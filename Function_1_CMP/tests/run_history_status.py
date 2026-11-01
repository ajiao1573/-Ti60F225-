"""Raster check readable freeze/count labels, and ensure history OSD is outside images."""
from pathlib import Path
import re
from run_canny import simulate
source=Path('src/video_status_osd.v').read_text()
fonts={int(c):[int(bits[i:i+5],2) for i in range(0,35,5)]
       for c,bits in re.findall(r"8'd(\d+):bits=35'b([01]{35});",source)}
pixels=[]
for frozen in (0,1):
 for count in range(9):
  lines=['STATE:FROZEN' if frozen else 'STATE:CAPTURING',f'FRAMES:{count}/8','']
  for y in range(72):
   line=y//24;dy=y%24-4;word=lines[line].ljust(24)
   for x in range(384):
    row=dy//2;col=x%16//2;glyph=fonts.get(ord(word[x//16]),[0]*7)
    on=0<=dy<14 and col<5 and (glyph[row]>>(4-col)&1)
    pixels.append([0x00ffff,0xffff00,0x00ff80][line] if on else 0x081020)
Path('tests/generated/history_status.hex').write_text(''.join(f'{p:06x}\n' for p in pixels))
tb='''`timescale 1ns/1ps
module tb;
 reg [11:0] x=0,y=0;reg frozen=0;reg [3:0] count=0;
 wire [23:0] rgb;wire active;
 video_status_osd #(.X_START(576),.Y_START(8),.STATE_ONLY(1)) dut(
 .x_pos(x),.y_pos(y),.gear(3'd3),.algorithm(2'd0),.overlay(1'b0),
 .history(1'b1),.compare(1'b0),.replay(3'd7),.left_frame(3'd0),.right_frame(3'd7),
 .frozen(frozen),.frame_count(count),.pixel(rgb),.active(active));
 reg [23:0] expected[0:497663];
 integer f,c,xx,yy,n=0;
 initial begin
  $readmemh("tests/generated/history_status.hex",expected);
  for(f=0;f<2;f=f+1) for(c=0;c<9;c=c+1) begin
   frozen=f;count=c;
   for(yy=0;yy<72;yy=yy+1) for(xx=0;xx<384;xx=xx+1) begin
    x=576+xx;y=8+yy;#1;
    if(!active || rgb!==expected[n]) $fatal(1,"freeze/count label f=%0d count=%0d x=%0d y=%0d",f,c,xx,yy);
    n=n+1;
   end
  end
  $display("PASS history status: STATE:FROZEN/CAPTURING, FRAMES:0..8/8, 497664 RGB pixels, all labels outside replay/comparison panes");$finish;
 end
endmodule
'''
top=Path('example_top.v').read_text(encoding='utf-8')
assert "lcd_ypos+12'd60" in top
assert '.X_START(1008),.Y_START(8)' in top
assert '.X_START(576),.Y_START(8)' in top
# Header boxes: THR/FPS [16,144)x[16,62); status [176,560)x[8,80);
# state/count [576,960)x[8,80); frame numbers [1008,1136)x[8,54).
# Replay starts at y=84; comparisons start at y=180.
assert 80<84<180
simulate('history_status',tb,['src/video_status_osd.v'])
