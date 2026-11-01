from pathlib import Path
import random,statistics,json
from run_canny import ROOT,OUT,simulate,write_hex
IW,IH,W,H,F=1920,28,848,12,5;palette=[(0,0,0),(180,0,0),(0,150,0),(0,0,120),(180,150,0),(180,0,120),(0,150,120),(180,180,180)]
rng=random.Random(20261020);inputs=[];expected=[];thumbs=[];raw_noise=[]
def at(p,x,y):
 x=1 if x<0 else IW-2 if x>=IW else x;y=1 if y<0 else IH-2 if y>=IH else y
 return p[y*IW+x]
for f in range(F):
 p=[]
 for y in range(IH):
  for x in range(IW):
   if f==0:c=(128,128,128)
   elif f==1:v=128+rng.randint(-24,24);c=(v,v,v);raw_noise.append(v)
   elif f==2:v=64 if x%2==0 else 192;c=(v,v,v)
   elif f==3:c=palette[x//240]
   else:c=((x+3*y)&255,(3*x+y)&255,(x+7*y)&255)
   p.append(c)
 inputs +=[(r<<16)|(g<<8)|b for r,g,b in p]
 filtered=[]
 for y in range(H):
  sy=y*(IH-1)//(H-1)
  for x in range(W):
   sx=x*(IW-1)//(W-1)
   rgb=[(sum(at(p,sx+dx,sy+dy)[c]*wx*wy for dx,wx in [(-1,1),(0,2),(1,1)] for dy,wy in [(-1,1),(0,2),(1,1)])+8)//16 for c in range(3)]
   filtered.append(tuple(rgb));expected.append((rgb[0]<<16)|(rgb[1]<<8)|rgb[2])
 for ty in range(H//2):
  for tx in range(W//2):
   q=[(sum(filtered[(2*ty+dy)*W+2*tx+dx][c] for dy in (0,1) for dx in (0,1))+2)//4 for c in range(3)]
   thumbs.append((q[0]<<16)|(q[1]<<8)|q[2])
ip=write_hex('noise_fix_front_input',inputs);ep=write_hex('noise_fix_front_expected',expected);tp=write_hex('noise_fix_thumbnail_expected',thumbs)
top=(ROOT/'example_top.v').read_text(encoding='utf-8');a=top.index('wire thumbnail_valid,');b=top.index('wire split_store_eof=',a);frag=top[a:b]
tb=r'''@TICK@timescale 1ns/1ps
module tb;
 localparam IW=1920,IH=28,W=848,H=12,F=5,N=W*H;
 reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;reg rstn_sys=0,iv=0,iframe=0;reg[23:0] rgb_in=0;
 wire sv,sf;wire[23:0] srgb;
 camera_rgb_smooth #(.WIDTH(IW),.HEIGHT(IH)) smooth(
 .clk(cmos_pclk),.rst_n(rstn_sys),.in_frame(iframe),.in_valid(iv),.in_rgb(rgb_in),
 .out_frame(sf),.out_valid(sv),.out_rgb(srgb));
 wire v,s,e,overflow;wire[10:0] full_view_x,full_view_y;wire[23:0] camera_rgb;
 camera_full_view #(.IN_W(IW),.IN_H(IH),.WIDTH(W),.HEIGHT(H),.IMAGE_H(H),.FIFO_BITS(5)) resize(
 .clk(cmos_pclk),.rst_n(rstn_sys),.enable(1'b1),.in_frame(sf),.in_valid(sv),.in_rgb(srgb),
 .out_valid(v),.out_sop(s),.out_eop(e),.out_rgb(camera_rgb),.out_x(full_view_x),.out_y(full_view_y),.overflow(overflow));
 wire rgb_store_en=v;
 @FRAGMENT@
 reg[23:0] input_mem[0:IW*IH*F-1],expected[0:N*F-1],thumb[0:W/2*(H/2)*F-1];
 integer gc=0,tc=0,pc=0,f,x,y,index,ei,grayval;
 always @(posedge cmos_pclk) if(rstn_sys) begin
 if(overflow) $fatal(1,"resize overflow");
 if(v) begin
 if(camera_rgb!==expected[gc] || s!==(gc%N==0) || e!==(gc%N==N-1)) $fatal(1,"common RGB x=%0d y=%0d got=%h exp=%h",full_view_x,full_view_y,camera_rgb,expected[gc]);
 gc=gc+1;end
 if(thumbnail_valid) begin
 if(thumbnail_rgb!==thumb[tc] || thumbnail_eol!==(tc%424==423)) $fatal(1,"thumbnail %0d got=%h exp=%h",tc,thumbnail_rgb,thumb[tc]);
 tc=tc+1;end
 if(gray_store_en) begin
 index=pc%432;ei=(pc/432)*424+index;
 grayval=index<424 ? (thumb[ei][23:16]+2*thumb[ei][15:8]+thumb[ei][7:0])/4:0;
 if(gray_store_data!==8'(grayval)) $fatal(1,"gray packing %0d got=%0d exp=%0d",pc,gray_store_data,grayval);
 pc=pc+1;end
 end
 initial begin
 $readmemh("@INPUT@",input_mem);$readmemh("@EXPECTED@",expected);$readmemh("@THUMB@",thumb);
 repeat(8) @(negedge cmos_pclk);rstn_sys=1;
 for(f=0;f<F;f=f+1) begin
 iframe=1;
 for(y=0;y<IH;y=y+1) begin
 for(x=0;x<IW;x=x+1) begin @(negedge cmos_pclk);iv=1;rgb_in=input_mem[f*IW*IH+y*IW+x];end
 @(negedge cmos_pclk);iv=0;repeat(64) @(negedge cmos_pclk);
 end
 @(negedge cmos_pclk);iframe=0;repeat(IW+64) @(negedge cmos_pclk);
 wait(gc==(f+1)*N);repeat(50) @(negedge cmos_pclk);
 end
 if(tc!=424*6*F || pc!=432*6*F) $fatal(1,"missing thumbnail/pad");
 $display("PASS 1920->848 RGB anti-alias, exact colors/all four borders, current frames, 2x2 thumbnail and top gray padding");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
'''
tb=tb.replace('@TICK@',chr(96)).replace('@FRAGMENT@',frag).replace('@INPUT@',ip).replace('@EXPECTED@',ep).replace('@THUMB@',tp)
simulate('noise_fix_frontend',tb,['src/camera_rgb_smooth.v','src/camera_full_view.v','src/video_thumbnail2.v'],timeout=180)
filtered_noise=[(v>>8)&255 for v in expected[W*H:2*W*H]]
thumb_noise=[(v>>8)&255 for v in thumbs[W//2*(H//2):2*(W//2*(H//2))]]
assert set(expected[2*W*H:3*W*H])=={0x808080},'2px texture should be removed before shrinking'
metrics={'raw_noise_std':statistics.pstdev(raw_noise),'common_rgb_gray_std':statistics.pstdev(filtered_noise),'thumbnail_gray_std':statistics.pstdev(thumb_noise)}
assert metrics['common_rgb_gray_std']<metrics['raw_noise_std']*.5,metrics
assert metrics['thumbnail_gray_std']<metrics['common_rgb_gray_std'],metrics
(OUT/'noise_fix_front_metrics.json').write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics,indent=2))
