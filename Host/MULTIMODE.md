# 三模式接入与使用

## 启动与切换

双击`start_control.cmd`，或运行`dist/Ti60PlateControl.exe`。程序只绑定127.0.0.1，默认8765端口，自动打开本地网页。源码启动为`python app.py`。

| 模式 | 位流入口 | 网页操作与结果 |
|---|---|---|
| 车牌自动识别 | `../Function_1_CMP/output/lens_corrected/Ti60_Demo.bit` | 号码、状态、帧ID、字符数、失败原因、定位框、FPS、欠载；重新识别、启动/暂停、阈值/字符偏移 |
| 豆子计数 | `../Function_2_CMP/output/host_web/Ti60_Demo.bit` | 数量、实际可见框数、分析批次、冻结状态、阈值、视图、极性、ROI、错误字；冻结/恢复 |
| 零件检测测试 | `../Function_3/output/host_web/Ti60_Demo.bit` | OK/NG/INVALID、有符号ACC、样本号、原始/筛选后点数和错误原因码；采样、清除/取消 |

加载相应位流后连接COM口，确认“板端应答正常”。新豆子和零件位流的构建状态、源输入哈希、位流SHA256分别在各自`output/host_web/build_summary.json`和`source_hashes.json`。**旧版豆子/零件位流没有此结果协议，单独升级Host不会令旧位流产生数据。**

收到有效身份后网页自动跟随。手动查看其他标签时，会提示加载对应位流并隐藏本页结果、禁用控制。手动切换标签不下载固件、不发送跨模式指令。板端换位流但串口设备仍在时，下一次有效状态自动识别；若USB设备重枚举，刷新端口重新连接。

网页不传相机视频，画面继续从HDMI查看。豆子图像参数沿用板上双键菜单；网页显示实际应用配置。零件模式固定Canny+Median、THR27及原13维分类器；INVALID不属于NG，ACC不显示成有效分值。

结果没有使用演示值。状态超时1.2秒、断线、源时钟丢失、异常或模式不匹配后，当前成功号码、数量、分类和ACC失效。实时豆子分析可显示最近一次完成批次的数量，批次号标明来源；冻结/配置改变沿用原模块清除和重算机制。

零件采样收到ACK后，Host会等待新的采样编号或取消结果，期间屏蔽上一次分类并禁止重复采样，避免跨时钟快照延迟造成重复请求。清除/取消仍可使用。

## UART协议

沿用115200、8N1、无流控，帧为`A5 5A 01 SEQ CMD LEN PAYLOAD CRC8`。小端，载荷最多48字节；CRC8多项式07，初始0，覆盖版本至载荷。旧车牌状态48字节布局不变，见`../Function_1_CMP/docs/UART_PROTOCOL.md`。

任务ID：0=车牌，1=豆子，3=零件；功能位图使用`1<<任务ID`。未实现的任务ID2不接受。

| 命令 | 适用模式 | 参数 |
|---|---|---|
| 01 GET_STATUS | 全部 | 无，返回81+48字节状态 |
| 10/11/12/14 | 车牌 | 原阈值、字符偏移、重新识别、运行控制 |
| 13 SET_TASK | 全部 | 只允许当前任务ID；不同ID拒绝，不改变固件 |
| 20 SET_FREEZE | 豆子 | 1字节，0恢复、1冻结 |
| 21 SAMPLE | 零件 | 无；忙状态拒绝或等待源域可接受 |
| 22 CLEAR | 零件 | 无；清除显示、取消结果事务，内部数值核可完成后再接受新采样 |

ACK80载荷为原命令/错误：0接收，1参数错误，2不支持，3邮箱或检测忙。ACK不代表结果已完成。Host逐条发送、等待回复；每个命令前查询身份，固件也检查允许的命令，避免换位流后错误控制。

豆子和零件均使用资源精简UART，只保留一个在途回复，发送中不接收额外请求；主机串行拥有者保证不并发。先预留ACK再执行动作，坏CRC不执行，不会无应答地重试采样。

### 新增豆子/零件状态布局

| 字节 | 通用 | 豆子 task1 | 零件 task3 |
|---|---|---|---|
| 0/1 | 固件主版本1 / task | | |
| 2 | 状态 | 0未就绪/1实时/2忙/3冻结/4错误 | 0未就绪/1等待/2忙/3OK/4NG/5INVALID |
| 3 | bit0就绪，bit4异常，bit5结果有效，bit6冻结，bit7运行 | | INVALID可作为有效发布的检测结论，但无有效ACC |
| 4..5 | 阈值u16 | 实际生效阈值 | 27 |
| 6 | 模式配置 | bit0..1视图，bit2深色目标 | 3=Canny+Median |
| 7 | 原因 | 总体错误标志 | 分类器原因 |
| 8..11 | 结果 | 数量u16、当前可见框数u16 | 有符号ACC i32 |
| 12..13 | | 保留 | 筛选后点数u16 |
| 14/15 | | DDR粘滞错误字/菜单状态 | 扫描原因/分类ID |
| 16..23 | ROI x/y/width/height各u16 | 实际生效ROI | 扫描框128,8,704,704 |
| 24..27 | 输入/处理FPS | 当前不提供测量，标为未知 | 当前不提供测量，标为未知 |
| 28 | | 保留 | 数值核原因 |
| 30..31 | | 保留 | 原始扫描点数u16 |
| 32..35 | 结果ID u32 | 完成批次号 | 12位采样号零扩展 |
| 36..43 | 输入宽/高、处理宽/高，各u16 | 1920×1080 / 960×540 | 960×720 / 960×720 |
| 44 | 可选测量有效位 | bit0输入FPS、bit1处理FPS、bit2欠载；当前0 | 同左；当前0 |
| 45/46..47 | 协议1 / 功能位图u16 | 2 | 8 |

零件原因码含义：扫描0成功、1时序领先、2溢出、3灰度缺失；数值核1点不足、2中位数空、3退化、4坐标越界、5溢出、6非正、7奇异、8主元过小、9病态、10非椭圆、11中心异常、12精度、13零分母、14接纳点不足、15中位数秩异常、17负开方、18点过多。分类器原因0无、1特征无效、2越域、3编码格式、4取消、5算术、6复位、7外部错误。

## 实现与重建

`rtl/`为新增通信源；各工程`src/host/`保留独立副本，工程不依赖Host运行目录。豆子顶层接入像素域冻结和结果；零件顶层接入实时采样/取消及完整结果快照。已有UART引脚/电平保持原板卡配置。

状态快照、命令采用保持总线和三拍toggle握手跨域，源时钟心跳丢失时清除结果有效位；参数、数量、ACC和编号按同一源域事务取样。豆子框坐标存储按实际图像宽高收窄，保留128框、编号和显示延迟，配套逐像素边界回归。

```powershell
python -m unittest discover -s Host/tests -v
python Host/tests/run_result_rtl.py
python Host/tests/run_endpoint_payloads.py
python Host/tests/run_bean_web_regression.py
# Playwright为本机已有依赖，需要把所在node_modules加入NODE_PATH
node Host/tests/browser_multimode.cjs
python Host/build_exe.py
# Efinity默认E:/software/Efinity，输出均为新目录，不烧录
python Host/tools/build_web_firmware.py Function_2_CMP
python Host/tools/build_web_firmware.py Function_3
python Host/tools/verify_web_firmware.py Function_2_CMP
python Host/tools/verify_web_firmware.py Function_3
```

浏览器测试夹具只在`tests/ui_fixture.py`启动，正式服务及EXE没有模拟设备、注入或演示接口。网页截图来自明确标记的假串口自动化回归，不能作为上板截图或算法准确率证据。

本轮验证日志：`tests/multimode_python.log`、`tests/browser_multimode.log`、`tests/rtl_results/`。已有车牌位流未改动。新增两套位流的实际相机/DDR/显示和UART上板联调仍需下载后验证；本次工作不自动烧录。

## 2026-10-31 交付验证

| 交付物 | 结果 |
|---|---|
| Python协议、HTTP、三模式控制 | 28项通过，含切换前身份检查、过期失效、重复采样保护 |
| EXE和浏览器 | 独立EXE启动/串口枚举通过；三模式及7种视口宽度通过，无JS错误 |
| UART RTL | 完整/精简实现的真实串行比特、CRC、模式限制、跨域和源时钟丢失测试通过 |
| 实际端点字节布局 | 豆子零数量、ROI、错误失效；零件负ACC、编号、INVALID和清除与Python解码一致 |
| 豆子图像回归 | 128框/编号及最后像素、63组CCA对象、视频像素/OSD、异步冻结/恢复通过 |
| 豆子新位流 | XLR60140/60800；26组时钟关系通过，最小setup +0.211ns、hold +0.026ns |
| 零件新位流 | XLR57896/60800；24组时钟关系通过，最小setup +0.326ns、hold +0.026ns |

两套位流输入哈希在编译前后保持一致，位流SHA256与`release_validation.json`一致。旧工程中未使用接口的SDC警告仍存在；上述为已约束关系的最终报告，不等同于全部物理接口或上板准确率验证。第一次通信实现的容量/布线失败没有作为发布版本，零件失败日志保留于`first_uart_route/`。

`dist/`和`dist_fixed/`已同步为同一新版EXE，原`dist_fixed`成品保存在`backup_before_multimode/`。截图`tests/web_plate.png`、`web_beans.png`、`web_parts.png`、`web_mobile.png`来自测试夹具，不是实机结果。
