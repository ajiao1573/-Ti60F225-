`timescale 1ns/1ps
module tb_early;
reg clk=0,rst_n=0,start=0,in_we=0,go=0;wire out_we,done,busy;wire [9:0] nout;integer errors=0,t;
always #5 clk=~clk;
point_gap_filter dut(.clk(clk),.rst_n(rst_n),.start(start),.in_we(in_we),.in_addr(11'd0),.in_data(64'd0),.go(go),.n_in(10'd1),.out_we(out_we),.out_addr(),.out_data(),.n_out(nout),.done(done),.busy(busy));
always @(posedge clk) if(out_we) errors=errors+1;
initial begin repeat(3)@(negedge clk);rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;in_we=1;@(negedge clk);in_we=0;repeat(725)@(negedge clk);go=1;@(negedge clk);go=0;t=0;while(!done&&t<20) begin @(negedge clk);t=t+1;end if(!done||nout!=0||errors!=0)$display("TEST:FAIL early data not rejected");else $display("TEST:PASS early data rejected");$finish;end
endmodule
