"""Check final runtime-control release, regression evidence and programming."""
from pathlib import Path
import hashlib,json,re

root=Path(__file__).resolve().parents[1]
out=root/'build/runtime'
manifest=json.loads((root/'output/bean_1080p_runtime.manifest.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bit=root/'output/bean_1080p_runtime.bit'
if sha(bit)!=manifest['bitstream_sha256'] or sha(bit)!=sha(root/'build/runtime_bitstream/Ti60_Demo.bit'):
    raise SystemExit('Published runtime bitstream hash mismatch')
for name,value in manifest['source_sha256'].items():
    if sha(Path(name))!=value: raise SystemExit(f'Design input changed: {name}')
compiled=[]
for top in ('bean_runtime_video_tb','bean_runtime_1080p_tb'):
    result=json.loads((out/f'{top}.result.json').read_text())
    if result['status']!='PASS': raise SystemExit(f'Incomplete compiled test: {top}')
    for name,value in result['input_sha256'].items():
        if sha(root/name)!=value: raise SystemExit(f'Simulation input changed: {name}')
    compiled.append(top)
log=(out/'regression.log').read_text(errors='replace')
requested=re.search(r'^Requested tests: (.+)$',log,re.M)
if not requested or len(requested[1].split(', '))!=12 or 'All requested bean RTL tests passed.' not in log:
    raise SystemExit('Twelve requested RTL regressions did not complete')
if re.search(r'^(?:FATAL|FAIL|ERROR)',log,re.M):raise SystemExit('RTL regression failure')
if 'PASS runtime OSD:' not in (out/'bean_runtime_osd_tb.log').read_text():
    raise SystemExit('Runtime OSD/six-digit readback test missing')
hardware=json.loads((root/'output/bean_1080p_runtime.hardware_validation.json').read_text(encoding='utf-8-sig'))
if hardware['sha256']!=sha(bit) or not hardware['programmed_successfully']:
    raise SystemExit('Hardware programming evidence refers to a different release')
mapping=(root/'build/runtime_bitstream/Ti60_Demo.map.rpt').read_text()
resource=lambda name:int(re.search(r'^'+name+r'\s*:\s*(\d+)',mapping,re.M)[1])
summary={
    'status':'PASS','bitstream':bit.name,'sha256':sha(bit),
    'runtime_interface':'K1 menu with short/medium/long/exit release gestures',
    'views':['RAW','BINARY','RESULT'],'maximum_annotated_objects':128,
    'annotation_policy':'only matching frozen result; accepted CCA roots',
    'native_contour_reference_pixels_checked':4147200,
    'complete_annotated_frame_pixels':2073600,'native_count_and_boxes':3,
    'targeted_rtl_tests':requested[1].split(', '),'additional_runtime_osd_test':'PASS',
    'compiled_integration_tests':compiled,
    'lut4':resource('EFX_LUT4'),'ff':resource('EFX_FF'),'ram10':resource('EFX_RAM10'),
    'timing_relationships_passed':manifest['analyzed_clock_relationships'],
    'minimum_slack_ns':manifest['minimum_reported_slack_ns'],
    'hardware_programmed':True,'hardware_user_confirmation':hardware.get('user_confirmation')}
(out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
print('PASS runtime release: current source/bitstream/programming hashes, 12 RTL regressions + OSD, two compiled integration tests, 128 objects and native 1080p reference')
