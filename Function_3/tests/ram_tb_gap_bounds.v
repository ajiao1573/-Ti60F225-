`timescale 1ns/1ps
module tb_gap_bounds;
reg clk=0,rst_n=0,start=0,in_we=0,go=0;reg [10:0] in_addr=0;reg [63:0] in_data=0;reg [9:0] n=0;wire out_we,done,busy;wire [10:0] out_addr;wire [63:0] out_data;wire [9:0] n_out;integer seen=0,errors=0,t,i;
always #5 clk=~clk;point_gap_filter dut(clk,rst_n,start,in_we,in_addr,in_data,go,n,out_we,out_addr,out_data,n_out,done,busy);
always @(posedge clk) if(out_we) begin if(out_addr!==seen*2) errors=errors+1;seen=seen+1;end
task run(input integer nleft,input integer nright,input integer yright,input integer expect_n);
 begin @(negedge clk);start=1;@(negedge clk);start=0;repeat(725) @(negedge clk);seen=0;n=nleft+nright;
  for(i=0;i<n;i=i+1)begin in_we=1;in_addr=2*i;in_data=(((i<nleft)?100:yright)<<10)|i;@(negedge clk);end
  in_we=0;go=1;@(negedge clk);go=0;t=0;while(!done&&t<10000)begin @(negedge clk);t=t+1;end
  if(!done||n_out!=expect_n||seen!=expect_n)begin $display("FAIL left=%0d right=%0d y=%0d output=%0d seen=%0d",nleft,nright,yright,n_out,seen);errors=errors+1;end
 end
endtask
initial begin repeat(3)@(negedge clk);rst_n=1;run(24,24,159,48);run(24,24,160,24);run(24,23,160,47);run(30,24,160,30);run(24,30,160,30);if(errors==0)$display("TEST:PASS gap threshold, group size, majority, repeated transactions");else $display("TEST:FAIL errors=%0d",errors);$finish;end
endmodule
