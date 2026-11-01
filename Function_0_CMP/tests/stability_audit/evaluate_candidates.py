"""Isolated software audit, no RTL/hardware or product edits.
Reuses current common RGB + median + 2 Gaussian gray. Baseline recomputation is checked
pixel-exact against current oracle. H27, L=floor(5H/8), 1bit prior class2 history.
Hold: prior bit, mag>=max(L,H-3), bilateral weak support, mag+2>=both normal neighbors.
Held class2 updates history, so persistent near-H gradients can remain latched indefinitely;
release immediately below H-3. New peak suppressed by normal-neighbor prior bit having
same current direction/polarity and neighbor mag>=hold limit and neighbor mag+2>=center.
No M3, DDR, camera AE, gain or physical sensor model. Starts with cleared history.
"""
from pathlib import Path
import ast,random,json,hashlib
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
ns={}
for file,names in [('run_canny.py',{'local_link'}),('run_noise_fix_edges.py',{'oracle'}),('noise_model.py',{'rgb_smooth','common','luma','edge'})]:
 t=ast.parse((ROOT/'tests'/file).read_text());exec(compile(ast.Module(body=[n for n in t.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),file,'exec'),ns)
 if file=='run_noise_fix_edges.py':ns['legacy']=ns['oracle']
W,H,F,T=48,32,16,27;N=W*H
SIDES=[([(-1,-1),(0,-1),(1,-1)],[(-1,1),(0,1),(1,1)]), ([(0,-1),(1,-1),(1,0)],[(0,1),(-1,0),(-1,1)]), ([(-1,-1),(-1,0),(-1,1)],[(1,-1),(1,0),(1,1)]), ([(-1,-1),(0,-1),(-1,0)],[(1,0),(0,1),(1,1)])]
def prepare(p):
 q=ns['luma'](ns['common'](p,W,H,True));gray,expected,_=ns['legacy'](q,W,H,3,T)
 mag=[0]*N;dire=[0]*N;sign=[0]*N
 for y in range(1,H-1):
  for x in range(1,W-1):
   a,b,c,d,_,f,g,j,k=(gray[(y+dy)*W+x+dx] for dy in (-1,0,1) for dx in (-1,0,1));i=y*W+x
   gx=c+2*f+k-a-2*d-g;gy=g+2*j+k-a-2*b-c;ax,ay=abs(gx),abs(gy)
   mag[i]=max(ax,ay,abs(f+2*k+j-b-2*a-d),abs(b+2*c+f-d-2*g-j))
   dire[i]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 3 if (gx<0)!=(gy<0) else 1;sign[i]=int((gy if dire[i]==2 else gx)<0)
 peak=[False]*N;weak=[False]*N;both=[False]*N;strong=[False]*N;normal=[(0,0)]*N
 for y in range(1,H-1):
  for x in range(1,W-1):
   i=y*W+x;m=mag[i];d=[1,W+1,W,W-1][dire[i]];a,b=i-d,i+d;normal[i]=(a,b);tol=4 if m>min(mag[a],mag[b])+16 else 0
   peak[i]=m>0 and m+tol>=mag[a] and m>mag[b]+tol
   def support(side,limit):return any(mag[(y+dy)*W+x+dx]>0 and mag[(y+dy)*W+x+dx]>=limit and dire[(y+dy)*W+x+dx]!=(dire[i]^2) for dx,dy in side)
   ws=[support(s,max(T*5//8,m//2)) for s in SIDES[dire[i]]];weak[i]=any(ws);both[i]=all(ws);strong[i]=all(support(s,max(T,m//2)) for s in SIDES[dire[i]])
 return dict(mag=mag,dire=dire,sign=sign,peak=peak,weak=weak,both=both,strong=strong,normal=normal,expected=expected)
def run(p,hist,anchor,hops,safe=False):
 m,d,s=p['mag'],p['dire'],p['sign'];low=T*5//8;limit=max(low,T-3);hold=[False]*N
 if anchor:
  for i in range(N):
   a,b=p['normal'][i];hold[i]=hist[i] and m[i]>=limit and p['both'][i] and m[i]+2>=m[a] and m[i]+2>=m[b]
 cls=[0]*N
 for i in range(N):
  if hold[i]:cls[i]=2;continue
  if not p['peak'][i] or m[i]<low or not p['weak'][i]:continue
  if anchor and any((hold[j] if safe else hist[j] and m[j]>=limit and m[j]+2>=m[i]) and d[j]==d[i] and s[j]==s[i] for j in p['normal'][i]):continue
  cls[i]=2 if m[i]>=T and p['strong'][i] else 1
 edges=ns['local_link'](cls,W,H,hops)
 if not anchor and hops==2:assert edges==p['expected'],'baseline mismatch'
 return edges,[c==2 for c in cls],sum(hold)
def images(name):
 rng=random.Random(99241+sum(map(ord,name)));imgs=[];centers=[]
 for f in range(F):
  cs=[24 if name!='diagonal2' else 12+y//2 for y in range(H)]
  if name=='moving':cs=[15+f]*H
  centers.append(cs);p=[]
  for y in range(H):
   for x in range(W):
    c=cs[y];amp=4;v=96
    if name.startswith('flat'):v=128;amp=int(name[4:])
    elif name.startswith('shadow'):v+=int(name[6:]) if x>=c else 0
    elif name.startswith('thin'):v+=int(name[4:]) if x==c else 0
    elif name=='line2':v+=24 if c<=x<c+2 else 0
    elif name=='diagonal2':v+=24 if c<=x<c+2 else 0
    elif name=='moving':v=40 if x<c else 200
    elif name=='disappear':v+=40 if x>=c and f<8 else 0
    v=max(0,min(255,v+rng.randint(-amp,amp)));p.append(v*0x010101)
  imgs.append(p)
 return imgs,centers
def metrics(edges,centers,name):
 cov=flips=bg=gap=trail=dead=0;prev=None
 for f,e in enumerate(edges):
  if f<2:continue
  run=0;mask=[]
  for y in range(5,H-5):
   c=centers[f][y];hit=any(e[y*W+x] for x in range(c-3,c+4));cov+=hit;run=0 if hit else run+1;gap=max(gap,run)
   mask.extend(bool(e[y*W+x]) for x in range(5,W-5))
   for x in range(5,W-5):
    bg+=bool(e[y*W+x]) and (name.startswith('flat') or abs(x-c)>5)
    if name=='moving' and x<c-1:trail+=bool(e[y*W+x])
    if name=='disappear' and f>=8:dead+=bool(e[y*W+x])
  if prev is not None:flips+=sum(a!=b for a,b in zip(mask,prev))
  prev=mask
 return dict(rows=cov,possible_rows=(F-2)*(H-10),max_gap=gap,flips=flips,background=bg,trailing=trail,after_disappear=dead)
report={}
for name in ['flat12','flat24','shadow12','shadow16','shadow24','thin24','thin48','line2','diagonal2','moving','disappear']:
 imgs,cs=images(name);preps=[prepare(p) for p in imgs];result={}
 for key,anchor,hops,safe in [('baseline2',False,2,False),('link4',False,4,False),('anchor2',True,2,False),('anchor4',True,4,False),('safe_anchor4',True,4,True)]:
  hist=[False]*N;es=[];holds=0
  for p in preps:e,hist,k=run(p,hist,anchor,hops,safe);es.append(e);holds+=k
  result[key]=metrics(es,cs,name)|dict(held=holds)
 report[name]=result;print(name,json.dumps(result,separators=(',',':')),flush=True)
files=['src/canny/canny_frontend.v','src/canny/canny_frame.v','src/canny/canny_local_link.v','src/camera_rgb_smooth.v','src/camera_rgb_denoise.v','tests/noise_model.py']
manifest={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files}
(OUT/'candidate_metrics.json').write_text(json.dumps({'config':{'W':W,'H':H,'frames':F,'THR':T,'mode':3,'root':str(ROOT)},'source_sha256':manifest,'metrics':report},indent=2))
print('PASS baseline matches current oracle on176 frames; software model only.')
