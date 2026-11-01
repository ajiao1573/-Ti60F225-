# 验证记录

## 已执行的软件与RTL验证

- host/tests/test_results.log：17项协议、串口和HTTP测试。
- host/tests/browser_smoke.log：中文页面、参数读回、断线及本地服务失效清除成功状态；使用独立假串口，无真实板端数据。
- tests/generated/host_uart.log：UART 115200收发、CRC/版本/范围、队列和忙处理。
- app_control_bridge.log：异步控制邮箱、原子状态、相机时钟停止清除过期成功。
- app_rearm.log：参数在实际处理结束后应用，帧尾不被复位截断。
- dynamic_crop.log、dynamic_crop_single.log：动态ROI归一化像素精确、各种比例和边界。
- panel_enclosure.log：牌面白色包络与字符掩码核对。
- single_roi_lock.log：两种普通牌格式、真实OCR、提交等待、拒绝与重识别。
- autoplate_core.log：实际Canny/历史选峰/定位/动态裁剪/字符OCR、原灰度预览、冻结帧ID，既有标定照片变位置和尺度回归。
- plate_locator.log：36个定位场景和事务，包括异步拒绝、冷却、边界及既有照片合成。
- single_gray_view.log：真实1080p30扫描四帧，缩放像素与404496字节预算、欠载检测和次帧恢复。
- single_gray_ddr.log、plate_transport.log：单幅DDR读取和原帧提交/冻结。
- b30_pipeline.log与metrics：1920×1080 RGB输入、84MHz/HTS2500/VTS1120的两连续30fps帧，经实际降噪和848×477流水线，无主动跳帧。该测试需在最新等价函数改写后重新完成，以最新日志为准。

日志位于tests/generated。测试覆盖不同子系统，不代表同一仿真包含整个摄像头、DDR PHY和HDMI物理链路。照片参与标定，不构成独立测试集。

## 最终交付前必须完成

最终Efinity完整compile、RAM容量检查、布局布线setup/hold检查、位流与最终源码对应校验及压缩包完整性。没有通过这些项目时，不应把源码目录称为已交付可烧录成品。

尚未进行实机摄像头、UART、HDMI及识别效果验收。

## 2026-10-29最终构建

Efinity map、interface、修正约束后pnr、最终pgm全部通过。RAM238/256，setup最小0.302ns，hold最小0.026ns。显示状态快照数据受20ns最大延迟约束；它由三拍握手同步后取样，未放宽普通运算路径。

最新b30_pipeline仿真PASS：两帧1920×1080/30fps RGB输入，每帧404496处理像素，无FIFO溢出/丢帧。该仿真耗时475.55秒。

自动完整流水线已验证AUY359两个位置/尺度、TR7750及848×477原生场景。现有DMN112、FAR441、OI7105的自动裁剪后OCR兼容性尚未完成改进，可能被严格置信度门槛拒绝；不得据本包宣称任意普通牌均可识别。保留359个逐字符模板及原拒绝门槛，没有为让样例通过而降低阈值。实机效果需上板验收。
