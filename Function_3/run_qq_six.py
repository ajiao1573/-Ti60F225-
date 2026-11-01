from pathlib import Path
from PIL import Image
import sys,json,subprocess,hashlib,re
p=Path.cwd();sys.path.insert(0,str(p/'tools'));import gen_scan_vectors as scan;import gen_core_vectors as g
root=Path(r'C:\Users\17734\Documents\Tencent Files\1773432419\nt_qq\nt_data\Pic\2026-10\Ori'); names=['636c96a3c2756057e895062826f00441.jpg','ce9e0fec8a3d2c6f56737a39b3c89336.jpg','7a6581bbd387b9fdb5b07b4a04b5a9c0.jpg','090c4b1ed1af0d3cab6a9d0bbbdb5547.jpg','c5449943964080530966ec29ec0eaf5c.jpg','c28beab09389f00fa77e36bd2913f3db.jpg']
out=p/'verification'/'qq_six_trial';out.mkdir(parents=True,exist_ok=True);params=json.loads((g.CLS/'verified'/'parameters.json').read_text(encoding='utf8')); rows=[]
for i,name in enumerate(names,1):
 try:
  src=root/name;d=out/f'image{i}';d.mkdir(exist_ok=True);im=Image.open(src).convert('RGB');w,h=im.size;side=min(w,h);left=(w-side)//2;top=(h-side)//2;prep=d/'input_512.png';im.crop((left,top,left+side,top+side)).resize((512,512),Image.Resampling.LANCZOS).save(prep)
  cf,fr=scan.rp.frame3(prep);pts=scan.rp.points_of(fr,cf);n=pts['n_points'];print(f'{i}: reference points={n}',flush=True)
  for fn,key,pack in [('gray','filtered_gray',scan.pack_gray),('edge','edge',scan.pack_bits),('prot','protect',scan.pack_bits)]: (d/(fn+'.hex')).write_text('\n'.join(pack(fr[key]))+'\n',encoding='ascii')
  words=g.pack_points(pts['x'],pts['y'],pts['side'],pts['slot'],pts['step'],pts['protect']);(d/'exp.hex').write_text(''.join(f'{words[2*j]:016x}\n' for j in range(n)),encoding='ascii')
  (d/'raw.pts.hex').write_text(''.join(f'{words.get(j,0):016x}\n' for j in range(944)),encoding='ascii')
  if not 0<n<=472: raise RuntimeError(f'unsupported point count: {n}')
  tag=f'qq_six_{i}_scan';cmd=[sys.executable,'tools/run_sim.py','--tag',tag,'--root','tb_ml_scan','--tb','tests/tb_scan_dump.v','--src','src/ml_scan.v','--plus',f'+NEXP={n}','--plus',f'+VEC=verification/qq_six_trial/image{i}','--plus',f'+GOT=verification/qq_six_trial/image{i}/actual_pts.hex'];r=subprocess.run(cmd,capture_output=True,text=True);scanlog=(p/'logs'/f'{tag}_run.log').read_text(errors='replace');scan_ok=r.returncode==0 and 'SCAN PASS' in scanlog and 'SCAN FAIL' not in scanlog and 'TIMEOUT' not in scanlog
  y=sorted(pts['y']);gaps=[(y[j]-y[j-1],j) for j in range(1,len(y))];gap,k=max(gaps,default=(0,0));cut=(y[k-1]+y[k])//2 if gap>=60 else None;low=sum(z<=cut for z in pts['y']) if cut is not None else 0;high=n-low
  enabled=cut is not None and low>=24 and high>=24;left_majority=low>=high;ix=[j for j in range(n) if not enabled or ((pts['y'][j]<=cut)==left_majority)]
  data=[[pts[key][j] for j in ix] for key in ('x','y','side','slot','step','protect')];ref=g.emit(d,'filtered',*data,params,'experiment gap-filter reference');pred=ref['predicted'];expected='OK' if i<=3 else 'NG'
  tag=f'qq_six_{i}_gap_core';cmd=[sys.executable,'tools/run_sim.py','--tag',tag,'--root','tb_ml_num_core','--tb','tests/ram_tb_gap_num_core.v','--src','src/point_gap_filter.v','--src','src/ml_num_core.v','--src','src/ml_num_au.v','--src','src/ml_int13_classifier.v','--plus',f'+RAWN={n}','--plus',f'+N={len(ix)}','--plus',f'+PTS=verification/qq_six_trial/image{i}/raw.pts.hex','--plus',f'+EXP=verification/qq_six_trial/image{i}/filtered.exp.hex'];r=subprocess.run(cmd,capture_output=True,text=True);lf=p/'logs'/f'{tag}_run.log';text=lf.read_text(errors='replace') if lf.exists() else r.stdout+r.stderr;core_ok=r.returncode==0 and 'TEST:PASS ml_num_core' in text and 'TEST:FAIL' not in text;match=re.search(r'core done after (\d+) cycles valid=(\d) reason=(\d+)',text)
  row={'index':i,'file':name,'input_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'source_size':[w,h],'crop':[left,top,left+side,top+side],'expected':expected,'reference':pred,'acc':ref['classifier_accumulator'],'reason':ref['reason'],'raw_points':n,'gap':gap,'filter_enabled':enabled,'removed':n-len(ix),'scan_rtl_pass':scan_ok,'filter_core_rtl_pass':core_ok,'core_report':match.group(0) if match else None,'requested_result_pass':scan_ok and core_ok and pred==expected}
 except Exception as e:
  row={'index':i,'file':name,'expected':'OK' if i<=3 else 'NG','error':f'{type(e).__name__}: {e}','requested_result_pass':False}
 rows.append(row);(out/'results.json').write_text(json.dumps(rows,indent=2,ensure_ascii=False),encoding='utf8');print(f"{i}: expected={row.get('expected')} result={row.get('reference')} acc={row.get('acc')} scan={row.get('scan_rtl_pass')} chain={row.get('filter_core_rtl_pass')} error={row.get('error')}",flush=True)
