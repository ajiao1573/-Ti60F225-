`timescale 1ns/1ps
module tb_gap_filter;
reg clk=0,rst_n=0,start=0,in_we=0,go=0;reg [10:0] in_addr=0;reg [63:0] in_data=0;reg [9:0] n=0;wire out_we,done,busy;wire [10:0] out_addr;wire [63:0] out_data;wire [9:0] n_out;
reg [63:0] src[0:943],expected[0:943];reg [1023:0] fsrc,fexp;integer i,seen,errs,timeout,expected_n;
always #5 clk=~clk;
point_gap_filter dut(clk,rst_n,start,in_we,in_addr,in_data,go,n,out_we,out_addr,out_data,n_out,done,busy);
always @(posedge clk) if(out_we) begin if(out_addr !== seen*2 || out_data !== expected[seen*2]) begin if(errs<3)$display("FAIL point %0d addr %0d data %h expected %h",seen,out_addr,out_data,expected[seen*2]);errs=errs+1;end seen=seen+1;end
initial begin seen=0;errs=0;timeout=0;if(!$value$plusargs("SRC=%s",fsrc)||!$value$plusargs("EXP=%s",fexp)||!$value$plusargs("N=%d",n)||!$value$plusargs("NOUT=%d",expected_n))$fatal(1,"missing args");$readmemh(fsrc,src);$readmemh(fexp,expected);repeat(3)@(negedge clk);rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;repeat(725) @(negedge clk);for(i=0;i<n;i=i+1)begin in_we=1;in_addr=2*i;in_data=src[2*i];@(negedge clk);end in_we=0;go=1;@(negedge clk);go=0;while(!done && timeout<10000)begin timeout=timeout+1;@(negedge clk);end if(!done||n_out!=expected_n||seen!=expected_n)errs=errs+1;if(errs==0)$display("TEST:PASS input=%0d output=%0d cycles=%0d",n,n_out,timeout);else $display("TEST:FAIL errors=%0d nout=%0d seen=%0d",errs,n_out,seen);$finish;end
endmodule
