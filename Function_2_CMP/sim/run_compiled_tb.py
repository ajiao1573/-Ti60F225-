"""Compile a named RTL testbench with the project-local Verilator/MSVC tools."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time

parser=argparse.ArgumentParser()
parser.add_argument('top')
parser.add_argument('--extra',nargs='*',default=[])
parser.add_argument('--param',action='append',default=[])
parser.add_argument('--out',default='build/runtime')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];os.chdir(root)
out=root/args.out;out.mkdir(parents=True,exist_ok=True)
vr=root/'build/tools/verilator/verilator';obj=out/('compiled_'+args.top)
sources=sorted((root/'src/bean').glob('*.v'))+[root/'sim'/f'{args.top}.v']+[root/p for p in args.extra]
inputs=sources+list((root/'src/bean').glob('*.vh'))
hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
env=os.environ.copy();env['VERILATOR_ROOT']=vr.as_posix()
with (out/f'{args.top}.compile.log').open('w') as log:
    subprocess.run([str(vr/'bin/verilator_bin.exe'),'--cc','--timing','--main','--exe',
        '-Wno-fatal','-Isrc','--top-module',args.top,'--Mdir',obj.as_posix(),
        *['-G'+v for v in args.param],*[p.as_posix() for p in sources]],env=env,
        stdout=log,stderr=subprocess.STDOUT,check=True)
vswhere=Path(os.environ.get('ProgramFiles(x86)','C:/Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
vcvars=Path(vs)/'VC/Auxiliary/Build/vcvars64.bat'
cpp=sorted(obj.glob('*.cpp'))+[vr/'include'/n for n in ('verilated.cpp','verilated_timing.cpp','verilated_threads.cpp')]
exe=out/(args.top+'.exe')
command='cl /nologo /std:c++20 /O2 /EHsc /MD /DVL_TIME_CONTEXT /D_CRT_SECURE_NO_WARNINGS '
command+=f'/I"{vr / "include"}" /I"{vr / "include/vltstd"}" '
command+=' '.join('"'+str(p)+'"' for p in cpp)+f' /Fe:"{exe}"'
batch=out/(args.top+'.cmd');batch.write_text(f'@echo off\ncall "{vcvars}" >nul\ncd /d "{obj}"\n{command}\nexit /b %ERRORLEVEL%\n')
with (out/f'{args.top}.cpp.log').open('w') as log:
    subprocess.run(['cmd','/c',str(batch)],stdout=log,stderr=subprocess.STDOUT,check=True)
start=time.monotonic()
with (out/f'{args.top}.log').open('w') as log:
    subprocess.run([str(exe)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1200)
result=(out/f'{args.top}.log').read_text()
if 'PASS' not in result: raise SystemExit('Testbench did not report PASS')
for p in inputs:
    if hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.relative_to(root))]:raise SystemExit(f'Input changed: {p}')
(out/f'{args.top}.result.json').write_text(json.dumps({'status':'PASS','top':args.top,
    'simulation_seconds':time.monotonic()-start,'input_sha256':hashes},indent=2))
print(result)
