# Actual 1080p LCD driver, presentation scaler and top plate compositor.
from pathlib import Path
import re
from run_canny import simulate
top=Path('example_top.v').read_text(encoding='utf-8')
params=re.search(r'plate_segmenter #(.*?) u_plate_segmenter\(',top,re.S).group(1)
names=['split_left_pixel','plate_guide','plate_display_rgb']
decl='\n'.join(re.search(r'wire\s+(?:\[[^\]]+\]\s+)?'+n+r'\s*=.*?;',top,re.S).group(0) for n in names)
tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #7 clk=~clk;reg rst=0;
 wire [11:0] x,y,view_x,view_y;wire [23:0] plate_rgb,scaled,pixel;wire en,vs,request,view_request;
 wire split_overlap_row=view_y>=241 && view_y<=478;
 wire [7:0] lcd_data=(view_x+view_y)%256;
 '''+decl+r'''
 plate_segmenter #'''+params+r''' dut(.clk(clk),.rst_n(rst),.enable(1'b0),.in_valid(1'b0),.in_sop(1'b0),
 .in_x(11'd0),.in_y(10'd0),.in_gray(8'd0),.adjust(8'd128),
 .pixel_clk(clk),.pixel_rst_n(rst),.vsync(vs),.x_pos(view_x),.y_pos(view_y),.pixel(plate_rgb));
 video_scale_3_2 scale(.clk(clk),.rst_n(rst),.request(request),.x_pos(x),.y_pos(y),.source_rgb(plate_display_rgb),
 .source_x(view_x),.source_y(view_y),.source_request(view_request),.rgb(scaled));
 lcd_driver #(.DATA_WIDTH(24)) lcd(.clk(clk),.rst_n(rst),.lcd_en(en),.lcd_vs(vs),.lcd_request(request),
 .lcd_rgb(pixel),.lcd_xpos(x),.lcd_ypos(y),.lcd_data(scaled));
 integer i,xx,yy,vx,vy,slot,offset,checked=0;reg [7:0] value;reg [23:0] expected;
 initial begin
  for(i=0;i<10240;i=i+1) dut.thumb_mem[i]=(i/20+i%20)%2;
  for(i=0;i<98304;i=i+1) dut.mask_mem[i]=i>=73728 ? (((i%24576)/256+i%256)%256)<128 : (((i%24576)/256+i%256)%256)>=128;
  repeat(5) @(negedge clk);rst=1;
  @(negedge clk);dut.ready=1;dut.count=8;dut.threshold=128;dut.low_contrast=0;
  dut.display_bank=1;dut.display_mask=1;dut.display_boxes={256{1'b1}};
  repeat(2200*1125) begin
   @(posedge clk);xx=x;yy=y;vx=2*xx/3;vy=2*yy/3;expected=0;
   if(vx<424 && vy>=241 && vy<=478) begin
    value=(vx+vy)%256;
    expected=vx>=4 && vx<=419 && vy>=280 && vy<=439 &&
      (vx==4 || vx==419 || vy==280 || vy==439) ? 24'hffff00 : {3{value}};
   end else if(vx>=672 && vx<1184 && vy>=208 && vy<400) begin
    value=((vx-672)/2+(vy-208)/2)%256;
    expected={24{!(value<128 && vx>=680 && vx<1176 && vy>=216 && vy<392)}};
   end else if(vx>=264 && vx<1032 && vy>=552 && vy<680) begin
    slot=(vx-264)/96;offset=(vx-264)%96;
    if(offset<80) expected={24{(((vy-552)/4+offset/4)%2)==0}};
   end
   #1;if(en) begin
    if(pixel!==expected) $fatal(1,"1080p plate alignment x=%0d y=%0d got=%h expected=%h",xx,yy,pixel,expected);
    checked=checked+1;
   end
  end
  if(checked!=1920*1080) $fatal(1,"LCD checked %0d pixels",checked);
  $display("PASS plate 1080p LCD: 2073600 pixels, actual scaler/driver, grayscale preview, guide, black-on-white mask and eight thumbnails");$finish;
 end
endmodule
'''
driver=Path('src/lcd_driver.v').read_text(encoding='utf-8').replace('`include "lcd_para.v"','`include "src/lcd_para.v"')
simulate('plate_lcd_1080',tb+driver,['src/plate_segmenter.v','src/video_scale_3_2.v'],timeout=240)
