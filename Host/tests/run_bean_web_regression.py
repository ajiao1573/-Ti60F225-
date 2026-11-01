"""Targeted regression with declaration-order compatibility for local Icarus.
Only a simulation copy of the legacy OSD is reordered; logic is unchanged.
"""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];BEAN=ROOT/'Function_2_CMP'
SIM=ROOT/'Function_1_CMP/tools/sim/mingw64/bin'
os.environ['PATH']=str(SIM)+os.pathsep+os.environ.get('PATH','')
OUT=ROOT/'Host/tests/rtl_results';OUT.mkdir(exist_ok=True)
osd=(BEAN/'src/bean/bean_osd.v').read_text(encoding='utf-8')
decl='    reg displayed_valid, displayed_error, displayed_busy, displayed_frozen;'
assert osd.count(decl)==1
osd=osd.replace(decl,'').replace('    assign display_ready_o=',decl+'\n    assign display_ready_o=')
copy=OUT/'bean_osd_sim.v';copy.write_text(osd)
sources=[str(p) for p in sorted((BEAN/'src/bean').glob('*.v')) if p.name!='bean_osd.v']+[str(copy)]
tests=['bean_freeze_denoise_tb'] if '--freeze-only' in sys.argv else ['bean_objects_tb','bean_cca_objects_tb','bean_video_tb','bean_freeze_denoise_tb']
for name in tests:
    exe=OUT/(name+'.vvp')
    module='bean_freeze_tb' if name=='bean_freeze_denoise_tb' else name
    options=['-Pbean_freeze_tb.DENOISE_ENABLE=1'] if name=='bean_freeze_denoise_tb' else []
    c=subprocess.run([str(SIM/'iverilog.exe'),'-g2005-sv','-I'+str(BEAN/'src'),'-s',module,*options,'-o',str(exe),*sources,str(BEAN/'sim'/(module+'.v'))],cwd=BEAN,capture_output=True,text=True)
    if c.returncode:print(c.stdout+c.stderr);c.check_returncode()
    r=subprocess.run([str(SIM/'vvp.exe'),str(exe)],cwd=BEAN,capture_output=True,text=True,timeout=600)
    (OUT/(name+'.log')).write_text(r.stdout+r.stderr);print(r.stdout+r.stderr);r.check_returncode()
