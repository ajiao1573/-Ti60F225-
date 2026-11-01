"""Fast native DDR/FIFO roundtrip using the same testbench as the Icarus run."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
os.chdir(root)
out=root/'build/reliability'
out.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,'sim/run_video_path_test.py','--prepare-only'],check=True)
vr=root/'build/tools/verilator/verilator'
obj=out/'verilated_axi'
sources=[root/p for p in ('build/sim/W0_FIFO_8_portable.sv','build/sim/R0_FIFO_16_portable.sv',
    'src/axi/axi4_ctrl.v','src/bean/video_frame_banks.v','sim/axi_video_roundtrip_tb.v')]
hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
env=os.environ.copy();env['VERILATOR_ROOT']=vr.as_posix()
with (out/'axi_compiled_build.log').open('w') as log:
    subprocess.run([str(vr/'bin/verilator_bin.exe'),'--cc','--timing','--main','--exe',
        '-Wno-fatal','--top-module','axi_video_roundtrip_tb','-GHEIGHT=1080',
        '--Mdir',obj.as_posix(),*[p.as_posix() for p in sources]],env=env,
        stdout=log,stderr=subprocess.STDOUT,check=True)
vswhere=Path(os.environ.get('ProgramFiles(x86)','C:/Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
vcvars=Path(vs)/'VC/Auxiliary/Build/vcvars64.bat'
if not vcvars.is_file(): raise SystemExit('Visual Studio C++ Build Tools not found')
cpp=sorted(obj.glob('*.cpp'))+[vr/'include'/n for n in ('verilated.cpp','verilated_timing.cpp','verilated_threads.cpp')]
exe=out/'axi_1080p.exe'
command='cl /nologo /std:c++20 /O2 /EHsc /MD /DVL_TIME_CONTEXT /D_CRT_SECURE_NO_WARNINGS '
command+=f'/I"{vr / "include"}" /I"{vr / "include/vltstd"}" '
command+=' '.join('"'+str(p)+'"' for p in cpp)+f' /Fe:"{exe}"'
batch=out/'build_axi.cmd'
batch.write_text(f'@echo off\ncall "{vcvars}" >nul\ncd /d "{obj}"\n{command}\nexit /b %ERRORLEVEL%\n')
with (out/'axi_cpp_build.log').open('w') as log:
    subprocess.run(['cmd','/c',str(batch)],stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'axi_1080p_compiled.log').open('w') as log:
    subprocess.run([str(exe)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
result=(out/'axi_1080p_compiled.log').read_text()
if 'PASS RGB565 DDR roundtrip: 1920x1080, 4147200 bytes, 2025 bursts' not in result:
    raise SystemExit('Missing full-frame DDR roundtrip coverage')
for p in sources:
    if hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.relative_to(root))]:
        raise SystemExit(f'Simulation input changed: {p}')
(out/'axi_1080p.result.json').write_text(json.dumps({'status':'PASS',
    'bytes_checked':4147200,'bursts_checked':2025,'input_sha256':hashes},indent=2))
print(result)
