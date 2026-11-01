"""Actual edge engine and geometry busy gate reject whole overlapping frames."""
from pathlib import Path
from run_canny import simulate
top=Path('example_top.v').read_text(encoding='utf-8')
assert '.capture_ready(canny_capture_ready && !shape_busy)' in top
tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,v=0,s=0,e=0;reg [7:0] data=0;
 wire start,engine_busy,ev,es,ee,shape_busy,done;wire [7:0] edge_data;wire [1:0] shape;
 integer accepted=0,published=0,xx,yy,t;
 canny_frame #(.WIDTH(48),.HEIGHT(40),.RUNTIME_MODES(1)) engine(
  .clk(clk),.rst_n(rst),.capture_ready(!shape_busy),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(data),
  .algorithm(2'd0),.threshold(10'd62),.frame_start(start),.busy(engine_busy),
  .edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(edge_data));
 shape_detect #(.WIDTH(48),.HEIGHT(40)) detector(clk,rst,1'b1,ev,es,ee,edge_data!=0,shape,done,shape_busy);
 always @(posedge clk) begin
  if(start) accepted=accepted+1;
  if(done) begin published=published+1;if(shape!=2) $fatal(1,"accepted-frame rectangle recognition");end
 end
 task frame;
  begin
   for(yy=0;yy<40;yy=yy+1) for(xx=0;xx<48;xx=xx+1) begin
    @(negedge clk);v=1;s=xx==0 && yy==0;e=xx==47 && yy==39;
    data=xx>=8 && xx<40 && yy>=8 && yy<32 ? 220 : 20;
   end
   @(negedge clk);v=0;s=0;e=0;
  end
 endtask
 initial begin
  repeat(5) @(negedge clk);rst=1;frame;
  t=0;while(engine_busy && t<5000) begin @(negedge clk);t=t+1;end
  if(engine_busy || !shape_busy) $fatal(1,"analysis busy did not cover post-edge interval");
  frame;if(accepted!=1) $fatal(1,"overlapping camera frame was accepted");
  t=0;while(published<1 && t<200000) begin @(negedge clk);t=t+1;end
  if(published!=1 || shape_busy) $fatal(1,"analysis completion/busy release");
  frame;t=0;while(published<2 && t<200000) begin @(negedge clk);t=t+1;end
  if(accepted!=2 || published!=2 || shape_busy) $fatal(1,"next complete frame did not recover");
  $display("PASS camera/geometry busy gate: completed frame accepted, overlapping frame wholly skipped, no contour overwrite, result publication and following-frame recovery");$finish;
 end
endmodule
'''
simulate('shape_busy',tb,['src/shape_detect.v']+[str(p) for p in Path('src/canny').glob('*.v')])
