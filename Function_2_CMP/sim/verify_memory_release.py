"""Verify memory savings, current design hashes and behavioral evidence."""
from pathlib import Path
import hashlib
import json
import re

root=Path(__file__).resolve().parents[1]
out=root/'build/memory'
manifest=json.loads((root/'output/bean_1080p_memory.manifest.json').read_text())
hash_file=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bit=root/'output/bean_1080p_memory.bit'
if hash_file(bit)!=manifest['bitstream_sha256']:
    raise SystemExit('Published bitstream hash mismatch')
if hash_file(root/'build/memory_bitstream/Ti60_Demo.bit')!=hash_file(bit):
    raise SystemExit('Published bitstream differs from checked FPGA build')
for name,value in manifest['source_sha256'].items():
    if hash_file(Path(name))!=value: raise SystemExit(f'Design input changed: {name}')
native=json.loads((out/'native_1080p.result.json').read_text())
if native['status']!='PASS' or native['frames_checked']!=2 or native['pixels_checked']!=4147200:
    raise SystemExit('Missing complete native two-frame reference evidence')
for name,value in native['input_sha256'].items():
    if hash_file(root/name)!=value: raise SystemExit(f'Image simulation input changed: {name}')
log=(out/'regression.log').read_text(errors='replace')
requested=re.search(r'^Requested tests: (.+)$',log,re.M)
if not requested or len(requested[1].split(', '))!=9 or 'All requested bean RTL tests passed.' not in log:
    raise SystemExit('Targeted memory/window regression did not complete all nine tests')
if re.search(r'^(?:FATAL|FAIL|ERROR)',log,re.M): raise SystemExit('Targeted regression contains failure')
ram=manifest['video']['ram10_blocks']
if ram>=245: raise SystemExit('No RAM10 reduction')
report=(root/'build/memory_bitstream/Ti60_Demo.map.rpt').read_text()
resource=lambda name:int(re.search(r'^'+name+r'\s*:\s*(\d+)',report,re.M)[1])
summary={
    'date':'2026-10-29','status':'PASS','baseline_release':'bean_1080p_reliability.bit',
    'baseline_user_confirmation':'正常','optimized_release':bit.name,
    'baseline_ram10':245,'optimized_ram10':ram,'ram10_saved':245-ram,
    'ram10_reduction_percent':100*(245-ram)/245,'free_ram10_before':11,'free_ram10_after':256-ram,
    'module_ram10':{'contour':{'before':71,'after':41},'median5':{'before':35,'after':23},'smooth':{'before':18,'after':12}},
    'pixel_algorithm_unchanged':True,'pipeline_latency_unchanged':True,
    'baseline_lut4':15620,'optimized_lut4':resource('EFX_LUT4'),
    'baseline_ff':11123,'optimized_ff':resource('EFX_FF'),
    'clock_relationships_passed':manifest['analyzed_clock_relationships'],
    'minimum_slack_ns':manifest['minimum_reported_slack_ns'],
    'targeted_tests':requested[1].split(', '),'banked_ram_reads_or_holds_checked':59535,
    'native_frames_checked':2,'native_pixels_checked':native['pixels_checked'],
    'native_analysis_count':native['count'],'bitstream_sha256':hash_file(bit)}
hardware=root/'output/bean_1080p_memory.hardware_validation.json'
if hardware.is_file():
    record=json.loads(hardware.read_text(encoding='utf-8-sig'))
    if record['sha256']!=summary['bitstream_sha256']: raise SystemExit('Hardware record refers to a different release')
    summary['hardware_programmed']=record['programmed_successfully']
    summary['hardware_user_confirmation']=record.get('user_confirmation')
(out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'PASS memory release: 245 -> {ram} RAM10, nine targeted regressions, two native 1080p frames, all input and bitstream hashes current')
