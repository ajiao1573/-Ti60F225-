# 实测镜头标定与识别前去畸变（2026-10-31）

用户观察到画面边缘呈桶形/鱼眼状弯曲，摄像头没有厂家标定参数。本次使用当前 OV5640、当前 1920×1080 模式和手机显示的棋盘进行现场标定。没有套用其他镜头的系数。

## 采样与模型选择

标定诊断位流 `output/lens_calibration/Ti60_Demo.bit` 增加独立抓图通道：从真实摄像头灰度流每隔 6 个像素取样，输出 320×180 灰度图。它不受 OCR 冻结影响；UART 下载 57600 字节约需 9.5 秒。标定图片低于识别分辨率，**生产识别源图仍为 1920×1080**。

棋盘图 `docs/calibration/checkerboard_9x6.png` 为 10×7 方格、9×6 内角点和完整白边。先取 10 张训练图，覆盖中央、四角、左右/上下倾斜与远距离；再取左右两张独立验证图，未参加拟合。12 张均检测到 54 个角点。原图、角点预览、采样元数据分别保存在 `docs/calibration/frames/` 和 `holdout/`。

同时拟合普通径向/切向模型与 fisheye 模型。两者独立验证误差很接近，不能凭用户对弯曲的描述就断言一定是 fisheye 模型。首版采用普通模型，因为独立验证的棋盘直线残差略低，模型更简单。

| 指标 | 普通模型 | fisheye 模型 |
|---|---:|---:|
| 训练重投影 RMS，320×180 像素 | 0.06994 | 0.07025 |
| 独立验证平均 RMS，折算原生像素 | 0.36894 | 0.36518 |
| 验证 11 直线残差，校正前→后，缩略图像素 | 0.08653→0.02381 | 0.08653→0.02383 |
| 验证 12 直线残差，校正前→后，缩略图像素 | 0.13714→0.03952 | 0.13714→0.03960 |
| 采样全视场最小映射 Jacobian | 0.7590 | 0.7733 |

普通模型直线弯曲残差约下降 72%。这里的重投影误差衡量几何一致性，原生像素值由缩略图误差乘 6 得到，不是全分辨率角点实测值，也不是整牌识别准确率。全视场 Jacobian 仅在 16 像素网格采样检查，未发现折叠；不能替代所有摄像头/镜头/工作距离的验证。

所选参数 `docs/calibration/lens_profile_native1080.json`：

```text
fx = 2290.9347763265896     fy = 2291.3384632974644
cx =  946.5689294033366     cy =  570.894691080643
k1 = -0.3941783996744122
k2 = -0.010508829236389797
p1 =  0.0005992636723245479
p2 = -0.0007202768686834421
k3 =  1.1820158189083958
```

系数顺序遵循 OpenCV 普通模型 `[k1,k2,p1,p2,k3]`，不能当作 fisheye 四系数使用。参考 [OpenCV 标定模型](https://docs.opencv.org/4.13.0/d9/d0c/group__calib3d.html) 和 [fisheye 模型](https://docs.opencv.org/doc/doxygen/html/db/d58/group__calib3d__fisheye.html)。

## FPGA 接入范围

数据路径：1920×1080 灰度源帧 → 原生 Canny/定位 → 同帧车牌动态裁剪 → 256×96 归一化 ROI → **实测镜头去畸变** → 重新统计灰度/局部对比度 → 字符分割 → 六字符模板识别。

- 全帧定位和 HDMI 仍使用原始镜头坐标，因此 HDMI 画面仍可能有弯曲。框与原始图像继续对应；本版先校正识别用的车牌区域，未实现整帧 HDMI 校正，也未解决“定位器根本没有提出车牌候选框”的全部原因。
- `src/lens_roi_warp.v` 通过原生坐标中的 8 个边界点计算展开范围，再反向采样捕获 ROI，避免空洞；像素用双线性插值。
- `src/lens_grid_lookup.v` 复用插值运算，从 `src/calibration/lens_map.hex` 读取实测正反向网格。节点间隔 64 个原生像素，坐标为有符号 Q8，域扩展至画面外以支持边缘车牌。
- `tools/export_lens_rom.py` 用数值求逆生成映射，并保存参数与 ROM 的 SHA256。没有逐像素浮点运算或通用大除法器。
- 额外 24KB ROI 存储隔离采样源与目标。回写时交换新旧像素，保留同一源帧的原始 ROI。如果校正分割/OCR 被拒绝，恢复原图并重试一次；仍失败才发布拒绝结果、继续搜索。没有降低模板误差/差距门槛。
- 默认顶层参数 `LENS_CORRECTION=1`，`CALIBRATION_CAPTURE=0`。生产版移除 57.6KB 抓图缓冲以留出校正资源。重新现场标定可加载保留的诊断位流，或关闭校正并启用诊断参数后重新编译。

`tools/lens_geometry.py` 导出的 16 像素参考网格仅供软件核对，当前硬件实际消费的是 `export_lens_rom.py` 生成的 64 像素正反向 ROM，不能把两种文件混用。

## 仿真与验收

`tests/run_lens_warp.py`：1000 个实际参数正反向坐标样本逐项核对 RTL；独立浮点映射与 ROM 的抽样误差最大分别约 0.185/0.258 个原生像素。4 个 ROI 覆盖中央、左上、右下、y≥1024 的小车牌区域；98304 个双线性输出像素逐项一致；校正回写、直方图同步更新通过。单个 ROI 约 48.2～51.1 万时钟，按 84MHz 约 5.7～6.1ms，另加回写/重新统计约 0.59ms；这是该模块的仿真时延，不是整牌从搜索到锁定的延迟。

`tests/run_lens_ocr.py`：用当前实测模型生成已有 AUY359 回归图的模拟畸变。首轮校正图曾因牌框边缘重采样而 OCR 拒绝，因此加入同帧回退；测试要求原图恢复逐像素一致、AUY359 仍通过原门槛，空白/实心块继续拒绝且回退次数有界。这是模板回归，不是独立道路准确率证据。

`tests/test_lens_geometry.py`：普通/鱼眼模型、径向/切向方向、分辨率缩放、非法参数、坐标符号、输出文件互不覆盖等单元检查。`tests/run_calibration_capture.py`、`run_calibration_uart.py` 检查诊断抓图/传输。原生裁剪与 UART 常规回归仍需通过。

最终构建、时序、JTAG 与实机状态记录见本文件末尾的验收记录。更换镜头、调焦、改变 OV5640 读出裁剪/缩放模式后需重新标定，不能直接复用本次参数。

## 复现

```powershell
# OpenCV 拟合/验证使用 Efinity 自带 Python3.11 及 tools/vision_deps。
$env:PYTHONHOME='E:/software/Efinity/python311'
& E:/software/Efinity/python311/bin/python.exe tools/camera_calibration.py calibrate docs/calibration/frames docs/calibration/candidate_pinhole.json --model pinhole
& E:/software/Efinity/python311/bin/python.exe tools/verify_lens_calibration.py

# 选定并检查 profile 后生成真正的硬件 ROM，普通 Python 即可。
python tools/export_lens_rom.py
python tests/run_lens_warp.py
python tests/run_lens_ocr.py
```

软件全帧校正前后对比图：`docs/calibration/rectification_comparison.png`（左原图，右软件校正；不是 HDMI 校正截图）。

## 验收记录

- 构建目录：`work/lens_corrected_fallback_build`。map、interface、pnr、pgm、位流导出全部通过。发布文件：`output/lens_corrected/Ti60_Demo.bit`；根目录 `output/Ti60_Demo.bit` 及主要报告也同步为该版本。主工程和构建工程 XML 语义相同，RTL/映射 ROM 按字节核对。
- 最终资源：RAM223/256、DSP34/160、XLR40676/60800。最终 setup 最小报告值 **0.000ns**（HDMI `clk_pixel` 上升沿到下降沿，处在报告精度边界，没有额外余量），hold 最小0.026ns；校正所在 `cmos_pclk` 的 setup 余量1.933ns。没有放宽约束。不能把完成位流导出等同于有充足时序余量。
- 2026-10-31 11:39:14，经 Efinity Programmer 以 JTAG/6MHz 下载到设备 `0x10660A79`，Checksum `3AD794A0`。日志显示 `Device is in user mode!` 和 `Programming operation completed.`；仅临时JTAG下载，未写入SPI启动Flash。
- 实机 COM16 应答正常；输入及处理尺寸均1920×1080，输入30fps；解除冻结后处理30fps；显示本帧/累计欠载均0。JTAG日志、下载后状态分别保存在 `tests/generated/lens_corrected_programmer.txt`、`lens_after_download_state.json`。
- 下载前以用户确认的 OP2972 记录5次，4秒窗口内3次正确，成功耗时0.393/1.025/3.563秒，2次超时（`lens_before_benchmark.json`）。下载后初轮4次返回AUY359、1次超时，用户随后核对HDMI冻结画面的真实号码确为AUY359。图片已经改变，**这两组不能作为改进前后速度/准确率对照**；原始期望及核对说明均保留在 `lens_after_benchmark.json`，没有悄悄改写原始评分。
- 按AUY359重新测试的早期一轮5次均在4秒窗口内没有结果，候选框多为非车牌大小区域；记录为失败（`lens_AUY359_benchmark.json`），没有删除该轮失败记录。
- 用户随后按提示重新固定手机、确认车牌入镜并回复“可以测试”，立即启动相同5次/每次4秒窗口测试。**5次均以新的抓取帧ID正确锁定AUY359**，耗时分别为1.518、3.278、1.239、0.439、0.746秒，中位数1.239秒。每次输入30fps、显示累计欠载0；输入/处理均1920×1080。记录为 `tests/generated/lens_AUY359_fixed_benchmark.json`。
- 最长的3.278秒试验中，主机100ms采样多数为搜索状态，并读到“未分出六个字符”的最近拒绝记录；这提示进一步提速应检查候选定位和重试，而不是把全部等待归因于约6ms的校正模块。主机状态轮询包含重复读值，不能代替逐周期硬件性能剖析。
- 本轮完成实测参数、像素校正、同帧回退和固定AUY359工况的上板验证。**没有同一固定图的校正开/关对照，不能宣称已测得准确率提升，也不能将手机重新固定前后的成功次数当作算法收益。** 单张手机图5次正确不代表独立道路准确率，锁定耗时仍有波动。
