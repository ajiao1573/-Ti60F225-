"""Publish only a completed, timing-clean measured-lens Efinity build."""
import hashlib,json,re,shutil
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
build=ROOT/'work/lens_corrected_fallback_build'
source=build/'output';target=ROOT/'output/lens_corrected'
log=(build/'compile_lens_corrected_final.log').read_text(encoding='utf-8-sig',errors='replace')
for flow in ['map','interface','pnr','pgm','export_bitstream']:
    if not re.search(r'^\s*'+flow+r'\s*:\s*PASS',log,re.M):raise RuntimeError('incomplete flow '+flow)
timing=(source/'Ti60_Demo.timing.rpt').read_text()
setup,hold=timing.split('Setup (Max) Clock Relationship',1)[1].split('Hold (Min) Clock Relationship',1)
hold=hold.split('NOTE:',1)[0]
def minimum(section):
    values=[float(s) for s in re.findall(r'^\s*\w+\s+\w+\s+[-\d.]+\s+([-\d.]+)\s+\(',section,re.M)]
    if not values or min(values)<0:raise RuntimeError('missing or failing timing')
    return min(values)
minimum_setup,minimum_hold=minimum(setup),minimum(hold)
usage=(source/'Ti60_Demo.place.rpt').read_text()
ram=int(re.search(r'Memory Blocks:\s*(\d+)',usage)[1])
dsp=int(re.search(r'DSP Blocks:\s*(\d+)',usage)[1])
if ram>256 or dsp>160:raise RuntimeError('resource budget exceeded')
hashes=json.loads((build/'SOURCE_SHA256.json').read_text())
def semantic_xml(element):
    return element.tag,sorted(element.attrib.items()),(element.text or '').strip(),tuple(semantic_xml(c) for c in element)
if semantic_xml(ET.parse(ROOT/'Ti60_Demo.xml').getroot())!=semantic_xml(ET.parse(build/'Ti60_Demo.xml').getroot()):
    raise RuntimeError('root/build project XML differ semantically')
for name,digest in hashes.items():
    if name=='Ti60_Demo.xml':continue # Efinity reformats this file; RTL remains byte-exact.
    if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('root changed after snapshot: '+name)
    if name.startswith('src/') or name=='example_top.v':
        if hashlib.sha256((build/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('build source changed: '+name)
target.mkdir(parents=True,exist_ok=True)
for suffix in ['bit','bit.bin','map.rpt','place.rpt','timing.rpt','route.rpt','cdc.rpt','hier_util.rpt']:
    shutil.copy2(source/f'Ti60_Demo.{suffix}',target/f'Ti60_Demo.{suffix}')
    shutil.copy2(source/f'Ti60_Demo.{suffix}',ROOT/f'output/Ti60_Demo.{suffix}')
shutil.copy2(build/'Ti60_Demo.xml',target/'build_project.xml')
shutil.copy2(build/'SOURCE_SHA256.json',target/'SOURCE_SHA256.json')
shutil.copy2(build/'compile_lens_corrected_final.log',target/'compile.log')
manifest=dict(source_snapshot=build.relative_to(ROOT).as_posix(),minimum_setup_ns=minimum_setup,
              minimum_hold_ns=minimum_hold,ram_blocks=ram,dsp_blocks=dsp,
              lens_correction=True,calibration_capture=False,input_size=[1920,1080],
              bitstream_sha256=hashlib.sha256((target/'Ti60_Demo.bit').read_bytes()).hexdigest(),
              hardware_status='not_downloaded')
(target/'BUILD_VALIDATION.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
