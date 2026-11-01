from pathlib import Path
import ast,math,json
from run_canny import ROOT,OUT,local_link,simulate,write_hex,RTL
ns={'local_link':local_link};tree=ast.parse((ROOT/'tests/run_noise_fix_edges.py').read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='oracle'],type_ignores=[]),'oracle','exec'),ns)
new=ns['oracle'];ns2={'local_link':local_link};tree=ast.parse((ROOT/'tests/run_sobel_noise.py').read_text())
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='oracle'],type_ignores=[]),'old','exec'),ns2);old=ns2['oracle']
w,h,n=96,64,96*64;fixtures=[];metrics={}
for mode in (2,3):
 for scene in ['rectangle','triangle','diagonal','soft_step']:
  for contrast in (32,48,96,180):
   p=[]
   for y in range(h):
    for x in range(w):
     if scene=='rectangle':v=16<=x<80 and 12<=y<52
     elif scene=='triangle':v=10<=y<54 and abs(x-48)<=y-10
     elif scene=='diagonal':v=x>=.6*y+28
     else:v=max(0,min(1,(x-28)/40))
     p.append(round(32+contrast*v))
   oe=old(p,w,h,mode,72,True,True,True)[1];ne=new(p,w,h,mode,72)[1]
   a=sum(bool(e) for e in oe);b=sum(bool(e) for e in ne)
   if a:assert b>=.95*a,(mode,scene,contrast,a,b)
   fixtures.append((mode,72,p));metrics[f'{mode}_{scene}_{contrast}']={'before':a,'after':b}
 for sigma in (2,4,8):
  p=[round(16+220*(1+math.erf((x-48)/sigma/2**.5))/2) for y in range(h) for x in range(w)]
  oe=old(p,w,h,mode,47,True,True,True)[1];ne=new(p,w,h,mode,47)[1]
  old_x={i%w for i,v in enumerate(oe) if v};new_x={i%w for i,v in enumerate(ne) if v}
  assert new_x and all(any(abs(a-b)<=1 for b in old_x) for a in new_x),(sigma,old_x,new_x)
  fixtures.append((mode,47,p));metrics[f'{mode}_blur_sigma{sigma}']={'old_columns':sorted(old_x),'new_columns':sorted(new_x)}
inputs=[];grays=[];edges=[];protect=[]
for mode,thr,p in fixtures:
 g,e,pr=new(p,w,h,mode,thr);inputs+=p;grays+=g;edges+=e;protect+=pr
ip=write_hex('noise_fix_detail_in',inputs);gp=write_hex('noise_fix_detail_gray',grays);ep=write_hex('noise_fix_detail_edge',edges);pp=write_hex('noise_fix_detail_protect',protect)
tb=f'''@TICK@timescale 1ns/1ps
module tb;
 localparam W={w},H={h},N=W*H,F={len(fixtures)};
 reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,sop=0,eop=0;reg[7:0] data=0;reg[1:0] mode;reg[9:0] threshold;
 wire busy,gv,gs,ge,ev,es,ee,pr;wire[7:0] gd,ed;
 canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(iv),.in_sop(sop),.in_eop(eop),.in_data(data),.threshold(threshold),.algorithm(mode),
 .busy(busy),.gray_valid(gv),.gray_sop(gs),.gray_eop(ge),.gray_data(gd),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed),.edge_protect(pr));
 reg[7:0] inp[0:N*F-1],gray[0:N*F-1],edge_mem[0:N*F-1],protect[0:N*F-1];reg[1:0] modes[0:F-1];reg[9:0] thrs[0:F-1];
 integer f,i,gc=0,ec=0,cycles=0;
 always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>N*F*3) $fatal(1,"timeout");
 if(gv) begin if(gd!==gray[gc]) $fatal(1,"gray %0d",gc);gc=gc+1;end
 if(ev) begin if(ed!==edge_mem[ec] || pr!==protect[ec][0] || es!==(ec%N==0) || ee!==(ec%N==N-1)) $fatal(1,"edge/confidence %0d",ec);ec=ec+1;end
 end
 initial begin
 $readmemh("{ip}",inp);$readmemh("{gp}",gray);$readmemh("{ep}",edge_mem);$readmemh("{pp}",protect);
 {''.join(f'modes[{i}]={m};thrs[{i}]={t};' for i,(m,t,p) in enumerate(fixtures))}
 repeat(8) @(negedge clk);rst=1;
 for(f=0;f<F;f=f+1) begin
 wait(!busy);mode=modes[f];threshold=thrs[f];
 for(i=0;i<N;i=i+1) begin
 @(negedge clk);iv=1;sop=i==0;eop=i==N-1;data=inp[f*N+i];
 if(i%W==W-1) begin @(negedge clk);iv=0;sop=0;eop=0;end
 end
 @(negedge clk);iv=0;sop=0;eop=0;wait(ec==(f+1)*N);repeat(12) @(negedge clk);
 end
 $display("PASS 38 detail frames: rectangles/triangles/diagonal weak contrast and broad soft-edge localization, exact gray/edge/confidence");$finish;
 end
endmodule'''
simulate('noise_fix_detail',tb.replace('@TICK@',chr(96)),RTL,timeout=180)
(OUT/'noise_fix_detail_metrics.json').write_text(json.dumps(metrics,indent=2))
