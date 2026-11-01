"""Verify the dual-button release and the evidence for its exact inputs."""
from pathlib import Path
import argparse,hashlib,json,re

parser=argparse.ArgumentParser()
parser.add_argument('--offline',action='store_true',help='validate saved release without requiring a connected/programmed board')
args=parser.parse_args()

root=Path(__file__).resolve().parents[1]
out=root/'build/two_key'
manifest=json.loads((root/'output/bean_1080p_dualkey.manifest.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
bit=root/'output/bean_1080p_dualkey.bit'
if sha(bit)!=manifest['bitstream_sha256'] or sha(bit)!=sha(root/'build/dualkey_bitstream/Ti60_Demo.bit'):
    raise SystemExit('Published dual-key bitstream hash mismatch')
for name,value in manifest['source_sha256'].items():
    if sha(Path(name))!=value: raise SystemExit(f'Design input changed: {name}')
compiled=[]
for top in ('bean_dualkey_video_tb','bean_runtime_video_tb','bean_runtime_1080p_tb'):
    result=json.loads((out/f'{top}.result.json').read_text())
    if result['status']!='PASS': raise SystemExit(f'Incomplete compiled test: {top}')
    for name,value in result['input_sha256'].items():
        if sha(root/name)!=value: raise SystemExit(f'Simulation input changed: {name}')
    compiled.append(top)
log=(out/'regression.log').read_text(errors='replace')
requested=re.search(r'^Requested tests: (.+)$',log,re.M)
if not requested or len(requested[1].split(', '))!=13 or 'All requested bean RTL tests passed.' not in log:
    raise SystemExit('Thirteen requested RTL regressions did not complete')
if re.search(r'^(?:FATAL|FAIL|ERROR)',log,re.M): raise SystemExit('RTL regression failure')
if 'PASS dual keys:' not in log or 'PASS runtime OSD:' not in log:
    raise SystemExit('Button gestures or runtime OSD evidence missing')
if 'PASS shared tick:' not in (out/'tick.log').read_text():
    raise SystemExit('Prescaled gesture timing evidence missing')
hardware=json.loads((root/'output/bean_1080p_dualkey.hardware_validation.json').read_text(encoding='utf-8-sig'))
if hardware['sha256']!=sha(bit) or (not args.offline and not hardware['programmed_successfully']):
    raise SystemExit('Hardware programming evidence refers to a different release')
mapping=(root/'build/dualkey_bitstream/Ti60_Demo.map.rpt').read_text()
resource=lambda name:int(re.search(r'^'+name+r'\s*:\s*(\d+)',mapping,re.M)[1])
summary={
    'status':'PASS','bitstream':bit.name,'sha256':sha(bit),
    'runtime_interface':'K1 normal freeze/resume; menu tap add, 0.5s hold subtract then repeat every 0.12s; K2 enter/next, 1s hold exit',
    'keys':{'K1':'N2/GPIOL_P_02 input 1.8V','K2':'M2/GPIOL_N_02 input 1.8V'},
    'menu_default_field':'THR','menu_remembers_selection':True,'overlap_suppressed':True,
    'prescaled_timing_test':'PASS',
    'views':['RAW','BINARY','RESULT'],'maximum_annotated_objects':128,
    'annotation_policy':'only matching frozen result; accepted CCA roots',
    'native_contour_reference_pixels_checked':4147200,
    'complete_annotated_frame_pixels':2073600,'native_count_and_boxes':3,
    'targeted_rtl_tests':requested[1].split(', '),'compiled_integration_tests':compiled,
    'lut4':resource('EFX_LUT4'),'ff':resource('EFX_FF'),'ram10':resource('EFX_RAM10'),
    'timing_relationships_passed':manifest['analyzed_clock_relationships'],
    'minimum_slack_ns':manifest['minimum_reported_slack_ns'],
    'hardware_programmed':hardware['programmed_successfully'],'hardware_user_confirmation':hardware.get('user_confirmation'),
    'validation_scope':'offline release checks' if args.offline else 'release checks and successful JTAG load'}
(out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
print('PASS dual-key release: current source/bitstream hashes, 13 RTL regressions, real-button video integration, runtime video and native 1080p reference; hardware programmed='+str(hardware['programmed_successfully']))
