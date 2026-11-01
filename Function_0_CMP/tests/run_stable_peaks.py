"""RTL regression of current common RGB + temporal NMS; no external audit dependency.
Run from any directory with Python. Generates tests/generated/stable_peaks*.{sv,hex,log}.
Reference model preserves frame configuration, previous class2 history and coherent
motion protection independently of the RTL implementation. Tests small dimensions
including total pixels not divisible by32 and explicit per-pixel history readback.
"""
from pathlib import Path
import ast,json,os,random,subprocess
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
OUT=ROOT/'tests/generated';OUT.mkdir(exist_ok=True)
SIM=ROOT/'tools/sim/mingw64/bin'
ns={}
for fn,names in [('run_canny.py',{'local_link'}),('run_noise_fix_edges.py',{'oracle'}),('noise_model.py',{'rgb_smooth','common','luma','edge'})]:
 t=ast.parse((ROOT/'tests'/fn).read_text())
 exec(compile(ast.Module(body=[n for n in t.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),fn,'exec'),ns)
 if fn=='run_noise_fix_edges.py':ns['legacy']=ns['oracle']
SIDES=[([(-1,-1),(0,-1),(1,-1)],[(-1,1),(0,1),(1,1)]), ([(0,-1),(1,-1),(1,0)],[(0,1),(-1,0),(-1,1)]), ([(-1,-1),(-1,0),(-1,1)],[(1,-1),(1,0),(1,1)]), ([(-1,-1),(0,-1),(-1,0)],[(1,0),(0,1),(1,1)])]
def oracle(p,w,h,mode,high,history):
 gray,baseline,oldprotect=ns['edge'](p,w,h,mode,high,True);n=w*h
 if mode<2:return gray,baseline,[2 if v else 0 for v in baseline],[0]*n,[0]*n
 mag=[0]*n;dire=[0]*n;sign=[0]*n
 for y in range(1,h-1):
  for x in range(1,w-1):
   a,b,c,d,_,f,g,j,k=(gray[(y+dy)*w+x+dx] for dy in (-1,0,1) for dx in (-1,0,1));i=y*w+x
   gx=c+2*f+k-a-2*d-g;gy=g+2*j+k-a-2*b-c;ax,ay=abs(gx),abs(gy)
   mag[i]=max(ax,ay,abs(f+2*k+j-b-2*a-d),abs(b+2*c+f-d-2*g-j))
   dire[i]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 3 if (gx<0)!=(gy<0) else 1;sign[i]=int((gy if dire[i]==2 else gx)<0)
 low=high*5//8;limit=max(low,max(0,high-3));classes=[0]*n
 for y in range(1,h-1):
  for x in range(1,w-1):
   i=y*w+x;m=mag[i];d=[1,w+1,w,w-1][dire[i]];a,b=i-d,i+d;tol=4 if m>min(mag[a],mag[b])+16 else 0
   peak=m>0 and m+tol>=mag[a] and m>mag[b]+tol
   def support(side,limit):return any(mag[(y+dy)*w+x+dx]>0 and mag[(y+dy)*w+x+dx]>=limit and dire[(y+dy)*w+x+dx]!=(dire[i]^2) for dx,dy in side)
   weak=[support(side,max(low,m//2)) for side in SIDES[dire[i]]];strong=all(support(side,max(high,m//2)) for side in SIDES[dire[i]])
   held=history[i] and m>0 and m>=limit and all(weak) and m+2>=mag[a] and m+2>=mag[b]
   compete=any(history[j] and mag[j]>0 and mag[j]>=limit and mag[j]+2>=m and dire[j]==dire[i] and sign[j]==sign[i] for j in (a,b))
   if (held or peak and not compete) and m>=low and any(weak):classes[i]=2 if held or m>=high and strong else 1
 ed=ns['local_link'](classes,w,h,2);protect=[int(bool(a) and bool(b)) for a,b in zip(oldprotect,ed)]
 return gray,ed,classes,protect,[int(c==2) for c in classes]
def hexfile(name,data):
 path=OUT/(name+'.hex');path.write_text(''.join(f'{int(v):x}\n' for v in data));return path.relative_to(ROOT).as_posix()
def fixtures(w,h):
 rng=random.Random(261026+w);spec=[]
 # Repeated stable scenes exercise history; repeated threshold/mode changes clear it.
 for mode,t,scene,count in [(3,27,'weak',7),(3,27,'thin',5),(3,27,'move',5),(3,27,'flat',3),(2,27,'weak',5),(2,22,'weak',4),(3,22,'weak',4),(0,22,'weak',2),(3,22,'weak',3),(1,27,'thin',2),(2,27,'weak',3),(3,0,'noise',3),(3,1023,'strong',2),(2,0,'strong',2),(2,1023,'strong',2),(3,27,'weak',3)]:
  for k in range(count):
   p=[]
   for y in range(h):
    c=w//2 if scene!='move' else w//2-2+k
    for x in range(w):
     if scene=='thin':v=96+(48 if x==c else 0)
     elif scene in ('strong','move'):v=40 if x<c else 200
     elif scene=='flat':v=96
     elif scene=='noise':v=128+rng.randint(-16,16)
     else:v=96+(16 if x>=c else 0)
     v=max(0,min(255,v+rng.randint(-4,4)))
     # RGB values equal for exact luma; common RTL still compares every channel.
     p.append(v*0x010101)
   spec.append((mode,t,scene,p))
 return spec

def verify(w,h):
 frames=fixtures(w,h);n=w*h;name=f'stable_peaks_{w}x{h}'
 inputs=[];rgb=[];gs=[];es=[];cs=[];ps=[];hs=[];modevec=[];thvec=[];history=[0]*n;prev=None;stats=[]
 for f,(mode,t,scene,p) in enumerate(frames):
  config=(mode,t)
  if mode<2 or config!=prev:history=[0]*n
  common=ns['common'](p,w,h,True);lum=ns['luma'](common)
  if mode>=2:hs+=history
  g,e,c,pr,history=oracle(lum,w,h,mode,t,history)
  inputs+=p;rgb+=common;gs+=g;es+=e;cs+=c;ps+=pr;modevec.append(mode);thvec.append(t);prev=config
  stats.append(dict(frame=f,mode=mode,threshold=t,scene=scene,edges=sum(bool(v) for v in e),strong=sum(v==2 for v in c)))
 paths={key:hexfile(name+'_'+key,data) for key,data in [('input',inputs),('rgb',rgb),('gray',gs),('edge',es),('class',cs),('protect',ps),('history',hs),('mode',modevec),('threshold',thvec)]}
 tb='''`timescale 1ns/1ps
module tb;
localparam W=@W@,H=@H@,N=W*H,F=@F@,TOTAL=N*F,HIST=@HIST@;
reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,fv=0;reg[23:0] data=0;
wire pv,pf;wire[23:0] rgb;
camera_rgb_denoise #(.WIDTH(W),.HEIGHT(H)) common(clk,rst,fv,iv,data,pf,pv,rgb);
reg[$clog2(N+1)-1:0] idx=0;
always @(posedge clk) if(!rst) idx<=0;else if(pv)idx<=idx==N-1 ? 0:idx+1'b1;
wire sop=pv && idx==0,eop=pv && idx==N-1;
wire[9:0] rgb_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
reg[1:0] mode=3;reg[9:0] threshold=27;wire busy,gv,gs,ge,ev,es,ee,protect;wire[7:0] gd,ed;
canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) dut(
.clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(pv),.in_sop(sop),.in_eop(eop),.in_data(rgb_sum[9:2]),.threshold(threshold),.algorithm(mode),
.busy(busy),.gray_valid(gv),.gray_sop(gs),.gray_eop(ge),.gray_data(gd),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed),.edge_protect(protect));
reg[23:0] inp[0:TOTAL-1],goldrgb[0:TOTAL-1];reg[7:0] goldgray[0:TOTAL-1],goldedge[0:TOTAL-1],goldprotect[0:TOTAL-1];
reg[1:0] goldclass[0:TOTAL-1],modes[0:F-1];reg[9:0] thrs[0:F-1];reg goldhistory[0:HIST-1];
integer rc=0,gc=0,ec=0,hc=0,cycles=0,f,i,j; reg[22:0] dbg_center,dbg_a,dbg_c;reg dbg_held,dbg_compete,dbg_peak,dbg_direct,dbg_selected,dbg_weak;reg[7:0] dbg_support,dbg_ta,dbg_tb; always @(posedge clk) begin dbg_direct<=dut.frontend.nms_enabled.normal_a[22] && dut.frontend.nms_enabled.normal_a[18:8]!=0 && dut.frontend.nms_enabled.normal_a[18:8]>=dut.frontend.nms_enabled.stable_peak_logic.hold_limit && {1'b0,dut.frontend.nms_enabled.normal_a[18:8]}+12'd2>={1'b0,dut.frontend.nms_enabled.mag} && dut.frontend.nms_enabled.normal_a[20:19]==dut.frontend.nms_enabled.n22[20:19] && dut.frontend.nms_enabled.normal_a[21]==dut.frontend.nms_enabled.n22[21];dbg_support<=dut.frontend.nms_enabled.weak_support;dbg_ta<=dut.frontend.nms_enabled.tangent_a;dbg_tb<=dut.frontend.nms_enabled.tangent_b;dbg_selected<=dut.frontend.nms_enabled.selected_peak;dbg_weak<=dut.frontend.nms_enabled.weak_supported;dbg_center<=dut.frontend.nms_enabled.n22;dbg_a<=dut.frontend.nms_enabled.normal_a;dbg_c<=dut.frontend.nms_enabled.normal_c;dbg_held<=dut.frontend.nms_enabled.held_peak;dbg_compete<=dut.frontend.nms_enabled.competing_history;dbg_peak<=dut.frontend.nms_enabled.peak;end
always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>TOTAL*8) $fatal(1,"timeout rc%0d gc%0d ec%0d hc%0d",rc,gc,ec,hc);
 if(pv)begin
  if(rgb!==goldrgb[rc])$fatal(1,"RGB f%0d x%0d y%0d got%h want%h",rc/N,rc%W,(rc%N)/W,rgb,goldrgb[rc]);rc=rc+1;
 end
 if(dut.frontend.nms_enabled.stable_history.history.out_valid)begin
  if(dut.frontend.nms_enabled.stable_history.history.out_data[22]!==goldhistory[hc])
   $fatal(1,"HISTORY token%0d x%0d y%0d got%b want%b",hc,hc%W,(hc%N)/W,dut.frontend.nms_enabled.stable_history.history.out_data[22],goldhistory[hc]);
  hc=hc+1;
 end
 if(gv)begin
  if(gd!==goldgray[gc] || dut.classification!==goldclass[gc])begin $display("DETAIL direct_a=%b selected=%b weak=%b support=%b ta=%b tb=%b n22=%h na=%h nc=%h held=%b competing=%b peak=%b weak=%b strong=%b low=%d high=%d",dbg_direct,dbg_selected,dbg_weak,dbg_support,dbg_ta,dbg_tb,dbg_center,dbg_a,dbg_c,dbg_held,dbg_compete,dbg_peak,dut.frontend.nms_enabled.weak_supported,dut.frontend.nms_enabled.strong_supported,dut.low_latched,dut.high_latched);$fatal(1,"GRAY/CLASS f%0d x%0d y%0d gray%0d/%0d class%0d/%0d",gc/N,gc%W,(gc%N)/W,gd,goldgray[gc],dut.classification,goldclass[gc]);end
  if(gs!==(gc%N==0) || ge!==(gc%N==N-1))$fatal(1,"GRAY framing %0d",gc);gc=gc+1;
 end
 if(ev)begin
  if(ed!==goldedge[ec] || protect!==goldprotect[ec][0])$fatal(1,"EDGE/PROTECT f%0d x%0d y%0d edge%0d/%0d protect%b/%b",ec/N,ec%W,(ec%N)/W,ed,goldedge[ec],protect,goldprotect[ec][0]);
  if(es!==(ec%N==0) || ee!==(ec%N==N-1))$fatal(1,"EDGE framing %0d",ec);ec=ec+1;
 end
end
initial begin
@LOADS@
repeat(8)@(negedge clk);rst=1;
for(f=0;f<F;f=f+1)begin
 wait(!busy);mode=modes[f];threshold=thrs[f];fv=1;
 for(i=0;i<N;i=i+1)begin
  iv=1;data=inp[f*N+i];@(negedge clk);
  if(i==N/2)begin mode=~modes[f];threshold=thrs[f]^10'h3ff;end
  if(i%13==7 || i%W==W-1)begin iv=0;repeat(1+i%4)@(negedge clk);end
 end
 iv=0;fv=0;wait(ec==(f+1)*N);repeat(5*W+30)@(negedge clk);
 if(rc!=(f+1)*N || gc!=(f+1)*N)$fatal(1,"frame count%0d",f);
end
if(hc!=HIST)$fatal(1,"history count%0d expected%0d",hc,HIST);
$display("PASS stable peaks @W@x@H@: @F@ frames; common RGB,gray,class,edge,protect,all markers,prior-history bits,mode/THR transitions,midframe changes,gaps,partial word");$finish;
end
endmodule
'''
 loads=[]
 for key,mem in [('input','inp'),('rgb','goldrgb'),('gray','goldgray'),('edge','goldedge'),('class','goldclass'),('protect','goldprotect'),('history','goldhistory'),('mode','modes'),('threshold','thrs')]:loads.append(f'$readmemh("{paths[key]}",{mem});')
 for key,value in {'W':w,'H':h,'F':len(frames),'HIST':len(hs),'LOADS':'\n'.join(loads)}.items():tb=tb.replace('@'+key+'@',str(value))
 src=OUT/(name+'.sv');src.write_text(tb);exe=OUT/(name+'.vvp')
 rtl=[str(p.relative_to(ROOT)) for p in (ROOT/'src/canny').glob('*.v')]+['src/camera_rgb_denoise.v']
 compile_result=subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-I.','-s','tb','-o',str(exe),str(src),*rtl],capture_output=True,text=True)
 log=compile_result.stdout+compile_result.stderr
 if compile_result.returncode:(OUT/(name+'.log')).write_text(log);raise RuntimeError(log)
 result=subprocess.run([str(SIM/'vvp.exe'),str(exe)],capture_output=True,text=True,timeout=180)
 log+=result.stdout+result.stderr;(OUT/(name+'.log')).write_text(log);print(log.strip(),flush=True)
 if result.returncode:raise RuntimeError('RTL failed: '+name)
 return dict(width=w,height=h,frames=len(frames),partial_word=n%32,history_tokens=len(hs),frames_metrics=stats),log
if __name__=='__main__':
 metrics=[];logs=[]
 try:
  for w,h in [(48,32),(35,23)]:
   m,log=verify(w,h);metrics.append(m);logs.append(log)
 finally:
  (OUT/'stable_peaks.log').write_text('\n'.join(logs));(OUT/'stable_peaks_metrics.json').write_text(json.dumps(metrics,indent=2))


