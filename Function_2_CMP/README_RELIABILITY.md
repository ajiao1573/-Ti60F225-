# 摄像头与 DDR 异常处理、1080P 验证

2026-10-29。当前功能版本为 `output/bean_1080p_reliability.bit`。
仍使用原生 1920×1080 RGB565、5×5 RGB 中值、边缘保护平滑、两像素红色轮廓及 K1 冻结。
此前去噪版和已确认显示正常的版本保留在 `output/bean_1080p_denoise.bit`、
`output/bean_1080p_display_fix.bit`。

## 摄像头初始化

- 四个字节的 ACK 均参与判定。失败时重试同一寄存器，默认最多重试 3 次；耗尽后保持失败索引，不报告配置完成。
- 重试间隔 1ms；写入 `0x3008[7]` 软件复位后等待 5ms。原表中只有等待注释，本版将等待落实到控制器。
- 检查 SDA 空闲并提供超时保护。默认实际配置的无响应超时为 20ms，终止后释放 SDA；恢复需系统复位或重新加载。
- 配置写入结束后将总线交给 `camera_sccb_verify.v`，使用 STOP 分隔的 SCCB 读操作回读：
  芯片 ID `0x300A/B=0x5640`、宽度 `0x3808/9=1920`、高度 `0x380A/B=1080`、格式 `0x4300=0x61`。
- 回读同时检查地址 ACK、返回值、重试次数和超时。全部匹配后才使能摄像头数据进入 DDR。
- 状态改变进入像素域时经过两级同步。初始化错误显示 ERROR，并隐藏旧数量。

## DDR 帧与协议保护

- 写入成功响应和 ID 检查通过、帧长度恰好等于 `VIDEO_WIDTH*VIDEO_HEIGHT*2`，且未发生 FIFO 溢出，才发布缓存。
- 失败、短帧、额外数据和跨越多个 EOF 的帧不发布。原生 1080P 每帧为 4,147,200 字节，恰好 2025 个 2048 字节突发。
- 支持的帧大小必须是完整突发的整数倍；本版不补齐不完整帧。`C_WR_FRAME_BYTES` 默认跟随 `C_RD_END_ADDR`。
- 检查读响应、读 ID 和 RLAST/突发长度。错误时停止向显示 FIFO 提供新数据，隐藏计数，在下一显示帧尝试恢复。
- VSync 出现时先排空旧读事务，再切换读缓存。等待 ARREADY 时保持 ARVALID/ARADDR，避免帧边界破坏未完成的地址握手。
- 监测写 FIFO 满和显示 FIFO 空。错误状态使 CCA 工作失效；恢复后从完整帧重新分析，冻结图也会重新计算。
- AXI 在 9,600,000 个时钟内没有握手进展（96MHz 下约 100ms）时请求共同复位；超过 ARLEN 而没有 RLAST 也请求共同复位。
- `example_top.v` 将 DDR 控制器、地址仲裁器、主机、FIFO 和缓存管理一起复位 1024 个系统时钟，再重新校准。
  超时前保持尚未完成的 AXI VALID；不会只撤销主机命令而保留旧 DDR 响应。

`axi4_ctrl` 的 `error_status_o` 为本次 DDR 复位以来的粘滞标志：

| 位 | 含义 |
|---|---|
| 0 | 写响应/写 ID 错误 |
| 1 | 读响应/读 ID/读长度错误 |
| 2 | FIFO 溢出或欠读 |
| 3 | AXI 无进展超时 |
| 4 | 帧字节数不正确或有额外残留 |
| 5 | 超过约定读长度且缺少 RLAST |

RTL 另提供饱和的写错误、读错误和 FIFO 错误计数端口。当前 HDMI 界面只使用实时 ERROR/数量失效状态；
这些计数端口尚未映射到串口或屏幕，不应把未接入的内部端口当成可读的实机遥测。

## 显示启动修正

`lcd_driver.v` 复位时明确将 HS/VS 设置为非活动电平。此前 VS 在首行结束前未初始化，
导致两态与四态仿真对第一个帧边界的处理不同。本版检查真实行场时序，不在测试中跳过这个差异。

## 复现

```powershell
python sim/run_bean_tests.py
python sim/run_video_path_test.py --1080p
python sim/run_native_1080p.py
./sim/build_reliability.ps1
# 连接开发板后，校验当前源码/位流哈希并执行 JTAG 易失加载：
./sim/program_reliability.ps1
```

默认 Icarus 回归增加 SCCB 故障、关键寄存器回读、AXI 故障和来源失效后的冻结恢复测试。
扩展冻结保持 30 帧，软件执行时限为 1200 秒。软件时限并非 FPGA 的处理时延。

`run_video_path_test.py --1080p` 使用实际 FIFO 数据/控制 RTL，替换厂商加密的复位同步器为其接口模型，
检查全部 2,073,600 个 RGB565 像素，覆盖 84/96/74.4MHz 三个时钟及 AW/W/R 停顿。

`run_native_1080p.py` 使用 Verilator 与已有的独立空间参考检查连续两帧：
共 4,147,200 个去噪/轮廓像素、实际 2200×1125 时序和 960×540 连通域计数，预期 3 个目标。
Icarus 小图/原生行宽回归仍承担四态仿真检查。Verilator 本地工具来自
[PyPI 的 verilator 包](https://pypi.org/project/verilator/)，安装在 `build/tools/verilator`，使用已有 Visual Studio C++ Build Tools 编译。

日志和逐次构建输入哈希位于 `build/reliability/`、`build/reliability_bitstream/`、`build/bean_project/input_sha256.json`。
构建在开始时保存输入哈希，发布前再次比较，拒绝编译途中修改过输入的位流。

## 实机验收边界

下载成功、摄像头回读保护、软件仿真通过，分别只证明各自检查范围。
实机画面完整性、最终 5×5 版本的实际去噪效果、人工已知数量的准确率、K1 冻结/恢复，
以及长时间运行仍需实际观察。当前状态以 `output/bean_1080p_reliability.hardware_validation.json` 为准。
JTAG 使用易失加载，不写启动 Flash。
共同复位会重建 DDR 缓存；发生此类故障前冻结的图像不能保证保留。
