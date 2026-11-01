from pathlib import Path
import re,subprocess,xml.etree.ElementTree as ET
from run_canny import ROOT,OUT
files=[e.attrib['name'] for e in ET.parse('Ti60_Demo.xml').iter() if e.tag.endswith('design_file') and Path(e.attrib['name']).exists() and not e.attrib['name'].endswith(('R0_FIFO_32.sv','lcd_para.v','lcd_driver.v','lcd_display.v','example_top.v'))]
header=re.sub(r'`timescale[^\n]*','',Path('src/lcd_para.v').read_text(encoding='utf-8'))
for name in ['lcd_driver','lcd_display']:
 text=Path('src/'+name+'.v').read_text(encoding='utf-8')
 text=re.sub(r'`include\s+"[^\"]*lcd_para.v"',lambda m:header,text)
 path=OUT/(name+'_elab.v');path.write_text(text,encoding='utf-8');files.append(str(path))
top=Path('example_top.v').read_text(encoding='utf-8')
declarations=[]
for text in ['wire canny_capture_ready;','wire shape_busy;', 'reg [7:0] status_meta,status_sync,status_display;', 'wire [23:0] plate_rgb;','wire plate_ready,plate_overflow,plate_low,plate_toggle;', 'wire plate_recognized_locked,plate_recognized_valid;wire [47:0] plate_recognized_ascii;', 'wire [3:0] plate_count;','wire [7:0] plate_threshold;', 'wire [9:0] plate_fps;','reg [9:0] plate_fps_osd;']:
 if text in top:top=top.replace(text,'',1);declarations.append(text)
anchor='    camera_full_view #'
top=top.replace(anchor,'\n'.join(declarations)+'\n'+anchor,1)
path=OUT/'example_top_elab.v';path.write_text(top,encoding='utf-8');files.append(str(path))
r=subprocess.run([str(ROOT/'tools/sim/mingw64/bin/iverilog.exe'),'-g2012','-i','-tnull','-I','src','-s','example_top',*files],text=True,capture_output=True)
(OUT/'top_elaboration.log').write_text(r.stdout+r.stderr,encoding='utf-8')
if r.returncode:print(r.stdout+r.stderr);raise SystemExit(r.returncode)
print('PASS real split top elaboration (vendor black boxes; LCD header and old declarations adapted only in simulation copy)')
