"""Independent integer model for common smoothing and coherent protection."""
from pathlib import Path
import ast
from run_canny import local_link
node=next(n for n in ast.parse(Path('tests/run_noise_fix_edges.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='oracle')
namespace={'local_link':local_link};exec(compile(ast.Module(body=[node],type_ignores=[]),'legacy_oracle','exec'),namespace)
legacy=namespace['oracle']
def rgb_smooth(p,w,h,adaptive=False):
 def at(x,y):
  x=1 if x<0 else w-2 if x>=w else x;y=1 if y<0 else h-2 if y>=h else y
  return p[y*w+x]
 out=[]
 for y in range(h):
  for x in range(w):
   vals=[[v>>s&255 for v in [at(x+dx,y+dy) for dy in (-1,0,1) for dx in (-1,0,1)]] for s in (16,8,0)]
   def edge_like(v):
    a,b,c,d,_,f,g,h,i=v;r=max(v)-min(v)
    gx=c+2*f+i-a-2*d-g;gy=g+2*h+i-a-2*b-c
    return r>0 and 2*max(abs(gx),abs(gy))>=7*r
   flat=all(max(v)-min(v)<=24 and not edge_like(v) for v in vals)
   channels=[(sum(a*b for a,b in zip(v,[1,2,1,2,4,2,1,2,1]))+8)//16 for v in vals]
   out.append(at(x,y) if adaptive and not flat else channels[0]<<16|channels[1]<<8|channels[2])
 return out
def common(p,w,h,new=True):
 a=rgb_smooth(p,w,h)
 return rgb_smooth(a,w,h,True) if new else a
def luma(p):return [((v>>16&255)+2*(v>>8&255)+(v&255))//4 for v in p]
def edge(p,w,h,mode,t,coherent=True):
 gray,ed,oldprotect=legacy(p,w,h,mode,t)
 if not coherent or not mode&2:return gray,ed,oldprotect
 mags=[0]*(w*h);dirs=[0]*(w*h);signs=[0]*(w*h)
 for y in range(1,h-1):
  for x in range(1,w-1):
   a,b,c,d,_,f,g,j,k=(gray[(y+dy)*w+x+dx] for dy in (-1,0,1) for dx in (-1,0,1))
   gx=c+2*f+k-a-2*d-g;gy=g+2*j+k-a-2*b-c;ax,ay=abs(gx),abs(gy);i=y*w+x
   mags[i]=max(ax,ay,abs(f+2*k+j-b-2*a-d),abs(b+2*c+f-d-2*g-j))
   dirs[i]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 3 if (gx<0)!=(gy<0) else 1
   signs[i]=int((gy if dirs[i]==2 else gx)<0)
 sides=[([(-1,-1),(0,-1),(1,-1)],[(-1,1),(0,1),(1,1)]),
        ([(0,-1),(1,-1),(1,0)],[(0,1),(-1,0),(-1,1)]),
        ([(-1,-1),(-1,0),(-1,1)],[(1,-1),(1,0),(1,1)]),
        ([(-1,-1),(0,-1),(-1,0)],[(1,0),(0,1),(1,1)])]
 protect=[0]*(w*h)
 for y in range(1,h-1):
  for x in range(1,w-1):
   i=y*w+x
   if not oldprotect[i]:continue
   limit=max(t,mags[i]-mags[i]//4)
   protect[i]=int(all(any(mags[(y+dy)*w+x+dx]>0 and mags[(y+dy)*w+x+dx]>=limit and dirs[(y+dy)*w+x+dx]==dirs[i] and signs[(y+dy)*w+x+dx]==signs[i] for dx,dy in side) for side in sides[dirs[i]]))
 return gray,ed,protect
def vote(frames,protection):
 return [[255*int(bool(frames[f][i]) and (bool(protection[f][i]) or bool(frames[f-1][i]) or bool(frames[f-2][i])) ) for i in range(len(frames[0]))] for f in range(2,len(frames))]
