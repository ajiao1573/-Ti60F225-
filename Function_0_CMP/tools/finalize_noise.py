"""Finalize only after the actual revised RTL and full-size checks pass."""
from pathlib import Path
import re,json,hashlib
root=Path(__file__).resolve().parents[1]
required=['mild_noise','960_pipeline','color_modes_fix','960_guard','960_history','video_keys','video_keys_no_history']
for name in required:
 s=(root/'tests/generated'/f'{name}.log').read_text();assert 'PASS' in s and 'FATAL' not in s,name
timing=(root/'output/Ti60_Demo.timing.rpt').read_text();table=timing.split('Setup (Max) Clock Relationship')[1].split('NOTE:')[0]
def rows(s):return [(m[0],m[1],float(m[2])) for m in re.findall(r'^\s+(\w+)\s+(\w+)\s+[-.\d]+\s+([-.\d]+)\s+\(',s,re.M)]
ss,hs=[rows(s) for s in table.split('Hold (Min) Clock Relationship')];assert min(v for a,b,v in ss+hs)>=0
pix=next(v for a,b,v in ss if a==b=='clk_pixel')
place=(root/'output/Ti60_Demo.place.rpt').read_text();resources='\n'.join(s for s in place.splitlines() if s.startswith(('XLRs:','Memory Blocks:','DSP Blocks:')))
metrics=json.loads((root/'tests/generated/mild_noise_metrics.json').read_text())
flat=metrics['flat24'];old=flat['thresholds']['22']['old_edge_percent'];new=flat['thresholds']['22']['new_edge_percent']
# DDR/display RTL is unchanged from the tested key/color fix. Retain that
# five-frame result with an explicit reuse label, rather than claiming a rerun.
baseline=root.parent/'ti60_A_960x720_60fps_fix'
for rel in ['src/axi/split_frame_ctrl.v','src/axi/R0_FIFO_32.sv','Ti60_Demo.peri.xml','Ti60_Demo.pt.sdc']:
 assert (root/rel).read_bytes()==(baseline/rel).read_bytes(),rel
verification=root/'verification';verification.mkdir(exist_ok=True)
if (baseline/'verification/960_stream.log').exists():
 (verification/'unchanged_ddr_previous_960_stream.log').write_bytes((baseline/'verification/960_stream.log').read_bytes())
report=f'''# 同源温和降噪与±1阈值步进验证

用户已确认：主档位1/5统一±1，长按逐档切换保持；低阈值优先保留细线和运动轮廓，允许少量残余噪点。现场报告THR22、灰度整体颗粒、平坦区散点和少量轮廓闪烁；算法名称及当前UND/TOT未取得。

## 修改

1. 阈值每次短按±1，0～1023饱和，不回绕。保留长按满1秒后松开逐档循环，不恢复旧两秒回第一档。
2. 所有五算法共用同一RGB前端；左灰度、彩色原图和右边缘来自同一处理后的像素。保留原3×3 binomial平滑，再增加一层保边平滑：新窗口三个RGB通道的局部极差均≤24且没有方向明显的弱边缘时做额外3×3 binomial，否则保留上一层中心像素。弱边缘使用相对条件2×轴向梯度≥7×局部极差识别，避免把低对比轮廓当成平坦区。额外平滑在平坦区域形成有效5×5支持，明显颜色/亮度边界保持原3×3结果。24是平滑区域判定，**不是边缘THR下限**。
3. 保留高阈值THR、低阈值floor(5×THR/8)，不改Sobel/Canny梯度定义、NMS和连接判定。运动保护除原mag≥2×THR条件，还要求切向两侧与中心具有相同量化方向、相同梯度极性、幅值至少为中心的3/4且不低于THR，避免低THR噪声峰轻易绕过投票。未禁用所有运动保护。
4. 摄像头寄存器、960×720/60目标时序、HDMI1080p60、状态区、RGB888行缓存、DDR布局及历史功能沿用前版。

## 量化对照

输入为48×32的固定种子模拟RGB图像，平坦128加逐帧独立均匀±24扰动；对照版和新版分别经过实际共同前端。统计排除5像素边界。此数据不是开发板实测。

- 平坦区左灰度标准差：{flat['gray_std_old']:.3f} → {flat['gray_std_new']:.3f}，下降{100*(1-flat['gray_std_new']/flat['gray_std_old']):.1f}%。
- THR22各算法散点比例：

| 算法 | 前版 | 新版 |
|---|---:|---:|
| Sobel | {old[0]:.3f}% | {new[0]:.3f}% |
| Sobel+Median | {old[1]:.3f}% | {new[1]:.3f}% |
| Canny | {old[2]:.3f}% | {new[2]:.3f}% |
| Canny+Median | {old[3]:.3f}% | {new[3]:.3f}% |
| MAJORITY3带运动保护 | {old[4]:.3f}% | {new[4]:.3f}% |

THR22下所测12灰度级弱阶跃、移动强轮廓、两像素细彩色线的边缘数量与前版一致；另在THR0/5/10/47检查无噪声目标的边缘数量保留率至少85%；含噪声弱阶跃以已知真实边界附近的逐行覆盖率检查THR≤22，不能把被删去的背景噪点误算为细节丢失。这不是对任意低对比细节的保证。THR接近0时仍可能有散点，优先保细节的温和方案不保证纯净黑底。完整数据见verification/mild_noise_metrics.json。

## 本轮检查

- `mild_noise` PASS：7类场景×5阈值×6帧，四种空间算法每种210帧；实际RGB前端、灰度、边缘、保护位、坐标/SOP/EOP与独立整数模型逐像素一致，含THR0/5/10/22/47。
- `960_pipeline` PASS：真实Bayer→新共同前端→四空间算法，完整960×720连续两帧，84MHz、HTS1600/VTS875输入，THR22；像素数、坐标、常量无边和阶跃完整，下一SOP前结束。
- `video_keys` PASS：±1完整上下范围和饱和、短按/长按、五档循环、显示/历史控制、28组比较及禁用历史配置。
- `color_modes_fix` PASS：96MHz AXI/148.5MHz HDMI，受限读速率下8次灰度/彩色切换逐像素正确、无欠载。
- `960_history` / `960_guard` PASS：完整历史冻结/回放/比较、恢复、兼容历史预热、保护位打包/读回和禁止旧帧鬼影。
- 实际顶层连接检查PASS。新增共同前端由include随顶层编译；完整综合、接口、布局布线、生成位流和导出PASS。
- DDR控制器、彩色行缓存与时钟约束逐字节未改，复用前版已通过的完整五帧96MHz DDR并发结果，日志单独标为`unchanged_ddr_previous_960_stream.log`，不冒称本轮重跑。

## 资源与时序

```
{resources}
```

所有受约束时钟关系最小建立余量{min(v for a,b,v in ss):+.3f}ns、最小保持余量{min(v for a,b,v in hs):+.3f}ns；148.5MHz显示时钟建立余量{pix:+.3f}ns。采用最终布线报告，非初步报告。原有未使用外设端口等警告仍存在。

## 实机边界

本版尚未烧录本板；仿真使用真实处理RTL和行为级FIFO/DDR，不模拟相机模拟噪声、DDR PHY及显示器电气接收。温和空间滤波无法完全消除高增益、曝光异常或传输欠载；若UND/TOT非0，须先排除传输问题。烧录后先保持THR22对照，再用±1微调，观察左灰度、平坦区散点、细线/运动轮廓、FPS与UND/TOT。相机配置实测限制仍见CAMERA_MODE.md。
'''
(root/'VALIDATION.md').write_text(report,encoding='utf-8')
(root/'IMPLEMENTATION_STATUS.md').write_text('已完成：主档位1/5±1步进、同源平坦区保边平滑、方向与极性一致的运动保护、低阈值实际RTL对照及完整960×720连续60Hz输入验证；编译和最终时序通过。新位流output/Ti60_Demo.bit。尚未上板实测；详见VALIDATION.md。\n',encoding='utf-8')
print(resources);print('PASS noise revision validation report; final pixel setup',pix)
