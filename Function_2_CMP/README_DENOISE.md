# 1080P 强去噪

当前默认启用 **5×5 RGB 中值滤波 + 3×3 边缘保护加权平滑**。
发布位流为 `output/bean_1080p_denoise.bit`，同名 `.manifest.json` 记录源文件哈希、资源和时序。

## 算法与视频流水线

`src/bean/bean_rgb_median5.v` 对 R/G/B 各取 25 点的精确中值。
RGB565 邻域填充七个最大值至 32 项，经过 15 级流水线双调排序，选择排序后的第 13 项。
每时钟处理一个像素，去除孤立及小簇亮暗噪点，不依赖帧间平均。
中值的最外两行、两列透传中心像素，避免消隐和相邻帧影响边界。

`src/bean/bean_rgb_smooth.v` 再对 RGB 做 3×3 二项加权平均，权重为 `[1 2 1]' × [1 2 1] / 16`。
按 RGB565 精度四舍五入；邻域中任一通道极差超过 48（RGB888 标度）就保留中心，保护强边缘。
此级最外一行、一列透传。高频细纹理可能被平滑，较大的色斑和固定条纹仍可能存在。

两级滤波位于 DDR 显示读取后、预处理前，原图、轮廓、计数使用同一去噪流。
采集和帧缓存保持完整 1920×1080 RGB565；使用 RGB565 行缓存不额外损失原始颜色精度。
RGB 和 DE/HS/VS 的滤波端到端延迟为 `3*LINE_TOTAL+23`，当前为 6623 个像素时钟。
轮廓支路跳过旧的灰度高斯窗口，保留阈值、开闭运算及两像素红色内边界。
轮廓行缓存也按 RGB565 加三个同步位存储，输出时补零恢复原有 RGB888 格式。
总视频延迟约九行、0.27ms。K1 冻结、重新计数一次及 HOLD 显示继续使用同一流水线。

顶层参数：

- `BEAN_DENOISE_ENABLE=1`：启用去噪。
- `BEAN_DENOISE_MEDIAN_SIZE=5`：25 点中值；改为 3 可使用原来的九点中值模块。
- `BEAN_DENOISE_SMOOTH=1`：启用第二级加权平滑。

摄像头自动 DVP 分频、24MHz XVCLK、1080P 配置、PCLK 输入延迟和 DDR 写响应修复保持原先已验证的设置。

## 构建与验证

```powershell
python sim/run_bean_tests.py
./sim/build_bean.ps1
```

19 项默认 RTL 回归全部通过，包括 5×5 中值及后续轮廓的独立软件参考逐像素检查：
小图四帧、两次复位，共 28,672 个像素；另有 1920 像素原生行宽、2200 总时钟的 16 行测试。
后者完整检查 30,720 个有效像素和消隐同步，涵盖首末列、行缓存换行与彩色条带。
参考算法直接排序全部 25 项，与 RTL 双调网络独立；覆盖随机 RGB、椒盐噪点、颗粒、移动及空背景。
默认回归另验证开启 5×5 与平滑后的双时钟冻结、一次性计数、持续摄像头写入及恢复。
合成平坦区噪声 MSE 为 1436.50 → 中值 5.63 → 平滑 4.08，数值仅代表固定随机种子的仿真。

可选 `python sim/run_bean_tests.py --1080p` 进一步逐像素验证完整 1920×1080 帧及 960×540 计数，软件运行较慢。
最终 5×5 版的验证范围以本次日志为准；前两版的整帧长测已因升级算法中止，不宣称其整帧通过。
日志在 `build/sim/denoise_regression_v3.log` 及对应 `bean_median5_*_tb.log`。

当前 Efinity 的 map / interface / pnr / pgm / export_bitstream 全部 PASS。
资源为 14945 LUT4、10814 FF、245/256 RAM10、6 DSP24、1 DSP48。
26 组时钟关系满足约束，全工程最小报告 slack 为 0.025ns。
已通过 JTAG 易失加载到 ID `0x10660A79` 的 Ti60，未改写启动 Flash。
实拍反馈与位流哈希另记录在 `output/bean_1080p_denoise.hardware_validation.json`。

## 已保留的版本

`output/bean_1080p_contour.bit` 是本次构建的兼容别名。
已确认画面完整正常的无 RGB 去噪版保留在 `output/bean_1080p_display_fix.bit`，
另备份到 `output/archive/before_denoise/`，新的构建不会覆盖它。
前两版实机调试中的 3×3 中值版及 3×3 中值加平滑版分别归档在
`output/archive/median3x3/`、`output/archive/median3x3_smooth/`，用户均反馈需要进一步加强。
构建脚本会同步 GUI 工程的新模块列表；若 Efinity GUI 已打开旧工程，重新载入磁盘工程后再构建。
