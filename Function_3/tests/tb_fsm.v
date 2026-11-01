`timescale 1ns/1ps
module tb_fsm;
reg clk=0,rst=0,clear=0,active=1,start=0,sbusy=0,nbusy=0,sdone=0,ndone=0,ready=1;wire ss,ns,pending;wire [2:0] st;integer errors=0;
always #5 clk=~clk;
live_fsm dut(clk,rst,clear,active,start,sbusy,nbusy,sdone,ndone,ready,10'd100,5'd0,ss,ns,pending,st);
task transaction;
begin
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(3) @(negedge clk);if(ns || pending || st!=1) begin $display("FAIL stale scan completion");errors=errors+1;end
 sbusy=1;sdone=0;repeat(3) @(negedge clk);if(st!=4) begin $display("FAIL no scan busy");errors=errors+1;end
 sbusy=0;sdone=1;@(negedge clk);repeat(3) @(negedge clk);if(pending || st!=5) begin $display("FAIL stale core completion");errors=errors+1;end
 nbusy=1;ndone=0;repeat(3) @(negedge clk);if(st!=2) errors=errors+1;
 nbusy=0;ndone=1;@(negedge clk);if(!pending) begin $display("FAIL completion");errors=errors+1;end
 repeat(3) @(negedge clk);if(st!=0) errors=errors+1;
end endtask
initial begin repeat(3) @(negedge clk);rst=1;transaction();transaction();if(errors==0) $display("TEST:PASS two sequential transactions with sticky done");else $display("FAIL errors=%0d",errors);$finish;end
endmodule
