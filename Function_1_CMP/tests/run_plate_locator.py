"""Independent density/component oracle and actual plate_locator RTL regression.

Synthetic edges are six glyph-like stroke groups, not only plate rectangles.
Photo composites use existing calibration photos and a cold-frame A Canny
integer reference; they are detector regression, not held-out OCR accuracy.
"""
from pathlib import Path
import ast,json,random,sys,subprocess
from run_canny import simulate as _simulate,OUT,local_link
ROOT=Path(__file__).resolve().parents[1]

def simulate(name,*args,**kwargs):
 try:return _simulate(name,*args,**kwargs)
 except subprocess.CalledProcessError as e:
  text=(e.stdout or '')+(e.stderr or '')
  (OUT/(name+'.log')).write_text(text);print(text,flush=True);raise

def locate(edges,w,h,suppressed=None):
 gw=(w+7)//8;gh=(h+3)//4
 hot=[[False]*gw for _ in range(gh)]
 for gy in range(gh):
  for gx in range(gw):
   hot[gy][gx]=sum(bool(edges[y*w+x]) for y in range(gy*4,min(h,gy*4+4)) for x in range(gx*8,min(w,gx*8+8)))>=2
 active=[];done=[]
 for row in range(gh+4):
  old=[c for c in active if row>c[3]+2]
  done+=old;active=[c for c in active if row<=c[3]+2]
  if row>=gh:continue
  runs=[]
  for x,on in enumerate(hot[row]):
   if on:
    if runs and x-runs[-1][1]<=3:runs[-1][1]=x;runs[-1][2]+=1
    else:runs.append([x,x,1])
  for left,right,hits in runs:
   work=[left,right,row,row,hits]
   # A connected row can join previously disjoint components; repeat closure.
   while True:
    matches=[c for c in active if row<=c[3]+2 and work[0]<=c[1]+1 and c[0]<=work[1]+1]
    if not matches:break
    for c in matches:
     active.remove(c);work=[min(work[0],c[0]),max(work[1],c[1]),min(work[2],c[2]),row,work[4]+c[4]]
   active.append(work)
 candidates=[];small=False
 for l,r,t,b,hits in done:
  bw=(r-l+1)*8;bh=(b-t+1)*4;area=(r-l+1)*(b-t+1)
  if not (2*bh<=bw<=8*bh and bw<=w-16 and bh<=h//2 and hits>=2*(r-l+1) and hits*8>=area):continue
  if bw<96 or bh<16:small=True;continue
  if suppressed:
   x,y,sw,sh=suppressed
   if x<=(l+r+1)*4<x+sw and y<=(t+b+1)*2<y+sh:continue
  score=hits*8-area
  x=max(0,l*8-8);y=max(0,t*4-8);x1=min(w,(r+1)*8+8);y1=min(h,(b+1)*4+8)
  if score>0:candidates.append((score,(x,y,x1-x,y1-y),[l,r,t,b,hits]))
 candidates.sort(key=lambda v:v[0],reverse=True)
 return (candidates[0][1] if candidates else None),small,candidates

def glyph_edges(w,h,x,y,cw=16,ch=32,pitch=24):
 p=[0]*(w*h)
 for c in range(6):
  ox=x+c*pitch
  for yy in range(y,min(h,y+ch)):
   for xx in range(ox,min(w,ox+cw)):
    if xx in (ox,ox+cw-1) or yy in (y,y+ch//2,y+ch-1):p[yy*w+xx]=255
 return p

def merged(a,b):return [max(x,y) for x,y in zip(a,b)]

def verify(name,w,h,frames,actions=None,expected=None,gaps=True):
 actions=actions or [0]*len(frames)
 if expected is None:expected=[locate(e,w,h)[0] for e in frames]
 values=sum(frames,[])
 path=OUT/(name+'_edges.hex');path.write_text(''.join(f'{v:x}\n' for v in values))
 init=[]
 for f,(box,act) in enumerate(zip(expected,actions)):
  vals=(int(box is not None),*(box or (0,0,0,0)),act)
  init.append(''.join(f'{var}[{f}]={val};' for var,val in zip(['valids','xs','ys','ws','hs','acts'],vals)))
 tb='''`timescale 1ns/1ps
module tb;
 localparam W=@W@,H=@H@,N=W*H,F=@F@;
 reg clk=0;always #5 clk=~clk;reg rst=0,en=1,rearm=0,v=0,s=0,e=0,rej=0;reg[7:0] edge_data=0;
 wire cv;wire[10:0] cx,cw;wire[9:0] cy,ch;wire[1:0] diag;wire[31:0] fid,cf;
 reg[10:0] bx=0,bw=0;reg[9:0] by=0,bh=0;
 plate_locator #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,en,rearm,v,s,e,edge_data,rej,bx,bw,by,bh,cv,cx,cw,cy,ch,diag,fid,cf);
 reg[7:0] image[0:F*N-1];integer valids[0:F-1],xs[0:F-1],ys[0:F-1],ws[0:F-1],hs[0:F-1],acts[0:F-1];
 integer f,i,done=0,expected_frame=0;reg[3:0] previous=0;
 always @(negedge clk) if(rst) begin
  if(dut.state==0 && previous==8)begin
   if(cv!==valids[done][0])$fatal(1,"@NAME@ candidate f%0d got%0d want%0d diag%0d",done,cv,valids[done],diag);
   if(cv && (cx!=xs[done] || cy!=ys[done] || cw!=ws[done] || ch!=hs[done]))
    $fatal(1,"@NAME@ box f%0d got%0d,%0d %0dx%0d want%0d,%0d %0dx%0d",done,cx,cy,cw,ch,xs[done],ys[done],ws[done],hs[done]);
   if(cf!=done+1)$fatal(1,"@NAME@ frame tag f%0d got%0d",done,cf);
   done=done+1;
  end
  previous=dut.state;
 end
 initial begin
  $readmemh("tests/generated/@NAME@_edges.hex",image);@INIT@
  repeat(8)@(negedge clk);rst=1;
  for(f=0;f<F;f=f+1)begin
   if(acts[f]==1)begin
    wait(done==f);bx=cx;by=cy;bw=cw;bh=ch;rej=1;@(negedge clk);rej=0;
   end
   if(acts[f]==2)begin
    wait(done==f);rearm=1;@(negedge clk);rearm=0;
    if(cv)$fatal(1,"rearm retained candidate");
   end
   for(i=0;i<N;i=i+1)begin
    v=1;s=i==0;e=i==N-1;edge_data=image[f*N+i];@(negedge clk);
    if(@GAPS@ && (i%31==30 || i%W==W-1))begin v=0;s=0;e=0;repeat(3)@(negedge clk);end
   end
   v=0;s=0;e=0;
   // No frame-end wait for normal cases: maps must be analysed during the
   // following input frame, while the other map bank is being filled.
  end
  wait(done==F);repeat(3)@(negedge clk);
  en=0;@(negedge clk);if(cv)$fatal(1,"disable retained candidate");
  en=1;repeat(3)@(negedge clk);
  $display("PASS @NAME@: @F@ frames, exact candidate bounds/frame tags, gaps/banks/rearm/reject/enable");$finish;
 end
 initial begin repeat(N*F*5+100000)@(posedge clk);$fatal(1,"@NAME@ timeout done%0d state%0d",done,dut.state);end
endmodule
'''
 for k,val in [('W',w),('H',h),('F',len(frames)),('NAME',name),('INIT','\n'.join(init)),('GAPS',int(gaps))]:tb=tb.replace('@'+k+'@',str(val))
 simulate(name,tb,['src/plate_locator.v'],timeout=180)
 return {'name':name,'width':w,'height':h,'frames':len(frames),'boxes':expected}

def synthetic():
 w,h=323,121
 blank=[0]*(w*h);a=glyph_edges(w,h,40,28);b=glyph_edges(w,h,104,68,16,28,24)
 noise=blank[:]
 for x,y in [(3,2),(280,4),(15,80),(298,100),(230,25),(12,115)]:
  for dx,dy in [(0,0),(1,0)]:noise[(y+dy)*w+x+dx]=255
 edgeleft=glyph_edges(w,h,0,44);edgeright=glyph_edges(w,h,w-136,40);bottom=glyph_edges(w,h,56,h-32)
 small=glyph_edges(w,h,64,40,8,16,12)
 primary=glyph_edges(w,h,16,12,16,32,24);secondary=glyph_edges(w,h,160,76,12,24,20)
 two=merged(primary,secondary)
 first=locate(two,w,h)[0];other=locate(two,w,h,first)[0]
 assert first and other and first!=other,(first,other)
 frames=[blank,a,b,merged(a,noise),edgeleft,edgeright,bottom,small,blank,two]+[two]*8+[a]+[a]*8
 actions=[0]*len(frames);actions[10]=1;actions[-1]=2
 actions[18]=2;actions[19]=1;actions[-1]=0
 boxes=[locate(p,w,h)[0] for p in frames]
 for f in range(10,17):boxes[f]=other
 boxes[17]=first
 for f in range(19,26):boxes[f]=None
 result=[verify('plate_locator_small',w,h,frames,actions,boxes)]
 w,h=848,477
 a=glyph_edges(w,h,352,208,24,48,32);n=[0]*(w*h)
 for x,y in [(10,10),(800,20),(20,440),(812,451)]:n[y*w+x]=n[y*w+x+1]=255
 result.append(verify('plate_locator_full',w,h,[[0]*(w*h),merged(a,n),glyph_edges(w,h,0,445,16,32,24)],gaps=False))
 return result

def reject_during_analysis():
 w,h=320,121;p=glyph_edges(w,h,40,28);box=locate(p,w,h)[0]
 path=OUT/'plate_locator_async_reject_edges.hex';path.write_text(''.join(f'{v:x}\n' for v in p))
 tb='''`timescale 1ns/1ps
module tb;
localparam W=320,H=121,N=W*H;reg clk=0;always #5 clk=~clk;
reg rst=0,v=0,s=0,e=0,reject=0;reg[7:0] d=0;wire cv;wire[10:0] x,w;wire[9:0] y,h;wire[1:0] diag;wire[31:0] fid,cf;
plate_locator #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,1'b1,1'b0,v,s,e,d,reject,11'd32,11'd152,10'd20,10'd48,cv,x,w,y,h,diag,fid,cf);
reg[7:0] image[0:N-1];integer i;
initial begin
 $readmemh("tests/generated/plate_locator_async_reject_edges.hex",image);
 repeat(8)@(negedge clk);rst=1;
 for(i=0;i<N;i=i+1)begin v=1;s=i==0;e=i==N-1;d=image[i];@(negedge clk);end
 v=0;s=0;e=0;
 wait(dut.best_score!=0 && dut.state==2 && dut.row>=25);@(negedge clk);reject=1;@(negedge clk);reject=0;
 wait(dut.state==0);@(negedge clk);@(negedge clk);
 if(cv)$fatal(1,"rejected best candidate republished while cooldown%0d: box%0d,%0d %0dx%0d",dut.cooldown,x,y,w,h);
 $display("PASS locator reject during analysis cannot republish stale winner");$finish;
end
initial begin repeat(N*3)@(posedge clk);$fatal(1,"async reject timeout state%0d",dut.state);end
endmodule
'''
 simulate('plate_locator_async_reject',tb,['src/plate_locator.v'],timeout=60)

def smooth(p,w,h,adaptive=False):
 out=[]
 def at(x,y):
  x=1 if x<0 else w-2 if x>=w else x;y=1 if y<0 else h-2 if y>=h else y
  return p[y*w+x]
 for y in range(h):
  for x in range(w):
   a,b,c,d,e,f,g,j,k=[at(x+dx,y+dy) for dy in (-1,0,1) for dx in (-1,0,1)]
   r=max(a,b,c,d,e,f,g,j,k)-min(a,b,c,d,e,f,g,j,k)
   gx=c+2*f+k-a-2*d-g;gy=g+2*j+k-a-2*b-c
   flat=r<=24 and not (r and 2*max(abs(gx),abs(gy))>=7*r)
   out.append(e if adaptive and not flat else (a+2*b+c+2*d+4*e+2*f+g+2*j+k+8)//16)
 return out

def photos():
 from PIL import Image
 from plate_reference import oracle as plate_oracle
 node=next(n for n in ast.parse((ROOT/'tests/run_noise_fix_edges.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='oracle')
 ns={'local_link':local_link};exec(compile(ast.Module(body=[node],type_ignores=[]),'canny_reference','exec'),ns)
 w,h=384,193;frames=[];metrics=[]
 records=json.loads((ROOT/'tests/plate_samples/sources.json').read_text(encoding='utf-8'))
 rng=random.Random(271029)
 for i,r in enumerate(records):
  pw,ph=216,72;x=40+(i%2)*64;y=36+(i%2)*60
  photo=Image.open(ROOT/'tests/plate_samples'/r['test_filename']).convert('L')
  canonical=photo.resize((256,96),Image.Resampling.LANCZOS)
  boxes=plate_oracle(canonical)[4]
  assert len(boxes)==6,(r['plate'],boxes)
  truth=(x+min(b[0] for b in boxes)*pw//256,y+min(b[2] for b in boxes)*ph//96,
         x+(max(b[1] for b in boxes)+1)*pw//256,y+(max(b[3] for b in boxes)+1)*ph//96)
  p=[100+rng.randrange(-3,4) for _ in range(w*h)]
  scaled=photo.resize((pw,ph),Image.Resampling.LANCZOS)
  paste=list(scaled.get_flattened_data() if hasattr(scaled,'get_flattened_data') else scaled.getdata())
  for yy in range(ph):p[(y+yy)*w+x:(y+yy)*w+x+pw]=paste[yy*pw:(yy+1)*pw]
  p=smooth(smooth(p,w,h),w,h,True)
  _,edges,_=ns['oracle'](p,w,h,3,27)
  box,_,candidates=locate(edges,w,h);frames.append(edges)
  coverage=0
  if box:
   bx,by,bw,bh=box;tx,ty,ex,ey=truth
   coverage=max(0,min(ex,bx+bw)-max(tx,bx))*max(0,min(ey,by+bh)-max(ty,by))/((ex-tx)*(ey-ty))
  m={'plate':r['plate'],'photo_box':[x,y,pw,ph],'glyph_box':truth,'candidate':box,'glyph_coverage':coverage,'candidate_count':len(candidates)}
  metrics.append(m);print('PHOTO',json.dumps(m),flush=True)
 result=verify('plate_locator_photos',w,h,frames)
 (OUT/'plate_locator_photo_metrics.json').write_text(json.dumps(metrics,indent=2))
 assert all(m['candidate'] is not None and m['glyph_coverage']>=.95 for m in metrics),metrics
 return result,metrics

if __name__=='__main__':
 if '--control-corner' in sys.argv:reject_during_analysis();raise SystemExit
 results=[]
 if '--photos-only' not in sys.argv:
  results=synthetic();reject_during_analysis()
  results.append({'name':'plate_locator_async_reject','width':320,'height':121,'frames':1,'boxes':[None]})
 if '--synthetic-only' not in sys.argv:
  p,metrics=photos();results.append(p)
 (OUT/'plate_locator_metrics.json').write_text(json.dumps(results,indent=2))
 logs='\n'.join((OUT/(r['name']+'.log')).read_text() for r in results)
 (OUT/'plate_locator.log').write_text(logs)
 print('PASS plate locator regression; photo detection limits are reported separately.')
