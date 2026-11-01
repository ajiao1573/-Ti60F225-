from run_canny import simulate
tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0;reg [1:0] keys=3;
 wire [2:0] gear;wire [2:0] alg;wire [1:0] view;wire [9:0] thr;wire [7:0] adjustment;wire frozen;
 video_key_control #(.CLOCK_HZ(100),.DEBOUNCE(3),.PLATE_SEG_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst),.keys(keys),.gear(gear),.algorithm(alg),.display_mode(view),.threshold(thr),.plate_adjust(adjustment),.freeze_requested(frozen));
 task press(input [1:0] mask,input integer duration);
 begin keys=~mask;repeat(duration+8) @(negedge clk);keys=3;repeat(12) @(negedge clk);end endtask
 integer g;
 initial begin
  repeat(8) @(negedge clk);rst=1;repeat(8) @(negedge clk);
  if(gear!=0 || thr!=72 || adjustment!=128) $fatal(1,"initial state");
  press(2,110);
  repeat(5) press(2,10);
  if(alg!=3 || gear!=1) $fatal(1,"five algorithms retained with six gears");
  press(1,110);
  for(g=1;g<=5;g=g+1) begin
   press(2,110);if(gear!=g) $fatal(1,"six gear sequence g=%0d actual=%0d",g,gear);
   if(g==3 && !frozen) $fatal(1,"history still freezes");
   if(g==4 && frozen) $fatal(1,"shape retained and leaves history");
  end
  press(2,10);if(adjustment!=133 || thr!=72 || gear!=5) $fatal(1,"plate plus independent of edge threshold");
  press(1,10);if(adjustment!=128) $fatal(1,"plate minus");
  repeat(30) press(2,10);if(adjustment!=255) $fatal(1,"upper saturation");
  repeat(60) press(1,10);if(adjustment!=0) $fatal(1,"lower saturation");
  press(3,110);if(!frozen || gear!=5) $fatal(1,"plate freeze");
  press(3,110);if(frozen) $fatal(1,"plate resume");
  press(2,110);if(gear!=0) $fatal(1,"six -> one");
  press(1,110);if(gear!=5) $fatal(1,"one -> six");
  press(1,110);if(gear!=4) $fatal(1,"six -> shape");
  press(2,110);press(3,110);if(gear!=5 || !frozen) $fatal(1,"plate re-arm gesture");
  press(2,110);if(gear!=0 || frozen) $fatal(1,"plate exit leaves next gear capturing");
  press(1,110);press(1,210);if(gear!=0) $fatal(1,"two second home");
  $display("PASS six gear controls: 1/2/3/4/5/6/1, shape retained, reverse, plate adjustment saturation, independent edge threshold, freeze/resume and home");$finish;
 end
endmodule
'''
simulate('plate_keys',tb,['src/video_key_control.v'])
