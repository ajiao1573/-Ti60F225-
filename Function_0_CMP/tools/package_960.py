"""Package only after required tests and the real compile flow have passed."""
from pathlib import Path
import hashlib,json,zipfile,shutil,re,difflib,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
required=['mild_noise','960_pipeline','color_modes_fix','960_guard','960_history','video_keys','video_keys_no_history']
for name in required:
 s=(root/'tests/generated'/f'{name}.log').read_text()
 assert 'PASS' in s and 'FATAL' not in s,name
assert (root/'tests/generated/mild_noise_metrics.json').exists()
flow=(root/'build_960.log').read_text(encoding='utf-8',errors='replace')
for step in ['map','interface','pnr','pgm','export_bitstream']:
 assert re.search(r'\b'+step+r'\s*:\s*PASS',flow),step
bit=root/'output/Ti60_Demo.bit';assert bit.stat().st_size>1000000
report=(root/'output/Ti60_Demo.timing.rpt').read_text()
table=report.split('Setup (Max) Clock Relationship')[1].split('NOTE:')[0]
slacks=[float(m.group(1)) for m in re.finditer(r'^\s+\w+\s+\w+\s+[-.\d]+\s+([-.\d]+)\s+\(',table,re.M)]
assert slacks and min(slacks)>=0,slacks
verification=root/'verification';verification.mkdir(exist_ok=True)
for name in required:shutil.copy2(root/'tests/generated'/f'{name}.log',verification/f'{name}.log')
for name in ['mild_noise.log','pipeline_960.log','color_modes_fix.log']:
 shutil.copy2(root/'tests'/name,verification/name)
shutil.copy2(root/'tests/generated/top_elaboration.log',verification/'top_elaboration.log')
shutil.copy2(root/'build_960.log',verification/'build_960.log')
shutil.copy2(root/'tests/generated/mild_noise_metrics.json',verification/'mild_noise_metrics.json')
baseline=root.parent/'ti60_A_960x720_60fps_fix'
changes=[];diff=[]
sources=[p for p in root.rglob('*') if p.is_file() and (p.relative_to(root).parts[0] in ['src','ip'] or p.parent==root and p.suffix in ['.v','.xml','.sdc'])]
for p in sorted(sources):
 rel=p.relative_to(root);old=baseline/rel
 if rel.as_posix()=='Ti60_Demo.xml':
  # Efinity rewrites identical project XML after exporting the bitstream.
  expected=old.read_text(encoding='utf-8').replace('ov5640_1080p30_regs','ov5640_960x720_60_regs')
  def xml_configuration(node):
   return (node.tag,tuple(sorted(node.attrib.items())),(node.text or '').strip(),tuple(xml_configuration(c) for c in node))
  assert xml_configuration(ET.fromstring(p.read_text(encoding='utf-8')))==xml_configuration(ET.fromstring(expected)), 'unexpected project configuration change'
 else:
  assert p.stat().st_mtime<=bit.stat().st_mtime, f'source newer than bitstream: {rel}'
 if not old.exists() or p.read_bytes()!=old.read_bytes():
  changes.append(rel.as_posix())
  if p.suffix in ['.v','.sv','.xml','.sdc']:
   a=old.read_text(encoding='utf-8',errors='replace').splitlines(keepends=True) if old.exists() else []
   b=p.read_text(encoding='utf-8',errors='replace').splitlines(keepends=True)
   diff.extend(difflib.unified_diff(a,b,fromfile='original/'+rel.as_posix(),tofile='960/'+rel.as_posix()))
(verification/'source_changes.diff').write_text(''.join(diff),encoding='utf-8')
manifest={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[bit]}
(verification/'sha256.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(verification/'changed_files.json').write_text(json.dumps(changes,indent=2),encoding='utf-8')
out=root.parent/'A_960x720_60fps_mild_noise_step1.zip'
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(root.rglob('*')):
  if not p.is_file():continue
  r=p.relative_to(root);parts=r.parts
  if parts[0] in ['work','.git','__pycache__'] or '__pycache__' in parts:continue
  if parts[:2]==('tests','generated'):continue
  if parts[0]=='output' and p.name not in ['Ti60_Demo.bit','Ti60_Demo.bit.bin','Ti60_Demo.timing.rpt','Ti60_Demo.place.rpt','Ti60_Demo.map.rpt','Ti60_Demo.pt.rpt','Ti60_Demo.pt_timing.rpt','Ti60_Demo.pinout.rpt','Ti60_Demo.warn.log','Ti60_Demo.err.log']:continue
  if r.as_posix()=='tools/migrate_960.py':continue
  z.write(p,'A_960x720_60fps_noise/'+r.as_posix())
with zipfile.ZipFile(out) as z:
 assert z.testzip() is None
 assert hashlib.sha256(z.read('A_960x720_60fps_noise/output/Ti60_Demo.bit')).hexdigest()==manifest['output/Ti60_Demo.bit']
print(json.dumps({'zip':str(out),'bytes':out.stat().st_size,'bit_sha256':manifest['output/Ti60_Demo.bit'],'changed_sources':changes},indent=2))
