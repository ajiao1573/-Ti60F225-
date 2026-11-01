`timescale 1ns/1ps
module tb;
 localparam W=1920,H=1080,N=W*H,F=1;
 reg clk=0;always #5 clk=~clk;reg rst=0,en=1,rearm=0,v=0,s=0,e=0,rej=0;reg[7:0] edge_data=0;
 wire cv;wire[10:0] cx,cw;wire[10:0] cy,ch;wire[1:0] diag;wire[31:0] fid,cf;
 reg[10:0] bx=0,bw=0;reg[10:0] by=0,bh=0;
 plate_locator #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,en,rearm,v,s,e,edge_data,rej,bx,bw,by,bh,cv,cx,cw,cy,ch,diag,fid,cf);
 reg[7:0] image[0:F*N-1];integer valids[0:F-1],xs[0:F-1],ys[0:F-1],ws[0:F-1],hs[0:F-1],acts[0:F-1];
 integer f,i,done=0,expected_frame=0;reg[3:0] previous=0;
 always @(negedge clk) if(rst) begin
  if(dut.state==0 && previous==8)begin
   if(cv!==valids[done][0])$fatal(1,"native_locator_bottom candidate f%0d got%0d want%0d diag%0d",done,cv,valids[done],diag);
   if(cv && (cx!=xs[done] || cy!=ys[done] || cw!=ws[done] || ch!=hs[done]))
    $fatal(1,"native_locator_bottom box f%0d got%0d,%0d %0dx%0d want%0d,%0d %0dx%0d",done,cx,cy,cw,ch,xs[done],ys[done],ws[done],hs[done]);
   if(cf!=done+1)$fatal(1,"native_locator_bottom frame tag f%0d got%0d",done,cf);
   done=done+1;
  end
  previous=dut.state;
 end
 initial begin
  $readmemh("tests/generated/native_locator_bottom_edges.hex",image);valids[0]=0;xs[0]=0;ys[0]=0;ws[0]=0;hs[0]=0;acts[0]=0;
  repeat(8)@(negedge clk);rst=1;
  for(f=0;f<F;f=f+1)begin
   if(acts[f]==1)begin
    wait(done==f);bx=cx;by=cy;bw=cw;bh=ch;rej=1;@(negedge clk);rej=0;
   end
   if(acts[f]==2)begin
    wait(done==f);rearm=1;@(negedge clk);rearm=0;
    if(cv)$fatal(1,"rearm retained candidate");
   end
   for(i=0;i<N;i=i+1)begin
    v=1;s=i==0;e=i==N-1;edge_data=image[f*N+i];@(negedge clk);
    if(0 && (i%31==30 || i%W==W-1))begin v=0;s=0;e=0;repeat(3)@(negedge clk);end
   end
   v=0;s=0;e=0;
   // No frame-end wait for normal cases: maps must be analysed during the
   // following input frame, while the other map bank is being filled.
  end
  wait(done==F);repeat(3)@(negedge clk);
  en=0;@(negedge clk);if(cv)$fatal(1,"disable retained candidate");
  en=1;repeat(3)@(negedge clk);
  $display("PASS native_locator_bottom: 1 frames, exact candidate bounds/frame tags, gaps/banks/rearm/reject/enable");$finish;
 end
 initial begin repeat(N*F*5+100000)@(posedge clk);$fatal(1,"native_locator_bottom timeout done%0d state%0d",done,dut.state);end
endmodule
