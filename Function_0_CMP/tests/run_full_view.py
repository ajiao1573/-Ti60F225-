"""Full-field RGB coordinate regression, padding, frame gating and FIFO occupancy."""
from run_canny import simulate
from pathlib import Path
import sys

top=Path('example_top.v').read_text(encoding='utf-8')
assert '.IMAGE_HSIZE_TARGET (1920 / CSI_STRB_WIDTH)' in top
assert '.IMAGE_YSIZE_TARGET (1080' in top
assert '.IMG_HDISP(1920)' in top and '.IMG_VDISP(1080)' in top
assert 'wire roi_valid=gray_valid;' in top
assert '.in_rgb({pre_rgb_r,pre_rgb_g,pre_rgb_b})' in top
assert '.rgb_data       (camera_rgb)' in top and '.left_rgb_data(camera_rgb)' in top

def check(iw,ih,w,h,im,fb):
 tb=r'''
`timescale 1ns/1ps
module tb;
 localparam IW=@IW@,IH=@IH@,W=@W@,H=@H@,IM=@IM@,TOP=(H-IM)/2;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=0,fv=0,valid=0;reg [23:0] rgb=0;
 wire ov,sop,eop,overflow;wire [23:0] out_rgb;wire [10:0] ox,oy;
 camera_full_view #(.IN_W(IW),.IN_H(IH),.WIDTH(W),.HEIGHT(H),
 .IMAGE_H(IM),.FIFO_BITS(@FB@)) dut(clk,rst,en,fv,valid,rgb,ov,sop,eop,out_rgb,ox,oy,overflow);
 integer frame,x,y,checks=0,frames=0,ex=0,ey=0,sx,sy,maxfill=0,fill;
 reg [23:0] expected;
 always @(negedge clk) if(rst) begin
  fill=dut.wp-dut.rp;if(fill>maxfill) maxfill=fill;
  if(overflow) $fatal(1,"FIFO overflow");
  if(ov) begin
   if(ox!=ex || oy!=ey || sop!==(ex==0 && ey==0) || eop!==(ex==W-1 && ey==H-1))
    $fatal(1,"coordinates/framing %d,%d expected %d,%d",ox,oy,ex,ey);
   if(ey<TOP || ey>=TOP+IM) expected=0;
   else begin
    sx=ex*(IW-1)/(W-1);sy=(ey-TOP)*(IH-1)/(IM-1);
    expected=(frame<<22)|(sy<<11)|sx;
   end
   if(out_rgb!==expected) $fatal(1,"pixel %d,%d got=%h expected=%h",ex,ey,out_rgb,expected);
   checks=checks+1;
   if(ex==W-1) begin ex=0;if(ey==H-1) begin ey=0;frames=frames+1;end else ey=ey+1;end
   else ex=ex+1;
  end
 end
 task tick;begin @(posedge clk);#1;end endtask
 initial begin
  repeat(5) tick;rst=1;
  // Disabled frame must not leak even if enable rises after its first pixel.
  frame=0;fv=1;
  for(y=0;y<IH;y=y+1) for(x=0;x<IW;x=x+1) begin
   valid=1;rgb=(y<<11)|x;if(y==1) en=1;tick;
  end
  fv=0;valid=0;repeat(20) tick;
  if(checks) $fatal(1,"partial input frame accepted");
  for(frame=1;frame<=3;frame=frame+1) begin
   fv=1;en=1;
   for(y=0;y<IH;y=y+1) begin
    for(x=0;x<IW;x=x+1) begin
     valid=1;rgb=(frame<<22)|(y<<11)|x;tick;
     // Toggle downstream availability inside an accepted frame.
     if(y==IH/2) en=0;
    end
    valid=0;repeat(frame==2 ? 23 : 0) tick;
   end
   valid=0;fv=0;
   wait(frames==frame);repeat(30) tick;
  end
  if(checks!=3*W*H) $fatal(1,"pixel count %d",checks);
  $display("PASS full view IW=%0d IH=%0d: %0d pixels, all four corners, letterbox, 3 frames, enable gating, FIFO max=%0d",IW,IH,checks,maxfill);
  $finish;
 end
 initial begin #400000000;$fatal(1,"timeout");end
endmodule
'''
 for key,value in [('IW',iw),('IH',ih),('W',w),('H',h),('IM',im),('FB',fb)]:
  tb=tb.replace('@'+key+'@',str(value))
 simulate(f'full_view_{iw}',tb,['src/camera_full_view.v'])

check(64,36,32,18,18,5)
if '--full' in sys.argv: check(1920,1080,848,477,477,5)
