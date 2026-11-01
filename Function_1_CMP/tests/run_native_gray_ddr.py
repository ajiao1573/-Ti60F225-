"""Native1080p DDR: byte-exact readback, plus full source->DDR write/freeze."""
from pathlib import Path
import ast,sys
from run_canny import simulate
source=Path('tests/run_single_gray_ddr.py').read_text()
tb=next(n.value.value for n in ast.parse(source).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
fifos=Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
tb=tb.replace('.SINGLE_VIEW(1),','.SINGLE_VIEW(1),.NATIVE_GRAY(1),').replace('.EDGE_LINES(477)','.EDGE_LINES(1080)').replace('.GRAY_LINES(238)','.GRAY_LINES(0)')
tb=tb.replace('alen!=63','alen!=127').replace('beat<53','beat<120').replace('tokens%848','tokens%1920').replace('tokens/848','tokens/1920').replace('848*477','1920*1080').replace('rows!=477','rows!=1080').replace('#15000000','#90000000')
tb=tb.replace('477 edge-plane rows,53 effective beats/row,404496 exact gray bytes','1080 native rows,120 effective beats/row,2073600 exact gray bytes')
if '--write-only' not in sys.argv: simulate('native_gray_ddr_read',fifos+tb,['src/axi/split_frame_ctrl.v'],timeout=300)
tb=r'''
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
'''
simulate('native_gray_ddr_write',fifos+tb,['src/axi/split_frame_ctrl.v'],timeout=300)
