from pathlib import Path
import sys,random,json
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tests'))
from run_canny import simulate,OUT,RTL,local_link,write_hex
def oracle(p,w,h,mode,high):
 def at(a,x,y):
  x=1 if x<0 else w-2 if x>=w else x
  y=1 if y<0 else h-2 if y>=h else y
  return a[y*w+x]
 if mode&1:p=[sorted(at(p,x+dx,y+dy) for dy in (-1,0,1) for dx in (-1,0,1))[4] for y in range(h) for x in range(w)]
 if mode&2:
  for _ in range(2):
   p=[(sum(at(p,x+dx,y+dy)*wx*wy for dx,wx in [(-1,1),(0,2),(1,1)] for dy,wy in [(-1,1),(0,2),(1,1)])+8)//16 for y in range(h) for x in range(w)]
 mags=[0]*(w*h);directions=[0]*(w*h);low=high*5//8
 for y in range(1,h-1):
  for x in range(1,w-1):
   a,b,c,d,_,f,g,j,k=(p[(y+dy)*w+x+dx] for dy in (-1,0,1) for dx in (-1,0,1))
   gx=c+2*f+k-a-2*d-g;gy=g+2*j+k-a-2*b-c;ax,ay=abs(gx),abs(gy);i=y*w+x
   mags[i]=max(ax,ay,abs(f+2*k+j-b-2*a-d),abs(b+2*c+f-d-2*g-j))
   directions[i]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 3 if (gx<0)!=(gy<0) else 1
 classes=[0]*(w*h);protect=[0]*(w*h)
 if not mode&2:return p,[255*int(m!=0 and m>=high) for m in mags],protect
 for y in range(1,h-1):
  for x in range(1,w-1):
   i=y*w+x;m=mags[i];d=[1,w+1,w,w-1][directions[i]]
   tolerance=4 if m>min(mags[i-d],mags[i+d])+16 else 0
   if not m or m+tolerance<mags[i-d] or m<=mags[i+d]+tolerance:continue
   sides=((( -1,-1),(0,-1),(1,-1)),((-1,1),(0,1),(1,1))) if directions[i]==0 else \
         (((0,-1),(1,-1),(1,0)),((0,1),(-1,0),(-1,1))) if directions[i]==1 else \
         (((-1,-1),(-1,0),(-1,1)),((1,-1),(1,0),(1,1))) if directions[i]==2 else \
         (((-1,-1),(0,-1),(-1,0)),((1,0),(0,1),(1,1)))
   def support(side,limit):
    return any(mags[(y+dy)*w+x+dx]>0 and mags[(y+dy)*w+x+dx]>=limit and directions[(y+dy)*w+x+dx]!=(directions[i]^2) for dx,dy in side)
   weak=any(support(side,max(low,m//2)) for side in sides)
   strong=all(support(side,max(high,m//2)) for side in sides)
   if m>=low and weak:classes[i]=2 if m>=high and strong else 1
   protect[i]=int(strong and m>=2*high)
 e=local_link(classes,w,h)
 return p,e,[int(a and b!=0) for a,b in zip(protect,e)]
w,h,n=64,48,64*48;rng=random.Random(20261020);names=['clean','noise24','impulse','step1','step24','moving']
images=[];goldgray=[];goldedge=[];goldprotect=[];modes=[]
for scene in names:
 for frame in range(8):
  if scene=='moving':step=24+frame*2
  else:step=32
  p=[]
  for y in range(h):
   for x in range(w):
    base=(50 if x<step else 200) if scene in ['step1','step24','moving'] else 128
    noise=rng.randint(-24,24) if scene in ['noise24','step24'] else rng.randint(-1,1) if scene=='step1' else rng.randint(-4,4) if scene=='moving' else 0
    v=max(0,min(255,base+noise))
    if scene=='impulse' and rng.random()<.02:v=rng.choice([0,255])
    p.append(v)
  images.append(p)
# All four modes get the exact same frames, threshold and empty cycles.
paths={'input':write_hex('noise_fix_input',sum(images,[]))}
inst=[];decl=[];mon=[];files=[]
for mode in range(4):
 gs=[];es=[];ps=[]
 for p in images:
  g,e,protect=oracle(p,w,h,mode,47);gs+=g;es+=e;ps+=protect
 gp=write_hex(f'noise_fix_gray{mode}',gs);ep=write_hex(f'noise_fix_edge{mode}',es);pp=write_hex(f'noise_fix_protect{mode}',ps)
 goldgray.append(gs);goldedge.append(es);goldprotect.append(ps)
 decl.append(f'wire b{mode},gv{mode},gs{mode},ge{mode},ev{mode},es{mode},ee{mode},p{mode};wire[7:0] gd{mode},ed{mode};integer gc{mode}=0,ec{mode}=0;reg[7:0] g{mode}[0:N*F-1],e{mode}[0:N*F-1],pm{mode}[0:N*F-1];')
 inst.append(f"""canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1)) d{mode}(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(iv),.in_sop(sop),.in_eop(eop),.in_data(data),.threshold(10'd47),.algorithm(2'd{mode}),
 .busy(b{mode}),.gray_valid(gv{mode}),.gray_sop(gs{mode}),.gray_eop(ge{mode}),.gray_data(gd{mode}),
 .edge_valid(ev{mode}),.edge_sop(es{mode}),.edge_eop(ee{mode}),.edge_data(ed{mode}),.edge_protect(p{mode}));""")
 mon.append(f"""if(gv{mode}) begin
 if(gd{mode}!==g{mode}[gc{mode}] || gs{mode}!==(gc{mode}%N==0) || ge{mode}!==(gc{mode}%N==N-1)) $fatal(1,"gray mode{mode} index=%0d got=%0d expected=%0d",gc{mode},gd{mode},g{mode}[gc{mode}]);gc{mode}=gc{mode}+1;end
 if(ev{mode}) begin
 if(ed{mode}!==e{mode}[ec{mode}] || p{mode}!==pm{mode}[ec{mode}][0] || es{mode}!==(ec{mode}%N==0) || ee{mode}!==(ec{mode}%N==N-1)) $fatal(1,"edge/protect mode{mode} index=%0d edge=%0d/%0d protect=%b/%b",ec{mode},ed{mode},e{mode}[ec{mode}],p{mode},pm{mode}[ec{mode}][0]);ec{mode}=ec{mode}+1;end""")
 files.append(f'$readmemh("{gp}",g{mode});$readmemh("{ep}",e{mode});$readmemh("{pp}",pm{mode});')
tb=f"""@TICK@timescale 1ns/1ps
module tb;
 localparam W={w},H={h},N=W*H,F={len(images)};
 reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,sop=0,eop=0;reg[7:0] data=0;
 {chr(10).join(decl)}
 {chr(10).join(inst)}
 reg[7:0] image[0:N*F-1];integer f,i,cycles=0;
 always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>N*F*3) $fatal(1,"timeout");
 {chr(10).join(mon)}
 end
 initial begin
 $readmemh("{paths['input']}",image);{chr(10).join(files)}
 repeat(8) @(negedge clk);rst=1;
 for(f=0;f<F;f=f+1) begin
 wait(!b0 && !b1 && !b2 && !b3);
 for(i=0;i<N;i=i+1) begin
 @(negedge clk);iv=1;sop=i==0;eop=i==N-1;data=image[f*N+i];
 if(i%31==30 || i%W==W-1) begin @(negedge clk);iv=0;sop=0;eop=0;end
 end
 @(negedge clk);iv=0;sop=0;eop=0;
 wait(ec0==(f+1)*N && ec1==(f+1)*N && ec2==(f+1)*N && ec3==(f+1)*N);
 repeat(12) @(negedge clk);
 end
 $display("PASS new reflected filters, tolerant NMS and aligned confidence: 192 gray/edge/protect frames, gaps and frame markers");$finish;
 end
endmodule
"""
simulate('noise_fix_edges',tb.replace('@TICK@',chr(96)),RTL,timeout=240)
metrics={}
def protected_vote(cur,prev,old,protect):
 return [255*int(bool(a) and (bool(p) or bool(b) or bool(c))) for a,b,c,p in zip(cur,prev,old,protect)]
for si,name in enumerate(names):
 es={m:[goldedge[m][(si*8+k)*n:(si*8+k+1)*n] for k in range(8)] for m in range(4)}
 ps=[goldprotect[3][(si*8+k)*n:(si*8+k+1)*n] for k in range(8)]
 es[4]=[protected_vote(es[3][k],es[3][k-1],es[3][k-2],ps[k]) for k in range(2,8)]
 bg=[y*w+x for y in range(5,h-5) for x in range(5,w-5) if name not in ['step1','step24','moving'] or x<20 or x>46]
 contour=[y*w+x for y in range(5,h-5) for x in range(22,44)]
 band=[y*w+x for y in range(h) for x in range(w) if 1<=min(x,w-1-x,y,h-1-y)<=4]
 metrics[name]={}
 for m,frames in es.items():
  if m<4:frames=frames[2:]
  q=dict(background_percent=100*sum(bool(e[i]) for e in frames for i in bg)/(len(frames)*len(bg)),
   border_percent=100*sum(bool(e[i]) for e in frames for i in band)/(len(frames)*len(band)),
   contour_flips=sum(a[i]!=b[i] for a,b in zip(frames,frames[1:]) for i in contour),
   step_rows_present=sum(any(e[y*w+x] for x in range(22,44)) for e in frames for y in range(5,h-5)))
  metrics[name][str(m)]=q
assert metrics['clean']['3']['background_percent']==0
assert metrics['step1']['3']['contour_flips']<78,metrics['step1']
assert metrics['moving']['4']['step_rows_present']==228,metrics['moving']
(OUT/'noise_fix_edges_metrics.json').write_text(json.dumps(metrics,indent=2))
print(json.dumps(metrics,indent=2))
