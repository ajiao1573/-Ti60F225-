from pathlib import Path
import re
from run_canny import simulate

s=Path('src/video_status_osd.v').read_text()
fonts={int(c):[int(bits[i:i+5],2) for i in range(0,35,5)] for c,bits in re.findall(r"8'd(\d+):bits=35'b([01]{35});",s)}
cases=[(0,0,0,0,128,'VIEW:CAPTURING'),(1,1,0,0,111,'VIEW:TOO MANY SEGMENTS'),
       (1,0,1,0,128,'VIEW:LOW CONTRAST'),(1,0,0,0,111,'VIEW:NO CHARACTERS'),
       (1,0,0,6,7,'VIEW:CHARS:6 BIN:007'),(1,0,0,8,255,'VIEW:CHARS:8 BIN:255')]
pixels=[];initial=[]
for i,(ready,over,low,count,thr,label) in enumerate(cases):
    initial.append(f'configs[{i}]=15\'d{(ready<<14)|(over<<13)|(low<<12)|(count<<8)|thr};')
    for y in range(72):
        line=y//24;dy=y%24-4;word=['GEAR:6 PLATE SEG','ALG:CHAR SEGMENT',label][line].ljust(24)
        for x in range(384):
            row=dy//2;col=x%16//2;glyph=fonts.get(ord(word[x//16]),[0]*7)
            on=0<=dy<14 and col<5 and (glyph[row]>>(4-col)&1)
            pixels.append([0x00ffff,0xffff00,0x00ff80][line] if on else 0x081020)
Path('tests/generated/plate_status.hex').write_text(''.join(f'{p:06x}\n' for p in pixels))
tb=f'''`timescale 1ns/1ps
module tb;
 reg [11:0] x=0,y=0;reg ready=0,over=0,low=0;reg [3:0] count=0;reg [7:0] thr=0;
 wire [23:0] pixel;wire active;
 video_status_osd dut(.x_pos(x),.y_pos(y),.gear(3'd5),.algorithm(3'd0),
 .overlay(1'b0),.history(1'b0),.compare(1'b0),.replay(3'd0),.left_frame(3'd0),.right_frame(3'd7),
 .frozen(1'b0),.frame_count(4'd8),.pixel(pixel),.active(active),
 .segment_count(count),.segment_threshold(thr),.segment_ready(ready),.segment_overflow(over),.segment_low(low));
 reg [14:0] configs[0:5];reg [23:0] expected[0:{len(pixels)-1}];integer i,xx,yy,n=0;
 initial begin
  $readmemh("tests/generated/plate_status.hex",expected);
  {''.join(initial)}
  for(i=0;i<6;i=i+1) begin
   {{ready,over,low,count,thr}}=configs[i];
   for(yy=0;yy<72;yy=yy+1) for(xx=0;xx<384;xx=xx+1) begin
    x=16+xx;y=68+yy;#1;
    if(!active || pixel!==expected[n]) $fatal(1,"plate status %0d pixel %0d",i,n);
    n=n+1;
   end
  end
  $display("PASS plate status: six states, counts, threshold digits, 165888 rendered pixels");$finish;
 end
endmodule
'''
simulate('plate_status',tb,['src/video_status_osd.v'])
