`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg [1:0] keys=3;
 wire [2:0] gear;wire [2:0] algorithm;wire [1:0] mode;wire [9:0] threshold;
 wire [7:0] plate_adjust_unused;wire frozen,compare;wire [2:0] replay,left,right;
 video_key_control #(.CLOCK_HZ(100),.DEBOUNCE(3),.ENABLE_DDR_FRAME(0)) dut(
  clk,rst,keys,gear,algorithm,mode,threshold,frozen,compare,replay,left,right);
 integer j;
 task press;input [1:0] mask;input integer cycles;
  begin keys=~mask;repeat(cycles+8) @(negedge clk);keys=3;repeat(12) @(negedge clk);end
 endtask

 initial begin
  repeat(8) @(negedge clk);rst=1;repeat(8) @(negedge clk);
  press(2,110);press(2,10);if(algorithm!=0) $fatal(1,"disabled history skips temporal");
  press(2,110);press(2,110);
  if(gear!=4 || frozen) $fatal(1,"history disabled skips to shape");
  press(1,110);if(gear!=2) $fatal(1,"reverse skips history");
  press(1,210);if(gear!=1) $fatal(1,"long minus skips no extra gears");press(1,110);if(gear!=0) $fatal(1,"back to threshold");press(1,110);if(gear!=4) $fatal(1,"reverse wraps to shape");
  press(2,110);if(gear!=0) $fatal(1,"forward wraps to threshold");
  $display("PASS five gears with history disabled");$finish;
 end
endmodule
