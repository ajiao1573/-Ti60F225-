"""Compile standalone web-result firmware without touching previous releases."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('project',choices=['Function_2_CMP','Function_3'])
p.add_argument('--efinity',default='E:/software/Efinity')
a=p.parse_args()
root=ROOT/a.project
out=root/'output/host_web'; work=root/'work_host_web'
out.mkdir(parents=True,exist_ok=True); work.mkdir(exist_ok=True)
ns='http://www.efinixinc.com/enf_proj'
ET.register_namespace('efx',ns)
tree=ET.parse(root/'Ti60_Demo.xml')
for e in tree.iter():
    tag=e.tag.rsplit('}',1)[-1]
    attr='name' if tag in ('design_file','default_peri_file','peri_file') else 'path' if tag=='ip' else 'value' if tag=='param' and e.get('name')=='include' else None
    if attr and e.get(attr):e.set(attr,(root/e.get(attr)).resolve().as_posix())
proj=work/'Ti60_Demo.xml';tree.write(proj,encoding='utf-8',xml_declaration=True)
inputs=[root/'example_top.v',root/'Ti60_Demo.xml',root/'Ti60_Demo.peri.xml',root/'Ti60_Demo.pt.sdc']
inputs+=sorted((root/'src').rglob('*.v'))+sorted((root/'src').rglob('*.vh'))
def hashes():return {str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}
before=hashes();(out/'source_hashes.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
env=os.environ.copy();env['EFINITY_HOME']=a.efinity
env['PYTHONHOME']=a.efinity+'/python311'
env['EFXPT_HOME']=a.efinity+'/pt';env['EFXPGM_HOME']=a.efinity+'/pgm';env['EFXIPM_HOME']=a.efinity+'/ipm'
env['EFINITY_USER_DIR_INI']=str(Path(env['LOCALAPPDATA'])/'efinity/user_dir.ini')
env['PATH']=os.pathsep.join([a.efinity+'/python311/bin',a.efinity+'/bin',a.efinity+'/pgm/bin',env['PATH']])
with (out/'compile.log').open('w',encoding='utf-8') as log:
    code=subprocess.run([str(Path(a.efinity)/'bin/efx_run.bat'),str(proj),'--flow','compile','--output_dir',str(out),'--work_dir',str(work)],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
unchanged=hashes()==before
bit=out/'Ti60_Demo.bit'
summary={'project':a.project,'flow_exit_code':code,'inputs_unchanged':unchanged,'bitstream_exists':bit.exists(),
         'sha256':hashlib.sha256(bit.read_bytes()).hexdigest() if bit.exists() else None,'hardware_validated':False}
(out/'build_summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary),flush=True)
sys.exit(0 if code==0 and unchanged and bit.exists() else 1)
