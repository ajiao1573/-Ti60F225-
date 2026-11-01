from run_canny import simulate

tb=r'''`timescale 1ns/1ps
module tb;
 reg [11:0] x=600,y=660;reg locked,valid;reg [47:0] ascii="JQXK90";
 wire [23:0] pixel;wire active;
 nz_plate_osd #(.X_START(600),.Y_START(660),.SCALE(4),.RESULT_ONLY(1)) dut(
 .x_pos(x),.y_pos(y),.locked(locked),.valid(valid),.ascii(ascii),.pixel(pixel),.active(active));
 reg [34:0] glyphs[0:3];integer c,r,k;reg ink;
 initial begin
  glyphs[0]=35'b00111000100001000010100101001001100;
  glyphs[1]=35'b01110100011000110001101011001001101;
  glyphs[2]=35'b10001100010101000100010101000110001;
  glyphs[3]=35'b10001100101010011000101001001010001;
  #1;locked=0;valid=0;#1;if(dut.text!=="PLATE:------            ") $fatal(1,"search placeholder");
  locked=1;#1;if(dut.text!=="PLATE:UNREADABLE        ") $fatal(1,"unreadable status");
  valid=1;#1;if(dut.text[143:96]!=="JQXK90") $fatal(1,"ASCII result placement");
  for(c=0;c<4;c=c+1) for(r=0;r<7;r=r+1) for(k=0;k<5;k=k+1) begin
   x=600+(6+c)*32+k*4;y=660+r*4;ink=glyphs[c][34-r*5-k];#1;
   if(!active || pixel!==(ink ? 24'h00ff80 : 24'h081020)) $fatal(1,"glyph %0d row=%0d col=%0d",c,r,k);
  end
  x=599;#1;if(active) $fatal(1,"left boundary");
  x=600;y=708;#1;if(active) $fatal(1,"bottom boundary");
  $display("PASS NZ HDMI OSD: search/failure states, ASCII placement, J/Q/X/K glyphs, scale and bounds");$finish;
 end
endmodule
'''
simulate('nz_plate_osd',tb,['src/nz_plate_osd.v'])