`timescale 1ns/1ps
module tb_clear_restart;
reg clk=0,rst=0,clear=0,active=1,start=0,sbusy=0,nbusy=0,sdone=0,ndone=0,ready=1;reg [9:0] count=0;wire ss,ns,pending;wire [2:0] st;wire [9:0] saved;wire [11:0] id;integer err=0;
always #5 clk=~clk;
live_fsm2 dut(clk,rst,clear,active,start,sbusy,nbusy,sdone,ndone,ready,count,5'd0,ss,ns,pending,st,saved,id);
task txn(input [9:0] n,input [11:0] wanted_id);
begin
 @(negedge clk);start=1;@(negedge clk);start=0;repeat(3)@(negedge clk);if(st!=1 || pending || ns)err=err+1;
 sbusy=1;sdone=0;repeat(3)@(negedge clk);count=n;sbusy=0;sdone=1;repeat(3)@(negedge clk);
 if(saved!==n || st!=5 || pending || id!==wanted_id)err=err+1;
 nbusy=1;ndone=0;repeat(3)@(negedge clk);nbusy=0;ndone=1;@(negedge clk);if(!pending)err=err+1;repeat(3)@(negedge clk);
end endtask
initial begin repeat(3)@(negedge clk);rst=1;txn(389,1);@(negedge clk);clear=1;@(negedge clk);clear=0;txn(400,2);if(err==0)$display("TEST:PASS clear and different next input");else $display("FAIL errors=%0d",err);$finish;end
endmodule
