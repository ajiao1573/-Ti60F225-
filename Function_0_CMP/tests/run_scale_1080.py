from pathlib import Path
from run_canny import simulate
simulate('scale_1080',r"""
`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0;
 wire req,de;wire [11:0] x,y,sx,sy;wire take;wire [23:0] image;wire [47:0] rgb;
 wire [23:0] source={sx[7:0],sy[7:0],(sx[7:0]^sy[7:0])};
 video_scale_3_2 scale(clk,rst,req,x,y,source,sx,sy,take,image);
 lcd_driver lcd(.clk(clk),.rst_n(rst),.lcd_request(req),.lcd_xpos(x),.lcd_ypos(y),
 .lcd_en(de),.lcd_data({2{image}}),.lcd_rgb(rgb));
 integer n=0,takes=0,ex,ey,lastx=-1,lasty=-1;
 initial begin
  repeat(4) @(negedge clk);rst=1;
  // Include the first frame: no prior cache initialization is allowed.
  while(n<1920*1080) begin
   @(negedge clk);
   if(take) begin
    if(sx!=takes%1280 || sy!=takes/1280) $fatal(1,"source reread/skip sx=%0d sy=%0d take=%0d",sx,sy,takes);
    takes=takes+1;
   end
   if(de) begin
    ex=((n%1920)*2)/3;ey=((n/1920)*2)/3;
    if(rgb[23:0]!=={8'(ex),8'(ey),8'(ex^ey)})
     $fatal(1,"scale/BRAM/DE mismatch pixel=%0d got=%h expected=%h",n,rgb[23:0],{8'(ex),8'(ey),8'(ex^ey)});
    n=n+1;
   end
  end
  if(takes!=1280*720) $fatal(1,"source count %0d",takes);
  $display("PASS 1080p 3:2 scaler: 2073600 output pixels, 921600 unique source reads; horizontal repeats, synchronous line replay, first-frame cache and LCD alignment");$finish;
 end
endmodule
"""+Path('src/lcd_driver.v').read_text().replace('`include "lcd_para.v"','`include "src/lcd_para.v"'),['src/video_scale_3_2.v'],timeout=180)
