"""Compile the real final 5x5 RTL and existing full-frame reference test.

Windows: install the optional local tool with
  python -m pip install --target build/tools/verilator verilator==5.48.0
then run this script using an installed Visual Studio C++ Build Tools toolchain.
The default regression remains Icarus (four-state); this compiled test checks
every 1080p output pixel with the identical testbench and independent vectors.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time

root=Path(__file__).resolve().parents[1]
os.chdir(root)
out=root/'build/reliability'
out.mkdir(parents=True,exist_ok=True)
vr=root/'build/tools/verilator/verilator'
binary=vr/'bin/verilator_bin.exe'
if not binary.is_file():
    raise SystemExit('Local Verilator missing; see this script docstring. Icarus alternative: python sim/run_bean_tests.py --1080p')
vswhere=Path(os.environ.get('ProgramFiles(x86)','C:/Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
vcvars=Path(vs)/'VC/Auxiliary/Build/vcvars64.bat'
if not vcvars.is_file(): raise SystemExit('Visual Studio C++ Build Tools not found')
references=[root/'build/sim'/n for n in (
    'native_denoise_rect40.hex','native_denoise_rect50.hex','native_denoise_red_total.txt')]
if not all(p.is_file() for p in references):
    subprocess.run([sys.executable,'sim/generate_median_vectors.py','--kernel','5'],check=True)
sources=sorted((root/'src/bean').glob('*.v'))+[root/'src/lcd_driver.v',root/'sim/bean_1080p_tb.v']
inputs=sources+list((root/'src/bean').glob('*.vh'))+[root/'src/lcd_para.v',root/'sim/generate_median_vectors.py']+references
hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
obj=out/'verilated_1080p'
env=os.environ.copy();env['VERILATOR_ROOT']=vr.as_posix()
with (out/'verilator_compile.log').open('w') as log:
    subprocess.run([str(binary),'--cc','--timing','--main','--exe','-Wno-fatal',
        '--top-module','bean_1080p_tb','--Mdir',obj.as_posix(),'-Isrc',
        *[p.as_posix() for p in sources]],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
cpp=sorted(obj.glob('*.cpp'))+[vr/'include'/n for n in ('verilated.cpp','verilated_timing.cpp','verilated_threads.cpp')]
exe=out/'native_1080p.exe'
command='cl /nologo /std:c++20 /O2 /EHsc /MD /DVL_TIME_CONTEXT /D_CRT_SECURE_NO_WARNINGS '
command+=f'/I"{vr / "include"}" /I"{vr / "include/vltstd"}" '
command+=' '.join('"'+str(p)+'"' for p in cpp)+f' /Fe:"{exe}"'
batch=out/'build_native.cmd'
batch.write_text(f'@echo off\ncall "{vcvars}" >nul\ncd /d "{obj}"\n{command}\nexit /b %ERRORLEVEL%\n')
with (out/'native_cpp_build.log').open('w') as log:
    subprocess.run(['cmd','/c',str(batch)],stdout=log,stderr=subprocess.STDOUT,check=True)
start=time.monotonic()
with (out/'native_1080p.log').open('w') as log:
    subprocess.run([str(exe)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
result=(out/'native_1080p.log').read_text()
if 'PASS 1080p: 4147200 native contour pixels, median=1' not in result or 'count=3' not in result:
    raise SystemExit('Native test did not report complete reference coverage')
for p in inputs:
    if hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.relative_to(root))]:
        raise SystemExit(f'Input changed during simulation: {p}')
(out/'native_1080p.result.json').write_text(json.dumps({
    'status':'PASS','simulator':'Verilator (Python package 5.48.0) / MSVC C++20',
    'simulation_seconds':time.monotonic()-start,'frames_checked':2,'pixels_checked':4147200,
    'analysis_size':[960,540],'count':3,'input_sha256':hashes},indent=2))
print(result)
