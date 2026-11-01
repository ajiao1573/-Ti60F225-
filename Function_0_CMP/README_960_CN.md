# A工程：960×720 / 60fps，Canny弱轮廓稳定版

打开 Ti60_Demo.xml；烧录 output/Ti60_Demo.bit。本目录为独立修复版本，上一版A工程和B工程未覆盖。最终检查结果见 VALIDATION.md，日志及源文件/位流SHA256见 verification/。

## 显示与操作

- 相机接口为OV5640 RAW8，目标960×720、60fps。HDMI为1920×1080、60Hz。
- 左右画面各完整960×720，位于y=180～899；上、下留白显示状态。保留灰度/边缘及彩色/红色边缘叠加模式。
- 五个主档位依次为阈值、算法、显示、历史、形状。KEY+是key1，KEY-是key0。
- 单键长按满1秒后松开：KEY+前进一档，KEY-后退一档，1～5循环；超过2秒仍只移动一档。短按调当前档位参数。主档位1和5阈值步进±1，0～1023饱和。
- 保留Sobel、Sobel+Median、Canny、Canny+Median和MAJORITY3，以及八帧冻结、回放、比较和形状功能。
- 状态区保留THR/FPS、档位/算法/显示模式、历史状态、UND/TOT、相机输入帧率与宽高等信息。

## 本版修复

Canny、Canny+Median及MAJORITY3的空间前端增加每像素1bit历史强峰参考，减少弱轮廓在相邻像素间来回跳动。只有当前梯度、方向邻域和双侧切向支持仍符合条件时才保持历史峰；失去当前支持就释放。算法/阈值切换后旧历史无效，Sobel两种算法不使用该机制。

新强种子的门槛仍为屏幕THR；已建立峰的保持门槛是max(floor(5×THR/8),THR−3)。例如THR27，新种子仍需27，保持门槛24，低候选门槛16。法线方向近峰允许2级差异。完整判定与边界见VALIDATION.md。

保留中值滤波、两遍高斯、两轮弱边连接；没有改相机曝光/增益、左灰度共同前端、DDR布局和RGB888行缓存。减少高斯虽可恢复部分弱边，但模型中平坦噪声明显反弹，因此未采用。

## 构建与检查

SDK默认C:/Efinity/2026.1，也可设置EFINITY_HOME。工程目录执行：

```
start_build.cmd compile
python tests/run_stable_peaks.py
python tests/run_960_pipeline.py
python tests/run_video_keys.py
python tests/run_color_modes_fix.py
python tests/run_960_guard.py
python tests/run_960_history.py
python tests/check_top.py
python tools/package_stable.py
```

专项110帧覆盖逐像素灰度/分类/边缘/保护/帧标记/历史位，及切换、输入间断、32位打包和部分末字。完整尺寸连续帧测试较慢。旧脚本有848/424尺寸假设，不能将所有历史测试直接当成本版本检查。

## 上板对照

先保持Canny+Median、THR27、相同自然光位置：检查细线连续性、阴影跳动、运动边缘是否拖影，以及输入IN约60、处理FPS约60、W0960/H0720、UND/TOT持续0。

本版尚未上板；离线仿真和最终时序通过不能代替相机、DDR PHY与显示器实测。相机候选时序说明见CAMERA_MODE.md。历史峰不能创造从未达到强种子条件的极弱单像素线，也不能保证所有场景零闪烁。左灰度整体明暗波动没有在本次被证实消除，仍需实际曝光/增益数据定位。
