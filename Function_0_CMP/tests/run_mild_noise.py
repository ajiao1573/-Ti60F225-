"""Same-source RGB/luma and four engines; integer oracle and low-THR metrics."""
import random,statistics,json
from pathlib import Path
from run_canny import simulate,write_hex,RTL,OUT
from noise_model import common,luma,edge,vote
W,H,F=48,32,6;N=W*H;rng=random.Random(20261024)
scenes={}
for name in ['flat12','flat24','impulse','weak_step','weak_noisy','moving','thin_color']:
 imgs=[]
 for f in range(F):
  p=[]
  for y in range(H):
   for x in range(W):
    if name.startswith('flat'):
     amp=int(name[4:]);v=128+rng.randint(-amp,amp);rgb=v*0x010101
    elif name=='impulse':
     v=128+(rng.choice([-100,100]) if rng.random()<.02 else 0);rgb=v*0x010101
    elif name=='weak_step':rgb=(96 if x<24 else 108)*0x010101
    elif name=='weak_noisy':rgb=((96 if x<24 else 108)+rng.randint(-4,4))*0x010101
    elif name=='moving':rgb=(40 if x<19+f else 200)*0x010101
    else:rgb=0x28b43c if x in (19,20) else 0x28283c
    p.append(rgb)
  imgs.append(p)
 scenes[name]=imgs
all_input=[];all_rgb=[];met={};outputs={m:[] for m in range(4)};protects={m:[] for m in range(4)};grayouts={m:[] for m in range(4)};thresholds=[]
inside=[y*W+x for y in range(5,H-5) for x in range(5,W-5)]
def density(fs):return 100*sum(bool(p[i]) for p in fs for i in inside)/(len(fs)*len(inside))
for name,imgs in scenes.items():
 old=[luma(common(p,W,H,False)) for p in imgs];newrgb=[common(p,W,H,True) for p in imgs];new=[luma(p) for p in newrgb]
 std_old=statistics.pstdev([p[i] for p in old for i in inside]);std_new=statistics.pstdev([p[i] for p in new for i in inside])
 met[name]={'gray_std_old':std_old,'gray_std_new':std_new,'thresholds':{}}
 if name.startswith('flat'):assert std_new<std_old*.88,(name,std_old,std_new)
 for t in [0,5,10,22,47]:
  olde=[];newe=[];oldp=[];newp=[]
  for m in range(4):
   o=[edge(p,W,H,m,t,False) for p in old];n=[edge(p,W,H,m,t,True) for p in new]
   olde.append([v[1] for v in o]);newe.append([v[1] for v in n]);oldp.append([v[2] for v in o]);newp.append([v[2] for v in n])
   for k in range(F):
    outputs[m]+=n[k][1];protects[m]+=n[k][2];grayouts[m]+=n[k][0]
  olde.append(vote(olde[3],oldp[3]));newe.append(vote(newe[3],newp[3]))
  met[name]['thresholds'][t]={'old_edge_percent':[round(density(a),3) for a in olde], 'new_edge_percent':[round(density(a),3) for a in newe]}
  if name in ['weak_step','moving','thin_color']:
   for m in range(4):
    before=sum(bool(v) for frame in olde[m] for v in frame);after=sum(bool(v) for frame in newe[m] for v in frame)
    if before:assert after>=before*.85,(name,t,m,before,after)
  if name=='weak_noisy' and t<=22:
   # Count coverage of the known step, not all white pixels: eliminating
   # flat-background noise must not be misreported as losing real detail.
   for m in range(4):
    before=sum(any(p[y*W+x] for x in range(22,26)) for p in olde[m] for y in range(5,H-5))
    after=sum(any(p[y*W+x] for x in range(22,26)) for p in newe[m] for y in range(5,H-5))
    if before:assert after>=before*.85,('noisy true-edge rows',t,m,before,after)
  for k in range(F):all_input+=imgs[k];all_rgb+=newrgb[k];thresholds.append(t)
metrics=OUT/'mild_noise_metrics.json';metrics.write_text(json.dumps(met,indent=2))
ip=write_hex('mild_input',all_input);rp=write_hex('mild_rgb',all_rgb);tp=write_hex('mild_threshold',thresholds)
decl=[];inst=[];mon=[];loads=[]
for m in range(4):
 gp=write_hex(f'mild_g{m}',grayouts[m]);ep=write_hex(f'mild_e{m}',outputs[m]);pp=write_hex(f'mild_p{m}',protects[m])
 decl.append(f'wire ev{m},es{m},ee{m},gv{m},gs{m},ge{m},p{m},busy{m};wire[7:0] ed{m},gd{m};integer gc{m}=0,ec{m}=0;reg[7:0] goldg{m}[0:TOTAL-1],golde{m}[0:TOTAL-1],goldp{m}[0:TOTAL-1];')
 inst.append(f'''canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1)) d{m}(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),.threshold(threshold),.algorithm(2'd{m}),.busy(busy{m}),
 .gray_valid(gv{m}),.gray_sop(gs{m}),.gray_eop(ge{m}),.gray_data(gd{m}),.edge_valid(ev{m}),.edge_sop(es{m}),.edge_eop(ee{m}),.edge_data(ed{m}),.edge_protect(p{m}));''')
 mon.append(f'''if(gv{m}) begin
 if(gd{m}!==goldg{m}[gc{m}] || gs{m}!==(gc{m}%N==0) || ge{m}!==(gc{m}%N==N-1)) $fatal(1,"gray mode{m} index%0d",gc{m});gc{m}=gc{m}+1;end
 if(ev{m}) begin
 if(ed{m}!==golde{m}[ec{m}] || p{m}!==goldp{m}[ec{m}][0] || es{m}!==(ec{m}%N==0) || ee{m}!==(ec{m}%N==N-1)) $fatal(1,"edge/protect mode{m} index%0d got%0d/%b expected%0d/%b",ec{m},ed{m},p{m},golde{m}[ec{m}],goldp{m}[ec{m}][0]);ec{m}=ec{m}+1;end''')
 loads.append(f'$readmemh("{gp}",goldg{m});$readmemh("{ep}",golde{m});$readmemh("{pp}",goldp{m});')
tb=r'''`timescale 1ns/1ps
module tb;
 localparam W=@W@,H=@H@,N=W*H,F=@F@,TOTAL=N*F;
 reg clk=0;always #5.952381 clk=~clk;reg rst=0,fv=0,iv=0;reg[23:0] input_rgb=0;reg[9:0] threshold=0;
 wire vf,v,s,e,overflow;wire[23:0] rgb,pre;wire pv,pf;wire[10:0] xout,yout;
 camera_rgb_denoise #(.WIDTH(W),.HEIGHT(H)) preprocess(clk,rst,fv,iv,input_rgb,pf,pv,pre);
 camera_full_view #(.IN_W(W),.IN_H(H),.WIDTH(W),.HEIGHT(H),.IMAGE_H(H),.FIFO_BITS(6),.LINE_GAP(12)) view(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_frame(pf),.in_valid(pv),.in_rgb(pre),.out_valid(v),.out_sop(s),.out_eop(e),.out_rgb(rgb),.out_x(xout),.out_y(yout),.overflow(overflow));
 wire[9:0] sum={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};wire[7:0] gray=sum[9:2];
 @DECL@ @INST@
 reg[23:0] input_mem[0:TOTAL-1],expected[0:TOTAL-1];reg[9:0] thrs[0:F-1];integer count=0,f,x,y;
 always @(posedge clk) if(rst) begin
  if(overflow) $fatal(1,"front FIFO overflow");
  if(v) begin
   if(rgb!==expected[count] || xout!=count%W || yout!=(count%N)/W) $fatal(1,"RGB common output index%0d got%h expected%h",count,rgb,expected[count]);count=count+1;
  end
  @MON@
 end
 initial begin
  $readmemh("@INPUT@",input_mem);$readmemh("@RGB@",expected);$readmemh("@THR@",thrs);@LOADS@
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<F;f=f+1) begin
   threshold=thrs[f];fv=1;
   for(y=0;y<H;y=y+1) begin
    for(x=0;x<W;x=x+1) begin iv=1;input_rgb=input_mem[f*N+y*W+x];@(negedge clk);end
    iv=0;repeat(64) @(negedge clk);
   end
   fv=0;repeat(10*W+300) @(negedge clk);
   if(count!=(f+1)*N || ec0!=(f+1)*N || ec1!=(f+1)*N || ec2!=(f+1)*N || ec3!=(f+1)*N) $fatal(1,"lost frame%0d count%0d ec%0d/%0d/%0d/%0d",f,count,ec0,ec1,ec2,ec3);
  end
  $display("PASS adaptive common RGB/luma and4 algorithms:210 frames, THR0/5/10/22/47, exact pixels/markers/polarity protection; flat noise, weak step, moving and thin colored targets");$finish;
 end
endmodule
'''
for k,v in [('W',W),('H',H),('F',len(thresholds)),('DECL','\n'.join(decl)),('INST','\n'.join(inst)),('MON','\n'.join(mon)),('LOADS','\n'.join(loads)),('INPUT',ip),('RGB',rp),('THR',tp)]:tb=tb.replace('@'+k+'@',str(v))
simulate('mild_noise',tb,['src/camera_rgb_denoise.v','src/camera_full_view.v']+RTL,timeout=600)
for name in ['flat12','flat24','weak_step','weak_noisy','moving','thin_color']:
 print(name,json.dumps({'std_old':met[name]['gray_std_old'],'std_new':met[name]['gray_std_new'],'THR22':met[name]['thresholds'][22]}))
