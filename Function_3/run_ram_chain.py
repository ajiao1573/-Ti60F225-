import json,subprocess,sys
from pathlib import Path
p=Path.cwd();s=json.loads((p/'verification/gap_probe/summary.json').read_text());m=json.loads((p/'verification/core/manifest.json').read_text());counts={r['tag']:r['n_points'] for r in m['runs']};rows=[]
for x in s:
 t=x['name'];n=318 if t=='worn' else counts[t];src='verification/user_worn_1/photo.pts.hex' if t=='worn' else f'verification/core/{t}.pts.hex';exp=f'verification/gap_probe/{t}.exp.hex';tag='ram_chain_'+t.replace('.','_')
 c=[sys.executable,'tools/run_sim.py','--tag',tag,'--root','tb_ml_num_core','--tb','tests/ram_tb_gap_num_core.v','--src','src/point_gap_filter.v','--src','src/ml_num_core.v','--src','src/ml_num_au.v','--src','src/ml_int13_classifier.v','--plus',f'+RAWN={n}','--plus',f'+N={n-x["removed"]}','--plus',f'+PTS={src}','--plus',f'+EXP={exp}'];r=subprocess.run(c,capture_output=True,text=True);ok=r.returncode==0 and 'TEST:PASS' in r.stdout;rows.append({'name':t,'pass':ok,'class':x['predicted'],'acc':x['acc']});print(t,ok,x['predicted'],flush=True);(p/'verification/gap_probe/ram_chain_results.json').write_text(json.dumps(rows,indent=2))
sys.exit(0 if all(r['pass'] for r in rows) else 1)
