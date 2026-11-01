`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,toggle=0;wire [9:0] fps;
 frame_rate_meter #(.CLOCK_HZ(100)) meter(clk,rst,toggle,fps);
 integer cycle=0;
 always @(posedge clk) if(rst) cycle=cycle+1;
 reg [11:0] x=0,y=0;wire [7:0] pixel;
 threshold_osd #(.X_START(16),.Y_START(16)) osd(x,y,10'd24,10'd30,8'd77,pixel);
 task check;
 input [11:0] xx,yy;input [7:0] expected;
 begin x=xx;y=yy;#1;if(pixel!==expected) $fatal(1,"OSD %0d,%0d got=%0d expected=%0d",xx,yy,pixel,expected);end
 endtask
 initial begin
  #1;check(0,0,77);check(16,16,0);
  // Top-left pixel of T (threshold) and F (FPS), including the 24px offset.
  check(16,20,255);check(16,44,255);check(16,56,255);
  check(20,56,0); // bottom of F is only its left stem
  check(48,44,0);check(50,44,255); // S top row 01111
  check(144,44,77);check(16,62,77); // overlay bounds
  repeat(3) @(negedge clk);rst=1;
  wait(cycle==10);#3;toggle=~toggle;
  wait(cycle==35);#3;toggle=~toggle;
  wait(cycle==70);#3;toggle=~toggle;
  wait(cycle==100);#1;if(fps!==3) $fatal(1,"FPS first window %0d",fps);
  wait(cycle==200);#1;if(fps!==0) $fatal(1,"FPS did not fall to zero");
  // Event reaches the counter exactly on the terminal clock.
  wait(cycle==297);@(negedge clk);toggle=~toggle;
  wait(cycle==300);#1;if(fps!==1) $fatal(1,"FPS rollover lost event %0d",fps);
  wait(cycle==400);#1;if(fps!==0) $fatal(1,"FPS rollover duplicated event");
  @(negedge clk);rst=0;#1;if(fps!==0) $fatal(1,"FPS reset");
  $display("PASS FPS asynchronous events, idle, exact rollover, reset and two-line OSD glyphs");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
