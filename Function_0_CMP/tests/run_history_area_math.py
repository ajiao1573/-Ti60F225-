"""Visible-pixel diagnostics (retained filename for existing regression runners)."""
from pathlib import Path
from run_canny import simulate

fifos = Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
tb = r'''
`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,vs=0,de=0,hist=1;
 reg [11:0] x=1008,y=64;
 wire [9:0] last_count,total_count;wire [7:0] osd;wire active;
  split_frame_ctrl #(.HISTORY_ENABLE(1),.HISTORY_COMPARE_NATIVE(1)) dut(
   .axi_clk(clk),.axi_reset(reset),.wframe_pclk(clk),.wframe_sof(1'b0),.wframe_eof(1'b0),
  .gray_data_en(1'b0),.edge_data_en(1'b0),.rgb_data_en(1'b0),.left_rgb_data_en(1'b0),
  .axi_awready(1'b0),.axi_wready(1'b0),.axi_bvalid(1'b0),.axi_arready(1'b0),.axi_rvalid(1'b0),
  .rframe_pclk(clk),.rframe_vsync(vs),.rframe_data_en(de),.rframe_left(1'b0),
  .overlay_requested(1'b0),.history_requested(hist),.compare_requested(1'b1),
  .replay_requested(3'd0),.left_requested(3'd0),.right_requested(3'd1),
  .history_underflow_frame(last_count),.history_underflow_total(total_count));
 threshold_osd #(.X_START(1008),.Y_START(64),.LABEL_KIND(4)) label(
  .x_pos(x),.y_pos(y),.threshold(10'd7),.fps(10'd42),.pixel_in(8'd0),.pixel_out(osd),.osd_active(active));
 function [34:0] glyph;
  input [7:0] c;
  begin case(c)
   "U":glyph=35'b10001100011000110001100011000101110;
   "N":glyph=35'b10001110011100110101101011000110001;
   "D":glyph=35'b11110100011000110001100011000111110;
   "T":glyph=35'b11111001000010000100001000010000100;
   "O":glyph=35'b01110100011000110001100011000101110;
   "0":glyph=35'b01110100011001110101110011000101110;
   "2":glyph=35'b01110100010000100010001000100011111;
   "4":glyph=35'b00010001100101010010111110001000010;
   "7":glyph={5'd31,5'd1,5'd2,5'd4,5'd8,5'd8,5'd8};
   ":":glyph=35'b00000001000010000000001000010000000;
   default:glyph=0;
  endcase end
 endfunction
 task boundary;begin
  de=0;vs=1;repeat(8) @(negedge clk);vs=0;repeat(60) @(negedge clk);
 end endtask
 integer xx,yy,row,col,dy,line;
 reg [63:0] text;reg [34:0] bits;reg ink;
 initial begin
  repeat(8) @(negedge clk);reset=0;
  for(yy=0;yy<46;yy=yy+1) for(xx=0;xx<128;xx=xx+1) begin
   x=1008+xx;y=64+yy;line=yy>=24;dy=yy-(line ? 28 : 4);
   row=dy/2;col=(xx%16)/2;text=line ? "TOT:0042" : "UND:0007";
   bits=glyph(text[63-(xx/16)*8-:8]);
   ink=dy>=0 && dy<14 && col<5 && bits[34-row*5-col];#1;
   if(!active || osd!==(ink ? 8'hff : 8'd0)) $fatal(1,"UND/TOT raster x=%0d y=%0d",xx,yy);
  end
  boundary;
  if(!dut.display_history) $fatal(1,"history mode latch");
  // Empty FIFO plus invisible pixels must not count.
  repeat(12) @(negedge clk);if(total_count!=0) $fatal(1,"blanking counted");
  de=1;repeat(11) @(negedge clk);de=0;
  if(total_count!=11) $fatal(1,"visible missing count");
  boundary;if(last_count!=11) $fatal(1,"frame count publication");
  de=1;repeat(1100) @(negedge clk);de=0;
  boundary;if(last_count!=999 || total_count!=999) $fatal(1,"counter saturation");
  boundary;if(last_count!=0 || total_count!=999) $fatal(1,"frame clearing and sticky total");
  reset=1;repeat(8) @(negedge clk);reset=0;repeat(8) @(negedge clk);
  if(last_count!=0 || total_count!=0) $fatal(1,"counter reset");
  $display("PASS history diagnostics: 5888 UND/TOT OSD pixels, visible-only counts, frame publication, saturation, reset");$finish;
 end
endmodule
'''
simulate('history_area_math', fifos+tb, ['src/axi/split_frame_ctrl.v', 'src/threshold_osd.v'])
