# OV5640 960×720 / 60 Hz 配置依据与验证范围

新模式文件：`src/cmos_i2c/ov5640_960x720_60_regs.v`。原始模拟初始化表保留，最后的模式覆盖改为中心窗口、2×2 binning、RAW8，无 ISP 缩放。

- XVCLK 24 MHz；PLL 和 DVP 字节时钟沿用原工程的 84 MHz 配置。
- 模拟窗口 `(320,250)..(2303,1705)` 为 1984×1456；采样后992×728，offset16/4裁出960×720。
- HTS1600、VTS875，理论 `84000000/(1600×875)=60 fps`；帧间155行约2.95 ms。
- 曝光上限871行，夜景延长帧关闭；50/60Hz bandstep分别525/437行。
- 原翻转方向保留，3820/3821由46/00改47/01以启用binning。

依据：本地OmniVision OV5640 v2.1手册的Table2-1（RAW720p/84MHz/60fps）、4.2（窗口/offset）及7.7（采样增量/翻转）；板卡所附I2C_OV5640_1280720_Config.v的模拟配套；[Linux OV5640驱动](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/ov5640.c)及[OpenMV OV5640驱动](https://github.com/openmv/openmv/blob/master/drivers/sensors/ov5640.c)。

限制：960×720、HTS1600/VTS875是由上述资料推导的候选，尚未在本板实测。Linux的HTS1600存在CSI上下文，不能当成本板DVP验证。OpenMV报告HTS小于1438可能使传感器停止，因此没有采用算术上同样为60fps的HTS1400/VTS1000。

上板需确认：CAM READY，W0960/H0720、输入IN约60、处理FPS约60；静止和彩色物体的方向、Bayer颜色正确；所有实时算法及彩色模式UND/TOT保持0。HDMI为1080p60：像素148.5MHz，2200×1125总时序，四路TMDS使用half-rate串行、742.5MHz快时钟（1485Mbps）。离线仿真和时序报告不能代替这些相机/显示器/DDR物理链路检查。
