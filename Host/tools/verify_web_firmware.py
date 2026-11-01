"""Verify exported bitstream, source provenance and final constrained timing."""
from pathlib import Path
import argparse,hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('project',choices=['Function_2_CMP','Function_3']);a=p.parse_args()
root=ROOT/a.project;out=root/'output/host_web'
summary=json.loads((out/'build_summary.json').read_text())
assert summary['flow_exit_code']==0 and summary['inputs_unchanged'] and summary['bitstream_exists'],summary
inputs=json.loads((out/'source_hashes.json').read_text())
assert all(hashlib.sha256((root/f).read_bytes()).hexdigest()==h for f,h in inputs.items()),'Source changed since build'
assert hashlib.sha256((out/'Ti60_Demo.bit').read_bytes()).hexdigest()==summary['sha256']
timing=(out/'Ti60_Demo.timing.rpt').read_text()
table=timing.split('---------- 2. Clock Relationship Summary (begin) ----------')[1].split('---------- Clock Relationship Summary (end)')[0]
setup,hold=table.split('Hold (Min) Clock Relationship')
pattern=r'^\s*\w+\s+\w+\s+-?\d+\.\d+\s+(-?\d+\.\d+)\s+\('
ss=[float(x) for x in re.findall(pattern,setup,re.M)];hs=[float(x) for x in re.findall(pattern,hold,re.M)]
assert ss and hs and min(ss)>=0 and min(hs)>=0,(ss,hs)
route=(out/'Ti60_Demo.route.out').read_text()
assert 'ERROR    :' not in route, 'Router contains errors'
place=(out/'Ti60_Demo.place.out').read_text()
used=int(re.findall(r'XLR count after merging:\s*(\d+)',place)[-1])
assert used<=60800
result={**summary,'timing_relationships':len(ss)+len(hs),'minimum_setup_slack_ns':min(ss),'minimum_hold_slack_ns':min(hs),
        'xlr_used':used,'xlr_capacity':60800,'verification':'PASS','hardware_validated':False,
        'limits':'Existing unused-interface SDC warnings remain; constrained setup/hold pass is not physical board validation.'}
(out/'release_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
