from run_canny import simulate
simulate('capture_recovery',r"""`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=0,v=0,s=0,e=0;wire hold;
plate_segmenter #(.ENABLE_NZ_OCR(1),.X_START(8),.Y_START(8)) dut(.clk(clk),.rst_n(rst),.enable(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_x(11'd0),.in_y(10'd0),.in_gray(8'd200),.adjust(8'd128),.accept_frame(1'b1),.snapshot_ready(1'b0),.capture_hold(hold),.pixel_clk(clk),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0));
initial begin
repeat(4) @(negedge clk);rst=1;wait(dut.state==1);
@(negedge clk);v=1;s=1;@(negedge clk);s=0;v=0;
repeat(5) @(negedge clk);if(!hold || dut.state!=2) $fatal(1,"not capturing");
v=1;e=1;@(negedge clk);v=0;e=0;
repeat(40) @(negedge clk);if(hold || dut.state!=1) $fatal(1,"stuck after source end");
v=1;s=1;@(negedge clk);v=0;s=0;
if(!hold || dut.state!=2) $fatal(1,"failed next frame");
$display("PASS missing ROI sample: source EOF releases capture and next SOP is accepted");$finish;
end
endmodule
""",['src/plate_segmenter.v'])
