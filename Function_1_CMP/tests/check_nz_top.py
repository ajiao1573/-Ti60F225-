"""Elaborate the top with vendor IP black boxes using Icarus.
Simulation-only copies remove an Efinity LCD-header timescale placement and
hoist existing forward declarations. No functional source is rewritten.
"""
from pathlib import Path
import re,subprocess,xml.etree.ElementTree as ET
from run_canny import ROOT,OUT
files=[e.attrib['name'] for e in ET.parse('Ti60_Demo.xml').iter()
 if e.tag.endswith('design_file') and Path(e.attrib['name']).exists()
 and not e.attrib['name'].endswith(('R0_FIFO_32.sv','lcd_para.v','lcd_driver.v','lcd_display.v','example_top.v'))]
header=re.sub(r'`timescale[^\n]*','',Path('src/lcd_para.v').read_text(encoding='utf-8'))
for name in ['lcd_driver','lcd_display']:
 text=Path('src/'+name+'.v').read_text(encoding='utf-8')
 text=re.sub(r'`include\s+"[^"]*lcd_para.v"',lambda m:header,text)
 path=OUT/('nz_'+name+'_elab.v');path.write_text(text,encoding='utf-8');files.append(str(path))
top=Path('example_top.v').read_text(encoding='utf-8')
declarations=[]
for text in ['wire canny_capture_ready;','wire shape_busy;',
 'reg [7:0] status_meta,status_sync,status_display;',
 'wire [23:0] plate_rgb;','wire plate_ready,plate_overflow,plate_low,plate_toggle;',
 'wire plate_recognized_locked,plate_recognized_valid;wire [47:0] plate_recognized_ascii;',
 'wire [3:0] plate_count;','wire [7:0] plate_threshold;',
 'wire [9:0] plate_fps;','reg [9:0] plate_fps_osd;']:
 assert top.count(text)==1,text
 top=top.replace(text,'',1);declarations.append(text)
anchor='    // Six gears;'
top=top.replace(anchor,'\n'.join(declarations)+'\n'+anchor,1)
# These declarations also feed the camera instance before the gear controls.
a=top.index('wire canny_capture_ready;');b=top.index('    // Six gears;',a)
block=top[a:b];top=top[:a]+top[b:]
anchor='    camera_full_view #'
if anchor not in top:
 anchor=next(line for line in top.splitlines() if 'camera_full_view #' in line)
top=top.replace(anchor,block+'\n'+anchor,1)
path=OUT/'nz_example_top_elab.v';path.write_text(top,encoding='utf-8');files.append(str(path))
r=subprocess.run([str(ROOT/'tools/sim/mingw64/bin/iverilog.exe'),'-g2012','-i','-tnull','-I','src','-s','example_top',*files],text=True,capture_output=True)
(OUT/'nz_top_elaboration.log').write_text(r.stdout+r.stderr,encoding='utf-8')
if r.returncode:print(r.stdout+r.stderr);raise SystemExit(r.returncode)
print('PASS full top elaboration: real top connections and new modules, vendor IP black boxes; original LCD headers/forward declarations adapted only in simulation copies')