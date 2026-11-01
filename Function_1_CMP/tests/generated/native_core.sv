
`include "src/native_gray_capture.v"
module tb;
reg clk=0;always #5.952381 clk=~clk;
reg rst=0,fr=0,v=0;reg[23:0]rgb=0;
wire take,sop,eop;wire[7:0]gray;wire[10:0]x,y;wire busy,hold,start,done,pv;wire[7:0]pd;wire[31:0]fid;
native_gray_capture cap(.clk(clk),.rst_n(rst),.enable(!busy&&!hold),.in_frame(fr),.in_valid(v),.in_rgb(rgb),.take(take),.start(sop),.last(eop),.gray(gray),.source_x(x),.source_y(y));
autoplate_core #(.WIDTH(1920),.HEIGHT(1080),.TEMPORAL_HISTORY(0)) core(
.clk(clk),.rst_n(rst),.run_enable(1'b1),.rearm(1'b0),.edge_threshold(10'd27),.char_adjust(8'd128),
.in_valid(take),.in_sop(sop),.in_eop(eop),.in_gray(gray),.in_x(x),.in_y(y),
.capture_ready(1'b1),.snapshot_ready(1'b1),.pixel_clk(clk),.pixel_rst_n(rst),.pixel_vsync(1'b0),
.frame_start(start),.frame_done(done),.busy(busy),.capture_hold(hold),.preview_valid(pv),.preview_data(pd),.captured_frame_id(fid));
integer captures=0,previews=0,edges=0,frames=0,nonzero=0,bottom_edges=0,xx,yy,f;
always @(posedge clk)if(rst)begin
 if(take)begin
  if(x!==captures%1920||y!==(captures/1920)%1080)$fatal(1,"native coord truncation %0d,%0d",x,y);
  captures=captures+1;
 end
 if(pv)previews=previews+1;
 if(core.ev)begin
  if(core.ed!=0)begin nonzero=nonzero+1;if(edges/1920>=1024)bottom_edges=bottom_edges+1;end
  edges=edges+1;
 end
 if(done)begin
  if(edges!=2073600)$fatal(1,"native frame did not process2073600 pixels %0d",edges);
  if(frames==0&&nonzero!=0)$fatal(1,"blank frame false edges");
  if(frames==1&&(nonzero<1000||bottom_edges<50))$fatal(1,"native lower rows missing edges %0d/%0d",nonzero,bottom_edges);
  frames=frames+1;edges=0;nonzero=0;
  $display("native frame%0d complete",frames);
 end
end
initial begin
 repeat(8)@(negedge clk);rst=1;
 for(f=0;f<2;f=f+1)begin
  fr=1;
  for(yy=0;yy<1080;yy=yy+1)for(xx=0;xx<2500;xx=xx+1)begin
   v=xx<1920;rgb=f==0 ? 24'h808080:xx<1700 ? 24'h282828:24'hc8c8c8;@(negedge clk);
  end
  v=0;fr=0;repeat(100000)@(negedge clk);
 end
 wait(!busy);repeat(1000)@(negedge clk);
 if(frames!=2||captures!=4147200||previews!=4147200||hold)$fatal(1,"native source/core budget %0d/%0d/%0d",frames,captures,previews);
 $display("PASS native1080 recognition: actual1920x1080 Canny+locator,2x2073600 source/preview/edge pixels at84MHz/30fps timing,lower rows beyond1023 retained,no resize stage");$finish;
end
initial begin #100000000;$fatal(1,"native recognition timeout frames%0d",frames);end
endmodule
