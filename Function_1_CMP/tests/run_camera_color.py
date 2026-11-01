"""Exercise the real Bayer frontend, neutral sensor color and channel order."""
from pathlib import Path
import re
from run_canny import simulate

top=Path('example_top.v').read_text(encoding='utf-8')
front=top[top.index(') u_pre_canny_bayer2rgb'):top.index('// Y ≈')]
assert ".mirror          (2'b00)" in front
assert '.rgb_data       (camera_rgb)' in top and '.left_rgb_data(camera_rgb)' in top
config=Path('src/cmos_i2c/ov5640_1080p30_regs.v').read_text(encoding='utf-8')
assert "24'h382046" in config
assert "24'h430000" in config and "24'h501f03" in config and "24'h382100" in config
gain='wire [23:0] camera_rgb={pre_rgb_r,pre_rgb_g,pre_rgb_b};'
tb=r'''
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,vs=0,de=0;reg [7:0] raw=0;
 wire valid,frame_valid;wire [7:0] pre_rgb_r,pre_rgb_g,pre_rgb_b;
 raw8_rgb_frame #(.IMG_HDISP(1920),.IMG_VDISP(1080)) dut(
 .clk(clk),.rst_n(rst),.mirror(2'b00),.per_frame_vsync(vs),
 .per_frame_href(de),.per_frame_hsync(de),.per_img_RAW(raw),
 .post_frame_vsync(frame_valid),.post_frame_href(valid),.post_img_red(pre_rgb_r),
 .post_img_green(pre_rgb_g),.post_img_blue(pre_rgb_b));
''' +gain+r'''
 integer f,x,y,ox=0,oy=0,checks=0,bar;
 reg vd=0;reg [23:0] c,expected;
 function [23:0] palette;
 input integer frame,col;
 integer p;
 begin
  p=(col/240+frame)%8;
  case(p)
   0:palette=24'h000000;1:palette=24'hb40000;
   2:palette=24'h009600;3:palette=24'h000078;
   4:palette=24'hb49600;5:palette=24'hb40078;
   6:palette=24'h009678;7:palette=24'hb4b4b4;
  endcase
 end
 endfunction
 function [23:0] balanced;
 input [23:0] rgb;
 integer rr,bb;
 begin
  rr=rgb[23:16];bb=rgb[7:0];
  balanced={8'(rr>255 ? 255 : rr),rgb[15:8],8'(bb>255 ? 255 : bb)};
 end
 endfunction
 always @(negedge clk) begin
  if(!frame_valid) begin ox=0;oy=0;vd=0;end
  else begin
   if(valid) begin
    // Check all rows including borders; exclude only true color transitions.
    if((ox%240>=16 && ox%240<224) || ox<16 || ox>=1904) begin
     c=palette(f,ox);expected=balanced(c);
     if({pre_rgb_r,pre_rgb_g,pre_rgb_b}!==c || camera_rgb!==expected)
      $fatal(1,"camera color frame=%0d x=%0d y=%0d raw RGB=%h expected=%h balanced=%h expected=%h",
             f,ox,oy,{pre_rgb_r,pre_rgb_g,pre_rgb_b},c,camera_rgb,expected);
     checks=checks+1;
    end
    // The centered window may pause within a logical row. Count accepted
    // pixels, rather than treating every valid gap as a new image row.
    if(ox==1919) begin ox=0;oy=oy+1;end else ox=ox+1;
   end
   vd=valid;
  end
 end
 initial begin
  repeat(10) @(posedge clk);#1;rst=1;
  for(f=0;f<3;f=f+1) begin
   @(posedge clk);#1;vs=1;
   for(y=0;y<1080;y=y+1) begin
    for(x=0;x<1920;x=x+1) begin
     @(posedge clk);#1;de=1;c=palette(f,x);
     // Unmirrored reference Bayer input is BGGR.
     raw=(!y[0] && !x[0]) ? c[7:0] : (y[0] && x[0]) ? c[23:16] : c[15:8];
    end
    @(posedge clk);#1;de=0;repeat(64) @(posedge clk);
   end
   @(posedge clk);#1;vs=0;repeat(1920+64) @(posedge clk);
  end
  if(checks!=5495040) $fatal(1,"missing color checks");
  $display("PASS actual camera Bayer/frontend: %0d RGB pixels, 8 colors, all four borders, 3 complete centered frames, RGB routing",checks);
  $finish;
 end
endmodule
'''
simulate('camera_color',tb,['src/raw8_rgb_frame.v'],timeout=180)
