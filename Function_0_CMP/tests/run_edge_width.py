"""Check display dilation against an independent 2x2 neighborhood oracle."""
from run_canny import simulate

tb=r'''`timescale 1ns/1ps
module tb;
localparam W=848,H=8,F=4,N=W*H;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,edge_in=0;reg [11:0] x=0,y=0;wire wide;
edge_display_width2 #(.WIDTH(W)) dut(clk,rst,valid,x,y,edge_in,wide);
reg pixels[0:N-1];reg expected;integer f,i,j,xx,yy,checked=0;
initial begin
 repeat(4) @(negedge clk);rst=1;
 for(f=0;f<F;f=f+1) begin
  for(i=0;i<N;i=i+1) pixels[i]=0;
  // Vertical/horizontal lines, isolated pixels, and right/bottom boundary.
  if(f==0) begin
   for(i=0;i<H;i=i+1) pixels[i*W+20]=1;
   for(i=100;i<180;i=i+1) pixels[2*W+i]=1;
   pixels[4*W+333]=1;pixels[W-1]=1;pixels[N-1]=1;
  end
  // Empty next frame must not retain last frame's lines.
  if(f==2) for(i=0;i<N;i=i+1) pixels[i]=((i*37+i/11)%101)<7;
  if(f==3) begin
   rst=0;repeat(3) @(negedge clk);rst=1;
   pixels[0]=1;pixels[W]=1;pixels[W-1]=1;
  end
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<W;xx=xx+1) begin
    @(negedge clk);valid=1;x=xx;y=yy;edge_in=pixels[yy*W+xx];
    expected=pixels[yy*W+xx];
    if(xx>0) expected=expected | pixels[yy*W+xx-1];
    if(yy>0) expected=expected | pixels[(yy-1)*W+xx];
    if(xx>0 && yy>0) expected=expected | pixels[(yy-1)*W+xx-1];
    #1;if(wide!==expected) $fatal(1,"dilation mismatch f=%0d y=%0d x=%0d",f,yy,xx);
    checked=checked+1;
    // Valid bubbles must not shift the stored line or leak a visible edge.
    if(xx%37==0) begin
     @(negedge clk);valid=0;#1;if(wide!==0) $fatal(1,"blanking leak");
    end
   end
   @(negedge clk);valid=0;repeat(8) @(negedge clk);
  end
 end
 $display("PASS display width2: %0d pixels, horizontal/vertical lines, isolated points, boundaries, blanking gaps, next-frame clearing, reset",checked);$finish;
end
endmodule
'''
simulate('edge_width2',tb,['src/edge_display_width2.v'])
