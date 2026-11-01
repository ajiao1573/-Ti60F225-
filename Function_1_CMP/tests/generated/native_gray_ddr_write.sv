`timescale 1ns/1ps
// Behavioral FIFOs are test doubles for the generated Efinix IP. They check
// over/underflow and retain the actual 8-to-128-bit packing convention.
module W0_FIFO_8(input wr_clk_i,wr_en_i,input [7:0] wdata,input a_rst_i,
 input rd_clk_i,rd_en_i,output [127:0] rdata,output prog_empty_o,empty_o,output [9:0] rd_datacount_o);
 reg [7:0] mem[0:8191];integer wp=0,rp=0,j;
 assign empty_o=(wp-rp)<16;assign prog_empty_o=(wp-rp)<=2032;
 assign rd_datacount_o=(wp-rp)/16;
 genvar b;generate for(b=0;b<16;b=b+1) begin
  assign rdata[b*8+:8]=mem[(rp+b)%8192];
 end endgenerate
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>=8192) $fatal(1,"write fifo overflow");mem[wp%8192]=wdata;wp=wp+1;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i) begin
   if(wp-rp<16) $fatal(1,"write fifo underflow");rp<=rp+16;
  end
endmodule
module R0_FIFO_8(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,
 output prog_full_o,input rd_clk_i,rd_en_i,output [7:0] rdata,output empty_o,almost_empty_o);
 reg [7:0] mem[0:8191];integer wp=0,rp=0,j;
 assign prog_full_o=wp-rp>=4096;assign empty_o=wp==rp;assign almost_empty_o=wp-rp<16;
 assign rdata=mem[rp%8192];
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>8176) $fatal(1,"display fifo overflow");
   for(j=0;j<16;j=j+1) mem[(wp+j)%8192]=wdata[8*j+:8];wp=wp+16;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i && !empty_o) rp<=rp+1;
endmodule


`include "src/native_gray_capture.v"
`include "src/camera_full_view.v"
module tb;
reg ac=0,pc=0;always #2.604 ac=~ac;always #5.952381 pc=~pc;
reg reset=1,iv=0,fr=0;reg[23:0]rgb=0;reg freeze=0;
wire take,ns,nl,ready,rv,rs,re;wire[7:0]gray;wire[23:0]small_rgb;
native_gray_capture cap(.clk(pc),.rst_n(!reset),.enable(ready),.in_frame(fr),.in_valid(iv),.in_rgb(rgb),.take(take),.start(ns),.last(nl),.gray(gray));
camera_full_view #(.HEIGHT(477),.IMAGE_H(477),.FIFO_BITS(5)) resize_branch(
.clk(pc),.rst_n(!reset),.enable(ready),.in_frame(fr),.in_valid(iv),.in_rgb(rgb),.out_valid(rv),.out_sop(rs),.out_eop(re),.out_rgb(small_rgb));
wire[31:0]addr;wire[7:0]len;wire av,wv,wl;wire[127:0]data;reg bv=0;wire frozen;
split_frame_ctrl #(.NATIVE_GRAY(1),.SINGLE_VIEW(1),.EDGE_LINES(1080),.GRAY_LINES(0),.HISTORY_ENABLE(1),.COMPACT_BURSTS(1),.C_BUF_SIZE(23)) dut(
.axi_clk(ac),.axi_reset(reset),.axi_awaddr(addr),.axi_awlen(len),.axi_awvalid(av),.axi_awready(1'b1),
.axi_wdata(data),.axi_wvalid(wv),.axi_wlast(wl),.axi_wready(1'b1),.axi_bvalid(bv),.axi_bresp(2'd0),
.axi_arready(1'b0),.axi_rvalid(1'b0),.axi_rlast(1'b0),.axi_rdata(128'd0),.axi_rresp(2'd0),
.wframe_pclk(pc),.wframe_sof(rv&&rs),.wframe_eof(rv&&re),.capture_ready(ready),
.edge_data_en(take),.edge_data(gray),.gray_data_en(1'b0),.gray_data(8'd0),
.freeze_requested(freeze),.history_requested(1'b0),.compare_requested(1'b0),.frozen(frozen),
.replay_requested(3'd0),.left_requested(3'd0),.right_requested(3'd0),.overlay_requested(1'b0),
.rframe_pclk(pc),.rframe_vsync(1'b0),.rframe_data_en(1'b0));
integer row=0,beat=0,b,xx,yy,n=0,small_n=0,starts=0;
function[7:0] value;input integer x,y;begin value=(x*7+y*11)&255;end endfunction
always @(posedge pc)if(!reset)begin
 if(take)n=n+1;if(rv)small_n=small_n+1;if(rv&&rs)starts=starts+1;
end
always @(posedge ac)begin
 bv<=0;
 if(!reset)begin
  if(av)begin if(addr!=(row<<11)||len!=127)$fatal(1,"native address/stride row%0d %h len%0d",row,addr,len);beat<=0;end
  if(wv)begin
   for(b=0;b<16;b=b+1)if(data[b*8+:8] !== (beat<120 ? value(beat*16+b,row):8'd0))$fatal(1,"native pixel row%0d beat%0d byte%0d",row,beat,b);
   if(wl)begin row<=row+1;bv<=1;end else beat<=beat+1;
  end
 end
end
initial begin
 repeat(8)@(negedge pc);reset=0;wait(ready);repeat(8)@(negedge pc);
 fr=1;
 for(yy=0;yy<1080;yy=yy+1)begin
  for(xx=0;xx<1920;xx=xx+1)begin iv=1;rgb={3{value(xx,yy)}};@(negedge pc);if(yy==30)freeze=1;end
  iv=0;repeat(580)@(negedge pc);
 end
 fr=0;iv=0;wait(frozen);repeat(30)@(negedge pc);
 if(n!=2073600||small_n!=404496||starts!=1||row!=1080||dut.completed_generation!=1||ready)$fatal(1,"native/OCR admission/commit %0d %0d %0d rows%0d",n,small_n,starts,row);
 freeze=0;wait(ready);
 $display("PASS native1080 write:2073600 original pixels,1080 padded bursts,OCR404496 pixels/same SOP,midframe freeze completes one generation,release recovers");$finish;
end
initial begin #90000000;$fatal(1,"native write timeout rows%0d",row);end
endmodule
