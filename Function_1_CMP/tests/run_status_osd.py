from pathlib import Path
import re,json
s=Path('src/video_status_osd.v').read_text();fonts={int(c):[int(bits[i:i+5],2) for i in range(0,35,5)] for c,bits in re.findall(r"8'd(\d+):bits=35'b([01]{35});",s)}
configs=[];labels=[];pixels=[]
for gear in range(5):
 for alg in range(5):
  for view in range(4):
   frame=(gear+alg)%8;left=(alg+1)%8;right=7
   configs.append((gear,alg,view,frame,left,right))
   lines=[['GEAR:1 THRESHOLD','GEAR:2 ALGORITHM','GEAR:3 DISPLAY','GEAR:4 HISTORY','GEAR:5 SHAPE'][gear],['ALG:SOBEL','ALG:SOBEL+MEDIAN','ALG:CANNY','ALG:CANNY+MEDIAN','ALG:MAJORITY3'][alg],['VIEW:SHAPE DETECTION' if gear==4 else 'VIEW:GRAY+EDGE','VIEW:SHAPE DETECTION' if gear==4 else 'VIEW:COLOR+RED',f'VIEW:REPLAY FRAME:{frame}',f'VIEW:COMPARE L:{left} R:{right}'][view]]
   labels.append(lines)
   for y in range(72):
    line=y//24;dy=y%24-4;word=lines[line].ljust(24)
    for x in range(384):
     row=dy//2;col=x%16//2;glyph=fonts.get(ord(word[x//16]),[0]*7)
     on=0<=dy<14 and col<5 and (glyph[row]>>(4-col)&1)
     pixels.append([0x00ffff,0xffff00,0x00ff80][line] if on else 0x081020)
Path('tests/generated/status_labels.json').write_text(json.dumps(labels))
# Keep the raster for reviewing rendered RTL glyphs.
Path('tests/generated/status_expected.hex').write_text(''.join(f'{p:06x}\n' for p in pixels))
init='\n'.join(f' configs[{i}]=18\'h{(g<<14)|(a<<11)|(v<<9)|(f<<6)|(l<<3)|r:05x};' for i,(g,a,v,f,l,r) in enumerate(configs))
tb=f'''`timescale 1ns/1ps
module tb;
 reg [11:0] x=0,y=0;reg [2:0] gear=0;reg [2:0] alg=0;reg overlay=0,history=0,comp=0;
 reg [2:0] frame=0,left=0,right=7;wire [23:0] rgb;wire active;
 video_status_osd dut(x,y,gear,alg,overlay,history,comp,frame,left,right,1'b0,4'd8,rgb,active,4'd0,8'd128,1'b0,1'b0,1'b0);
 reg [23:0] expected[0:{len(pixels)-1}];reg [17:0] configs[0:{len(configs)-1}];
 integer k,xx,yy,n=0;reg [1:0] v;
 initial begin
  $readmemh("tests/generated/status_expected.hex",expected);
{init}
  for(k=0;k<{len(configs)};k=k+1) begin
   {{gear,alg,v,frame,left,right}}=configs[k];overlay=v==1;history=v>=2;comp=v==3;
   for(yy=0;yy<72;yy=yy+1) for(xx=0;xx<384;xx=xx+1) begin
    x=16+xx;y=68+yy;#1;
    if(!active || rgb!==expected[n]) $fatal(1,"status raster config=%0d x=%0d y=%0d got=%h expected=%h",k,xx,yy,rgb,expected[n]);
    n=n+1;
   end
   x=400;y=70;#1;if(active) $fatal(1,"right border");
   x=20;y=140;#1;if(active) $fatal(1,"bottom border");
   x=15;y=70;#1;if(active) $fatal(1,"left border");
  end
  $display("PASS status OSD: {len(configs)} gear/algorithm/view configurations, frame numbers, {len(pixels)} RGB pixels, labels, glyphs, colors, borders");$finish;
 end
endmodule
'''
Path('tests/generated/status_osd.sv').write_text(tb)
Path('tests/generated/status_configs.json').write_text(json.dumps(configs))
from run_canny import simulate
simulate('status_osd',tb,['src/video_status_osd.v'])
