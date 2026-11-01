`timescale 1ns/1ps
module tb_gap_fsm;
reg clk=0,rst=0,clear=0,active=1,start=0,sbusy=0,nbusy=0,sdone=0,ndone=0,fbusy=0,fdone=0,ready=1;reg [9:0] scount=0,fcount=0;wire ss,ns,fg,pending;wire [2:0] st;wire [9:0] saved;integer errors=0;
always #5 clk=~clk;
gap_fsm dut(clk,rst,clear,active,start,sbusy,nbusy,sdone,ndone,fbusy,fdone,ready,scount,fcount,5'd0,ss,ns,fg,pending,st,saved);
task txn(input [9:0] raw_n,input [9:0] kept_n); begin
 @(negedge clk);start=1;@(negedge clk);start=0;repeat(2)@(negedge clk);if(st!=1 || fg || ns || pending)errors=errors+1;
 sbusy=1;sdone=0;repeat(2)@(negedge clk);sbusy=0;sdone=1;scount=raw_n;@(negedge clk);if(!fg || saved!=raw_n)errors=errors+1;repeat(2)@(negedge clk);if(st!=6||ns||pending)errors=errors+1;
 fbusy=1;fdone=0;repeat(2)@(negedge clk);fbusy=0;fdone=1;fcount=kept_n;@(negedge clk);if(!ns||saved!=kept_n)errors=errors+1;repeat(2)@(negedge clk);if(st!=5||pending)errors=errors+1;
 nbusy=1;ndone=0;repeat(2)@(negedge clk);nbusy=0;ndone=1;@(negedge clk);if(!pending)errors=errors+1;repeat(3)@(negedge clk);
end endtask
initial begin repeat(3)@(negedge clk);rst=1;txn(318,245);@(negedge clk);clear=1;@(negedge clk);clear=0;txn(389,389);if(errors==0)$display("TEST:PASS two transactions clear and sticky completions");else $display("TEST:FAIL errors=%0d",errors);$finish;end
endmodule
