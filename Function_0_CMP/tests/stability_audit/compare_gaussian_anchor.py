"""Follow-up: Gaussian2/1 crossed with anchor disabled/enabled, plus moving geometry.
Executes definitions of evaluate_candidates.py without its experiment/output block.
Single Gaussian is hypothetical; all other processing remains identical.
"""
from pathlib import Path
exec(Path(__file__).with_name('evaluate_candidates.py').read_text(encoding='utf-8-sig').split('report={}')[0])
# Replace only the explicit pair of Canny Gaussian passes in the independent oracle.
node=next(n for n in ast.parse((ROOT/'tests/run_noise_fix_edges.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='oracle')
count=0
for n in ast.walk(node):
 if isinstance(n,ast.For) and isinstance(n.iter,ast.Call) and isinstance(n.iter.func,ast.Name) and n.iter.func.id=='range' and len(n.iter.args)==1 and isinstance(n.iter.args[0],ast.Constant) and n.iter.args[0].value==2:
  n.iter.args[0]=ast.Name(id='GAUSSIAN_PASSES',ctx=ast.Load());count+=1
assert count==1
exec(compile(ast.fix_missing_locations(ast.Module(body=[node],type_ignores=[])),'gaussian_variant','exec'),ns);ns['legacy']=ns['oracle']
report={}
for name in ['flat12','flat24','shadow12','shadow16','shadow24','thin24','thin48','line2','diagonal2','moving','disappear']:
 imgs,cs=images(name);result={};all_edges={}
 for passes in (2,1):
  ns['GAUSSIAN_PASSES']=passes;preps=[prepare(p) for p in imgs]
  for anchor in (False,True):
   key='gauss%d_%s'%(passes,'anchor2' if anchor else 'baseline2');hist=[False]*N;es=[]
   for p in preps:e,hist,_=run(p,hist,anchor,2);es.append(e)
   result[key]=metrics(es,cs,name);all_edges[key]=es
 if name=='moving':
  for key,es in all_edges.items():
   base=all_edges['gauss2_baseline2'];deltas=[];width=[];double=0;stalled=0;centers=[]
   for f in range(2,F):
    center_rows=[]
    for y in range(5,H-5):
     xx=[x for x in range(5,W-5) if es[f][y*W+x]];bb=[x for x in range(5,W-5) if base[f][y*W+x]]
     if xx:
      width.append(max(xx)-min(xx)+1);double+=len(xx)>1;center_rows.append(sum(xx)/len(xx))
      if bb:deltas.append(sum(xx)/len(xx)-sum(bb)/len(bb))
    centers.append(sum(center_rows)/len(center_rows))
   result[key]['moving_geometry']={'mean_x_relative_gauss2_baseline':sum(deltas)/len(deltas),'min_x_relative_baseline':min(deltas),'max_x_relative_baseline':max(deltas),'max_span_pixels':max(width),'multi_pixel_rows':double,'center_per_frame':centers,'stalled_transitions':sum(abs(b-a)<.25 for a,b in zip(centers,centers[1:]))}
 report[name]=result
 print(name,json.dumps(result,separators=(',',':')),flush=True)
(OUT/'gaussian_anchor_metrics.json').write_text(json.dumps(report,indent=2))
print('PASS software comparison complete; readout timing/BRAM implementation untested.')
