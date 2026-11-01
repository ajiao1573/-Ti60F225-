"""Full-size RAW8 DVP -> central crop, plus actual HDMI raster timing."""
from run_canny import simulate
from pathlib import Path
import sys
if '--hdmi-only' not in sys.argv:
 simulate('ov5640_dvp',r'''
 `timescale 1ns/1ps
 module tb;
  reg clk=0;always #5 clk=~clk;
  reg rst=0,cfg=0,vs=0,href=0;
  reg [8:0] ri=0;wire [23:0] rd;wire [7:0] delay_ms;wire [8:0] rc;
  reg [7:0] polarity;integer k;
  ov5640_1080p30_regs regs(ri,rd,delay_ms,rc);reg [7:0] data=0;
  wire fv,pv,err,cv,ch,cd;wire [7:0] pix,cp;wire [11:0] lw,lh;
  ov5640_dvp dut(clk,rst,cfg,vs,href,data,fv,pv,pix,err,lw,lh);
  Sensor_Image_XYCrop #(.IMAGE_HSIZE_SOURCE(1920),.IMAGE_VSIZE_SOURCE(1080),
  .IMAGE_HSIZE_TARGET(1280),.IMAGE_YSIZE_TARGET(720),.PIXEL_DATA_WIDTH(8)) crop(
  .clk(clk),.rst_n(rst),.image_in_vsync(fv),.image_in_href(pv),.image_in_de(pv),
  .image_in_data(pix),.image_out_vsync(cv),.image_out_href(ch),.image_out_de(cd),.image_out_data(cp));
  integer f,x,y,ox=0,oy=0,pixels=0,rawpixels=0,frames=0;reg chd=0,cvd=0;
  function [7:0] pattern;input integer xx,yy;begin pattern=(xx*17+yy*31) ^ (xx>>8) ^ (yy>>8);end endfunction
  always @(negedge clk) if(rst) begin
   if(pv) rawpixels=rawpixels+1;
   if(ch) begin
    if(f<3 || !cv || !cd) $fatal(1,"warmup/qualifier leak");
    if(cp!==pattern(ox+320,oy+180)) $fatal(1,"crop pixel x=%0d y=%0d got=%h expected=%h",ox,oy,cp,pattern(ox+320,oy+180));
    ox=ox+1;pixels=pixels+1;
   end else if(chd) begin
    if(ox!=1280) $fatal(1,"crop width %0d",ox);
    ox=0;oy=oy+1;
   end
   if(cvd && !cv) begin
    if(oy!=720) $fatal(1,"crop height %0d",oy);
    oy=0;frames=frames+1;
   end
   chd=ch;cvd=cv;
  end
  task tick;begin @(posedge clk);#1;end endtask
  task sync;begin vs=!polarity[0];repeat(8) tick;vs=polarity[0];repeat(8) tick;end endtask
  initial begin
   polarity=8'h20;
   for(k=0;k<rc;k=k+1) begin ri=k;#1;if(rd[23:8]==16'h4740) polarity=rd[7:0];end
   // Model this adapter: VSYNC bit inversion and reference HREF bit 1=0.
   if(polarity!=8'h20) $fatal(1,"sensor/receiver polarity mismatch %h",polarity);
   repeat(5) tick;rst=1;
   href=1;repeat(8) tick;href=0;
   if(pv || fv) $fatal(1,"camera emitted before configuration");
   cfg=1;repeat(8) tick;
   for(f=0;f<5;f=f+1) begin
    sync;
    for(y=0;y<1080;y=y+1) begin
     for(x=0;x<1920;x=x+1) begin href=1;data=pattern(x,y);tick;end
     href=0;repeat(12) tick;
    end
    repeat(16) tick;
   end
   vs=1;repeat(8) tick;
   if(err || lw!=1920 || lh!=1080 || frames!=2 || pixels!=2*1280*720 || rawpixels!=2*1920*1080)
    $fatal(1,"full frames err=%0d width=%0d height=%0d frames=%0d crop=%0d raw=%0d",err,lw,lh,frames,pixels,rawpixels);
   // Drop configuration mid-stream, then verify malformed input diagnostics.
   cfg=0;repeat(10) tick;cfg=1;repeat(10) tick;vs=0;repeat(8) tick;sync;
   href=1;repeat(1919) tick;href=0;repeat(12) tick;vs=1;repeat(8) tick;
   if(!err || lw!=1919 || lh!=1) $fatal(1,"malformed frame not detected");
   $display("PASS RAW8 DVP: 3 discarded warmup frames, 2 full 1920x1080 frames; exact central 1280x720 crop; malformed frame detection");
   $finish;
  end
  initial begin #150000000;$fatal(1,"DVP timeout");end
 endmodule
 ''',['src/cmos_i2c/ov5640_dvp.v','src/Sensor_Image_XYCrop.v','src/cmos_i2c/ov5640_1080p30_regs.v'],timeout=180)
 
simulate('hdmi_1080p30',r'''
`timescale 1ns/1ps
module tb;
 reg clk=0;always #6.734 clk=~clk;
 reg rst=0;wire hs,vs,de,req;wire [11:0] x,y;wire [47:0] rgb;
 lcd_driver dut(.clk(clk),.rst_n(rst),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
 .lcd_request(req),.lcd_xpos(x),.lcd_ypos(y),.lcd_data({12'd0,x,12'd0,y}),.lcd_rgb(rgb));
 integer n=0,active=0,requests=0,hsc=0,vsc=0,ex=0,ey=0;
 initial begin
  repeat(4) @(negedge clk);rst=1;
  // Run to the second counter origin so all registered outputs have settled.
  wait(dut.hcnt==2199 && dut.vcnt==1124);@(negedge clk);
  repeat(2200*1125) begin
   @(negedge clk);
   if(!hs) hsc=hsc+1;if(!vs) vsc=vsc+1;
   if(req) begin
    if(x!=ex || y!=ey) $fatal(1,"request coordinates %0d,%0d expected %0d,%0d",x,y,ex,ey);
    requests=requests+1;if(ex==1919) begin ex=0;ey=ey+1;end else ex=ex+1;
   end
   if(de) begin
    if(rgb[35:24]!==12'(active%1920) || rgb[11:0]!==12'(active/1920))
     $fatal(1,"RGB/DE alignment pixel=%0d rgb=%h",active,rgb);
    active=active+1;
   end
  end
  if(requests!=1920*1080 || active!=1920*1080 || hsc!=44*1125 || vsc!=5*2200)
   $fatal(1,"raster req=%0d active=%0d hs=%0d vs=%0d",requests,active,hsc,vsc);
  $display("PASS HDMI 1080p30: 2200x1125 total, 1920x1080 active, sync 44x5, every pixel coordinate aligned; 74250000/(2200*1125)=30");
  $finish;
 end
endmodule
'''+Path('src/lcd_driver.v').read_text().replace('`include "lcd_para.v"','`include "src/lcd_para.v"'),[],timeout=120)
