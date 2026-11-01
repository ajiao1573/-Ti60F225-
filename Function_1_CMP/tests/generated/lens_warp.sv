`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0;reg [10:0] x,y,w,h;
wire rd,wr,done,success;wire [14:0] ra,wa;wire [7:0] wd;reg [7:0] data;
reg [7:0] source[0:24575],expected[0:24575];integer n,cycles;
always @(posedge clk)if(rd)data<=source[ra];
lens_roi_warp dut(.clk(clk),.rst_n(rst),.start(start),.roi_x(x),.roi_y(y),.roi_width(w),.roi_height(h),
 .read_enable(rd),.read_address(ra),.read_data(data),.write_enable(wr),.write_address(wa),.write_data(wd),.done(done),.success(success));
task run_case(input integer xx,yy,ww,hh);begin
 @(negedge clk);x=xx;y=yy;w=ww;h=hh;start=1;n=0;cycles=0;
 @(negedge clk);start=0;
 while(!done)begin
  if(wr)begin
   if(wa!==n || wd!==expected[n])$fatal(1,"pixel %d address %d got %d expected %d",n,wa,wd,expected[n]);n=n+1;
  end
  cycles=cycles+1;@(negedge clk);
 end
 if(!success || n!=24576)$fatal(1,"incomplete warp %d",n);
 $display("warp box %d,%d,%d,%d cycles %d",xx,yy,ww,hh,cycles);
end endtask
initial begin
 $readmemh("tests/generated/lens_source.hex",source);#12;rst=1;
 $readmemh("tests/generated/lens_expected0.hex",expected);run_case(640,420,640,192);
$readmemh("tests/generated/lens_expected1.hex",expected);run_case(32,32,640,200);
$readmemh("tests/generated/lens_expected2.hex",expected);run_case(1248,840,640,200);
$readmemh("tests/generated/lens_expected3.hex",expected);run_case(1650,1040,128,32);
 @(negedge clk);start=1;x=1900;y=0;w=640;h=96;@(negedge clk);start=0;
 wait(done);#1;if(success)$fatal(1,"invalid ROI accepted");
 $display("PASS lens warp:4 native ROIs,98304 exact bilinear pixels,repeated start,bounds");$finish;
end
initial begin #40000000;$fatal(1,"timeout");end
endmodule