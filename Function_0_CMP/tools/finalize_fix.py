"""Write this repair's validation report from final build/test results."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
timing=(root/'output/Ti60_Demo.timing.rpt').read_text()
table=timing.split('Setup (Max) Clock Relationship')[1].split('NOTE:')[0]
setup,hold=table.split('Hold (Min) Clock Relationship')
def rows(s):
 return [(m[0],m[1],float(m[2])) for m in re.findall(r'^\s+(\w+)\s+(\w+)\s+[-.\d]+\s+([-.\d]+)\s+\(',s,re.M)]
ss,hs=rows(setup),rows(hold)
assert ss and hs and min(v for a,b,v in ss+hs)>=0
pixel_s=next(v for a,b,v in ss if a==b=='clk_pixel')
pixel_h=next(v for a,b,v in hs if a==b=='clk_pixel')
place=(root/'output/Ti60_Demo.place.rpt').read_text()
resource='\n'.join(line for line in place.splitlines() if line.startswith(('XLRs:','Memory Blocks:','DSP Blocks:')))
for name in ['video_keys','video_keys_no_history','color_modes_fix','960_stream','960_history','960_guard']:
 s=(root/'tests/generated'/f'{name}.log').read_text();assert 'PASS' in s and 'FATAL' not in s
assert '5529600 visible pixels' in (root/'tests/generated/960_stream.log').read_text()
baseline=(root/'tests/generated/color_modes_baseline.log').read_text();assert 'FATAL' in baseline
report=f'''# KEY顺序切档与彩色分屏修复验证

本修复仅更改两个RTL文件：`src/video_key_control.v`、`src/axi/split_frame_ctrl.v`。原960×720工程和原压缩包保留。相机参数、五种边缘算法、阈值及1080p60布局未更改。

## 修改

1. 取消KEY-两秒回第一档。单键按满1秒后松开，KEY+前进一档，KEY-后退一档，五档循环；即使按住2秒、3秒、4秒，也只移动一档。短按继续调当前档位参数，组合键保留。
2. 彩色模式原先每行从DDR读取两次RGB888（共4个突发），分别供左右图。现只读一次（2个突发），左图显示同时写960×24bit同步行RAM，右图从该RAM读取并叠加同源红色边缘。RGB888不降位宽，RGB读取流量减半。每帧RGB读数据由5,529,600降为2,764,800字节，60Hz时约331.8降为165.9MB/s；灰度、边缘及历史数据另计。
3. 修正压力测试时钟：实际顶层 `w_ddr3_ui_clk=clk_sys` 为96MHz，上一版压力测试误用了192MHz。本次所有新增彩色压力/切换验证使用96MHz AXI、148.5MHz HDMI，摄像头84MHz。

## 回归结果

- `video_keys` / `video_keys_no_history` PASS：长按顺序切档、两秒以上不回原点、跨首尾循环、短按、显示切换、冻结/回放、全部28组历史比较、关闭历史配置。
- `color_modes_baseline` 是预期失败的旧版对照：96MHz、随机读取有效率25%的相同模型下，第二行彩色输出即出现缺像素。
- `color_modes_fix` PASS：上述相同模型下8次灰度/彩色切换，帧内模式稳定，全部RGB888/红边像素正确，每行仅2个RGB突发，UND/TOT为0。
- `960_stream` PASS：真实96MHz时钟下5帧完整960×720连续60Hz采集，随机AXI停顿、投票及彩色显示并发；每帧在下一SOP前提交，5,529,600个并发显示像素无欠载，最终完整720行左右图逐像素正确。
- `960_history` / `960_guard` PASS：环形历史、冻结、完整回放/比较、恢复、兼容帧预热和运动边缘保护。
- 实际工程源清单顶层连接检查PASS；综合、接口、布局布线、位流生成及导出PASS。没有使用初步布局报告中的时序作最终结论。

## 最终时序与资源

HDMI148.5MHz建立余量 {pixel_s:+.3f}ns，保持余量 {pixel_h:+.3f}ns。所有受约束时钟关系的最小建立余量 {min(v for a,b,v in ss):+.3f}ns，最小保持余量 {min(v for a,b,v in hs):+.3f}ns。

```
{resource}
```

行缓存新增3块RAM。编译仍有原工程未使用外设端口及部分端口宽度警告，不是零警告构建。报告和测试日志见 `verification/`、`output/Ti60_Demo.timing.rpt`。

## 实机确认范围

用户报告的花屏闪烁及UND/TOT=999表明实机存在持续显示欠载。本次修复已在受限读取模型中通过旧版失败、新版通过的对照；该模型不能确定实机所有DDR停顿分布，也不模拟DDR PHY。新位流尚未烧录到本板验证。烧录新版本并复位后，切到第三档彩色模式，观察完整左右图及UND/TOT是否保持0。相机模式实测限制仍见 `CAMERA_MODE.md`。
'''
(root/'VALIDATION.md').write_text(report,encoding='utf-8')
(root/'IMPLEMENTATION_STATUS.md').write_text('源码修改、针对性回归、完整编译和最终时序检查通过。修复内容：KEY+/-长按始终逐档循环，取消两秒回第一档；RGB888行缓存将彩色DDR读取减半。新位流output/Ti60_Demo.bit。详见VALIDATION.md。尚未在本板烧录实测。\n',encoding='utf-8')
print(resource)
print(f'PASS final setup/hold; pixel {pixel_s:+.3f}/{pixel_h:+.3f}ns')
