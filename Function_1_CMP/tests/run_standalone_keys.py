from run_canny import simulate
tb=r"""@TICK@timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0;reg[1:0] keys=3;
 wire[7:0] adjust;wire rearm;
 plate_key_control #(.CLOCK_HZ(100),.DEBOUNCE(3)) dut(.clk(clk),.rst_n(rst),.keys(keys),.adjust(adjust),.rescan_toggle(rearm));
 task press(input[1:0] mask,input integer duration);begin
 keys=~mask;repeat(duration+8) @(negedge clk);keys=3;repeat(12) @(negedge clk);end endtask
 initial begin
 repeat(8) @(negedge clk);rst=1;repeat(8) @(negedge clk);
 if(adjust!=128 || rearm) $fatal(1,"boot");
 press(2,10);if(adjust!=133) $fatal(1,"plus");press(1,10);if(adjust!=128) $fatal(1,"minus");
 repeat(30) press(2,10);if(adjust!=255) $fatal(1,"upper");
 repeat(60) press(1,10);if(adjust!=0) $fatal(1,"lower");
 press(3,110);if(adjust!=128 || !rearm) $fatal(1,"rearm");
 press(3,110);if(rearm) $fatal(1,"second rearm");
 press(2,110);press(1,210);if(adjust!=128 || rearm) $fatal(1,"single long press switched mode");
 keys=0;repeat(18) @(negedge clk);keys=2;repeat(18) @(negedge clk);keys=3;repeat(12) @(negedge clk);
 if(adjust!=128 || rearm) $fatal(1,"partial chord release");
 keys=1;@(negedge clk);keys=3;repeat(12) @(negedge clk);
 if(adjust!=128) $fatal(1,"bounce");
 $display("PASS standalone keys: ADJ +/-5, saturation, rearm/reset offset, no mode exit, chord and bounce");$finish;
 end
endmodule
""".replace('@TICK@',chr(96))
simulate('plate_standalone_keys',tb,['src/plate_key_control.v'])
