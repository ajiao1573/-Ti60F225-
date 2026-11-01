"""Reject stale bitstreams, missing clocks, timing failures or wrong VF K1 pins."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import argparse

root = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output-dir',default='build/bean_bitstream')
parser.add_argument('--work-dir',default='build/bean_build')
parser.add_argument('--reliability',action='store_true')
args=parser.parse_args()
out=root/args.output_dir
flow=(root/args.work_dir/'flow.log').read_text(errors='replace')
for stage in ('map','interface','pnr','pgm','export_bitstream'):
    if not re.search(r'\b'+stage+r'\s*:\s*PASS',flow):
        raise SystemExit(f'Final build stage did not pass: {stage}')
timing = (out/'Ti60_Demo.timing.rpt').read_text()
summary = timing.split('Clock Relationship Summary (begin)')[1].split('Clock Relationship Summary (end)')[0]
slacks = [float(s) for s in re.findall(
    r'^\s+\w+\s+\w+\s+-?\d+\.\d+\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',summary,re.M)]
if not slacks or min(slacks)<0 or not re.search(r'clk_pixel\s+13\.441',timing):
    raise SystemExit('Invalid/missing clock constraints or negative reported timing slack')
if not re.search(r'clk_27m\s+41\.667\s+24\.000',timing):
    raise SystemExit('Camera XVCLK must be 24MHz (legacy port name clk_27m)')
top = (root/'example_top.v').read_text(encoding='utf-8')
if args.reliability:
    controller_top=top.split(') u_axi4_ctrl (',1)[1].split(');',1)[0]
    for signal in ('bid','bresp','bvalid','rid','rresp','rlast','rvalid'):
        if not re.search(r'\.axi_'+signal+r'\s*\(\s*w_ddr3_'+signal+r'\s*\)',controller_top):
            raise SystemExit(f'AXI checker must receive actual DDR {signal}')
for name,value in (('VIDEO_WIDTH',1920),('VIDEO_HEIGHT',1080),('BEAN_LINE_TOTAL',2200),('BEAN_DENOISE_ENABLE',1),('BEAN_DENOISE_SMOOTH',1),('BEAN_DENOISE_MEDIAN_SIZE',5)):
    if not re.search(r'\b'+name+r'\s*=\s*'+str(value)+r'\b',top):
        raise SystemExit(f'Incorrect native video parameter: {name}')
if '.C_RD_END_ADDR(VIDEO_WIDTH * 2 * VIDEO_HEIGHT)' not in top:
    raise SystemExit('DDR read extent must track native RGB565 frame size')
for signal in ('V','H'):
    if not re.search(r'\.vid_p'+signal+r'Sync\s*\(~bean_video_'+signal.lower()+r's\)',top):
        raise SystemExit('1080p HDMI requires positive sync at encoder input')
# Namespace spelling is obtained from the actual document, not hardcoded.
peri = ET.parse(root/'Ti60_Demo.peri.xml')
clocks = [e for e in peri.iter() if e.tag.endswith('comp_output_clock') and e.get('name')=='clk_27m']
if len(clocks)!=1 or clocks[0].get('out_divider')!='56':
    raise SystemExit('Camera reference PLL divider must be 56 for 24MHz')
lcd = (root/'src/lcd_para.v').read_text(encoding='utf-8')
if not re.search(r'^`define\s+VGA_1920_1080_30FPS_74_25MHz\s*$',lcd,re.M):
    raise SystemExit('Default display mode must select 1080p30 raster')
mapping = (out/'Ti60_Demo.map.rpt').read_text(errors='replace')
ram_blocks = int(re.search(r'^EFX_RAM10\s*:\s*(\d+)',mapping,re.M)[1])
if ram_blocks>256:
    raise SystemExit('Native-size design exceeds Ti60 block RAM capacity')
pins = (out/'Ti60_Demo.pinout.csv').read_text()
if not re.search(r'^N2,GPIOL_P_02(?:_CSI)?,key1_n_i(?:\.P)?,Input,1A,1\.8 V,',pins,re.M):
    raise SystemExit('VF K1 must be an N2 / GPIOL_P_02 1.8V input')
if 'key2_n_i' in top and not re.search(r'^M2,GPIOL_N_02(?:_CSO)?,key2_n_i(?:\.N)?,Input,1A,1\.8 V,',pins,re.M):
    raise SystemExit('VF K2 must be an M2 / GPIOL_N_02 1.8V input')
if re.search(r'^(?:N2|M2),[^\n]*,(?:Output|Clock Output),',pins,re.M):
    raise SystemExit('VF key pins must not be driven by unused LCD outputs')
for mapping in ('P15,GPIOR_25,led_o[0],Output,',
                'P14,GPIOR_22,led_o[1],Output,'):
    if mapping not in pins:
        raise SystemExit(f'Pin assignment does not match VF reference project: {mapping}')
ns = {'p':'http://www.efinixinc.com/enf_proj'}
project = ET.parse(root/'build/bean_project/Ti60_Demo.xml')
sources = [Path(e.get('name')) for e in project.findall('./p:design_info/p:design_file',ns)]
sources += [root/'Ti60_Demo.peri.xml',root/'Ti60_Demo.pt.sdc',root/'Ti60_Demo.xml']
# Included raster constants and IP settings affect the synthesized circuit.
for source in list(sources):
    if source.suffix in ('.v','.sv'):
        for name in re.findall(r'`include\s+"([^"\n]+)"',source.read_text(errors='replace')):
            include=next((p for p in (source.parent/name,root/'src'/name,root/name) if p.is_file()),None)
            if include is not None: sources.append(include.resolve())
sources.extend(sorted((root/'ip').glob('*/settings.json')))
sources=list(dict.fromkeys(sources))
bit = out/'Ti60_Demo.bit'
snapshot=root/'build/bean_project/input_sha256.json'
if snapshot.is_file():
    for name,expected_hash in json.loads(snapshot.read_text(encoding='utf-8')).items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=expected_hash:
            raise SystemExit(f'Design input changed during compilation: {name}')
if bit.stat().st_mtime < max(s.stat().st_mtime for s in sources):
    raise SystemExit('Bitstream predates one or more current design inputs')
manifest = {
    'bitstream_sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),
    'source_sha256':{str(s):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},
    'analyzed_clock_relationships':len(slacks),
    'minimum_reported_slack_ns':min(slacks),
    'key1':'N2/GPIOL_P_02 input, active low, 1.8V (VF core K1)',
    'video':{'width':1920,'height':1080,'line_total':2200,'frame_total_lines':1125,
             'pixel_clock_mhz':74.4,'display_hz':74_400_000/(2200*1125),
             'camera_xclk_mhz':24,'camera_format':'RGB565','camera_target_fps':15,'camera_pclk_mode':'auto',
             'analysis_width':960,'analysis_height':540,'frame_bytes':4_147_200,
             'bank_bytes':4_194_304,'ram10_blocks':ram_blocks,'contour_width_pixels':2,
             'denoise':{'algorithm':'exact RGB 5x5 median + edge-protected RGB 3x3 binomial smoothing','enabled':True,
                        'storage_format':'RGB565','border':'unchanged center pixel',
                        'latency_pixel_clocks':6623,'smooth_edge_threshold':48,'contour_gaussian_bypassed':True,
                        'contour_metadata_format':'RGB565 + DE/HS/VS'}},
}
if args.reliability:
    manifest['reliability']={
        'sccb_write_ack_checked':4,'sccb_max_retries':3,
        'sccb_reset_settle_ms':5,'sccb_retry_gap_ms':1,
        'verified_registers':['300a','300b','3808','3809','380a','380b','4300'],
        'axi_response_id_and_length_checks':True,'frame_byte_count_checked':True,
        'axi_no_progress_timeout_cycles':9600000,'shared_ddr_reset_cycles':1024,
        'failed_frame_policy':'discard, suppress count, recover on complete frame',
        'simulation_evidence_directory':'build/reliability',
        'hardware_validation':'not yet confirmed'}
if out.name=='memory_bitstream':
    if ram_blocks>=245:
        raise SystemExit('Banked-storage build did not reduce the 245-RAM10 baseline')
    manifest['memory_optimization']={
        'baseline_ram10':245,'optimized_ram10':ram_blocks,'ram10_saved':245-ram_blocks,
        'strategy':'512-word banks for wide line and metadata buffers',
        'pixel_algorithm_unchanged':True,'pipeline_latency_unchanged':True,
        'evidence_directory':'build/memory'}
if out.name in ('runtime_bitstream','dualkey_bitstream'):
    for pattern in (r'\.RUNTIME_ENABLE\(1\)',r'\.OBJECTS_ENABLE\(1\)',r'\.MAX_OBJECTS\(128\)'):
        if not re.search(pattern,top): raise SystemExit('Missing runtime controls / accepted-object overlay integration')
    manifest['runtime_controls']={
        'interface':'K1 freeze or tap+/hold- repeat; K2 menu/next/1s exit; frame-boundary atomic settings',
        'views':['raw','threshold binary','candidate contours and accepted frozen boxes'],
        'max_display_objects':128,'accepted_boxes':'CCA accepted roots; frozen frame only',
        'numbering':'1..128 per frozen result','object_overlay_latency_pixel_clocks':2,
        'settings_retained_after_power_loss':False,'evidence_directory':'build/two_key' if out.name=='dualkey_bitstream' else 'build/runtime'}
    manifest['key2']='M2/GPIOL_N_02 input, active low, 1.8V (VF core K2)'
(out/'bean_build_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(f'PASS native 1080p geometry, camera clock, RAM budget, bit freshness, all {len(slacks)} clock relationships, VF K1 pins and source hashes')
