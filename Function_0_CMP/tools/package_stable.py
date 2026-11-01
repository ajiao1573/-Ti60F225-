"""Validate this revision and package its matching sources, bitstream and evidence."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile,difflib,subprocess,sys
root=Path(__file__).resolve().parents[1]
baseline=root.parent/'ti60_A_960x720_60fps_noise'
verification=root/'verification';verification.mkdir(exist_ok=True)
required=['stable_peaks','960_pipeline','color_modes_fix','960_guard','960_history','video_keys','video_keys_no_history']
for name in required:
 p=root/'tests/generated'/f'{name}.log';s=p.read_text()
 assert 'PASS' in s and 'FATAL' not in s,name
 shutil.copy2(p,verification/p.name)
rtl_time=max(p.stat().st_mtime for p in (root/'src').rglob('*.v'))
for name in ['960_pipeline','stable_peaks_48x32','stable_peaks_35x23']:
 log=root/'tests/generated'/f'{name}.log';vvp=log.with_suffix('.vvp')
 assert log.stat().st_mtime>=vvp.stat().st_mtime>=rtl_time,f'pending/stale RTL simulation: {name}'
top=subprocess.run([sys.executable,'tests/check_top.py'],cwd=root,check=True,text=True,capture_output=True)
assert 'PASS' in top.stdout
(verification/'top_elaboration.log').write_text(top.stdout+(root/'tests/generated/top_elaboration.log').read_text(),encoding='utf-8')
flow=(root/'build_960.log').read_text(encoding='utf-8',errors='replace')
for step in ['map','interface','pnr','pgm','export_bitstream']:
 assert re.search(r'\b'+step+r'\s*:\s*PASS',flow),step
shutil.copy2(root/'build_960.log',verification/'build_960.log')
timing=(root/'output/Ti60_Demo.timing.rpt').read_text()
assert 'status : final' in timing
table=timing.split('Setup (Max) Clock Relationship')[1].split('NOTE:')[0]
ss,hs=table.split('Hold (Min) Clock Relationship')
def rows(s):return [(a,b,float(v)) for a,b,v in re.findall(r'^\s+(\w+)\s+(\w+)\s+[-.\d]+\s+([-.\d]+)\s+\(',s,re.M)]
ss,hs=rows(ss),rows(hs);assert ss and hs and min(v for a,b,v in ss+hs)>=0
place=(root/'output/Ti60_Demo.place.rpt').read_text()
resources='\n'.join(s for s in place.splitlines() if s.startswith(('XLRs:','Memory Blocks:','DSP Blocks:')))
bit=root/'output/Ti60_Demo.bit';assert bit.stat().st_size>1000000
sources=[p for p in root.rglob('*') if p.is_file() and (p.relative_to(root).parts[0] in ['src','ip'] or p.parent==root and p.suffix in ['.v','.xml','.sdc'])]
changes=[];diff=[]
for p in sorted(sources):
 r=p.relative_to(root);old=baseline/r
 if r.name!='Ti60_Demo.xml':assert p.stat().st_mtime<=bit.stat().st_mtime,f'stale bit: {r}'
 if not old.exists() or old.read_bytes()!=p.read_bytes():
  changes.append(r.as_posix())
  if p.suffix in ['.v','.sv','.vh','.sdc','.xml']:
   a=old.read_text(encoding='utf-8',errors='replace').splitlines(True) if old.exists() else []
   b=p.read_text(encoding='utf-8',errors='replace').splitlines(True)
   diff.extend(difflib.unified_diff(a,b,fromfile='baseline/'+r.as_posix(),tofile='stable/'+r.as_posix()))
# The temporal NMS uses on-chip RAM; no DDR bandwidth/layout/clock changes.
for rel in ['src/axi/split_frame_ctrl.v','src/axi/R0_FIFO_32.sv','Ti60_Demo.peri.xml','Ti60_Demo.pt.sdc','src/camera_rgb_denoise.v','src/camera_rgb_smooth.v','src/cmos_i2c/ov5640_960x720_60_regs.v','src/video_key_control.v']:
 assert (root/rel).read_bytes()==(baseline/rel).read_bytes(),rel
previous=baseline/'verification/unchanged_ddr_previous_960_stream.log'
if previous.exists():shutil.copy2(previous,verification/'unchanged_ddr_previous_960_stream.log')
for p in (root/'tests/generated').glob('*stable*metrics*.json'):shutil.copy2(p,verification/p.name)
manifest={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[bit]}
(verification/'sha256.json').write_text(json.dumps(manifest,indent=2))
(verification/'source_changes.diff').write_text(''.join(diff),encoding='utf-8')
(verification/'changed_files.json').write_text(json.dumps(changes,indent=2))
report=f'''# Canny 弱轮廓稳定修复验证

现场条件：Canny+Median、THR27；相机和物体静止仍闪，左灰度有颗粒及明暗变化；自然光，UND/TOT为0。用户确认细节优先、温和降噪，接受最多约1帧响应变化，保留960×720/60fps与原功能。

## 本版实际改动

新增每像素1bit历史强峰记录。Canny及Canny+Median（含MAJORITY3的空间前端）采用带迟滞的NMS选峰；Sobel两种模式不变。

- 新种子依然要求当前梯度不低于显示THR及原切向支持条件；没有抬高THR或删除细节来制造黑底。
- 旧强峰只有在当前梯度不低于max(floor(5×THR/8),THR−3)、切向两侧仍支持、距邻近法线最大值不超过2级时才保持。邻近同方向、同极性历史位置抑制竞争新峰，减少一像素来回跳动。
- 持续满足保持条件的历史峰可以持续保留；这不是固定一帧超时。当前梯度失去支持时释放，防止只靠旧图保留轮廓。
- 算法/阈值改变后旧历史无效；切到Sobel清逻辑有效标志。历史RAM无需逐帧清零，完整同配置前一帧写完后才允许使用。
- 保留中值、两遍高斯及两轮局部弱边连接。减少高斯曾使模型平坦噪点显著增加，因此未采用。未改相机自动曝光/增益、左灰度、DDR布局、RGB888行缓存、HDMI状态显示及按键。

## 验证

本轮逐像素时域历史/边缘专项110帧（48×32与35×23各55帧）、完整960×720连续60Hz输入双帧、DDR投票/保护、冻结回放、彩色切换、按键和实际顶层检查均PASS，日志在verification。完整编译map/interface/pnr/pgm/export_bitstream均PASS。

专项覆盖的详细场景、帧数和量化数据以stable_peaks.log及对应metrics.json为准；包括历史位/32bit打包及末字、输入气泡、配置变更、静态弱边缘、运动和消失。模型对照也保存在tests/stability_audit，软件结果不冒充硬件实测。

DDR控制器/时钟/布局逐字节未改，复用之前五帧96MHz DDR并发测试，日志明确标记unchanged_ddr_previous_960_stream.log。本轮另外重新运行了960像素宽的guard/history及96MHz DDR的彩色切换回归。

## 最终资源及时序

```
{resources}
```

所有受约束关系最小建立余量{min(v for a,b,v in ss):+.3f}ns，最小保持余量{min(v for a,b,v in hs):+.3f}ns；显示148.5MHz建立余量{next(v for a,b,v in ss if a==b=='clk_pixel'):+.3f}ns，输入84MHz建立余量{next(v for a,b,v in ss if a==b=='cmos_pclk'):+.3f}ns。使用最终布线报告。原工程未使用外设/旧约束端点等警告仍存在。

位流SHA256：{manifest['output/Ti60_Demo.bit']}。

## 实机验证边界

尚未烧录本板。历史选峰不能恢复从未达到强种子条件的极弱单像素结构；更弱阴影覆盖增加时，总翻转数未必下降，不保证所有场景零闪烁。所测1像素/帧运动最多出现1像素位置滞后；这不是任意速度、光照下的统一延迟上限。左侧灰度及相机AE/AG未修改，源图整体明暗波动不属于本次已证实消除的问题。

烧录后以Canny+Median、THR27、相同自然光位置对照：观察细线连续性、阴影跳动、运动拖影、FPS60及UND/TOT0。若左侧整体明暗仍周期变化，需要进一步采集实际曝光/增益状态，不能仅凭离线模型认定或锁死曝光。
'''
(root/'VALIDATION.md').write_text(report,encoding='utf-8')
(root/'IMPLEMENTATION_STATUS.md').write_text('已完成Canny历史选峰稳定：专项逐像素、完整960×720连续60Hz、功能回归及最终编译/时序通过。新位流output/Ti60_Demo.bit；尚未上板。左灰度/AE未改，详见VALIDATION.md。\n',encoding='utf-8')
out=root.parent/'A_960x720_60fps_edge_stable.zip';prefix='A_960x720_60fps_edge_stable/'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(root.rglob('*')):
  if not p.is_file():continue
  r=p.relative_to(root)
  if r.parts[0] in ['work','work_pnr','work_syn','ooc','outflow','.git'] or '__pycache__' in r.parts:continue
  if r.parts[:2]==('tests','generated') or r.name=='.lock':continue
  if r.as_posix() in ['tools/migrate_960.py','tools/package_960.py','tools/finalize_noise.py']:continue
  if r.parts[0]=='output' and p.name not in ['Ti60_Demo.bit','Ti60_Demo.bit.bin','Ti60_Demo.timing.rpt','Ti60_Demo.place.rpt','Ti60_Demo.map.rpt','Ti60_Demo.pt.rpt','Ti60_Demo.pt_timing.rpt','Ti60_Demo.pinout.rpt','Ti60_Demo.warn.log','Ti60_Demo.err.log']:continue
  z.write(p,prefix+r.as_posix())
with zipfile.ZipFile(out) as z:
 assert z.testzip() is None
 assert hashlib.sha256(z.read(prefix+'output/Ti60_Demo.bit')).hexdigest()==manifest['output/Ti60_Demo.bit']
print(json.dumps({'zip':str(out),'bytes':out.stat().st_size,'bit_sha256':manifest['output/Ti60_Demo.bit'],'changed_sources':changes,'resources':resources},indent=2))
