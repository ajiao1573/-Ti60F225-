
from pathlib import Path
import sys,ast,random
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
import run_canny
from plate_reference import sample
OUT=ROOT/'tests/generated'
run_canny.OUT=OUT
simulate=run_canny.simulate
images=[sample('BKT682',size=size) for size in [52,32,24]]
im=sample('BKT682',size=32)
for kind in ['shadow','gradient']:
 out=im.copy()
 for y in range(96):
  for x in range(256):
   gain=(0.55 if x<128 else 1.0) if kind=='shadow' else 0.3+0.7*x/255
   out.putpixel((x,y),round(im.getpixel((x,y))*gain))
 images.append(out)
p=OUT/'plate_sizes.hex';p.write_text(''.join(f'{v:02x}\n' for im in images for v in im.tobytes()))
tb=r'''@TICK@timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg pc=0;always #7 pc=~pc;
 reg rst=0,en=0,iv=0,sop=0,accept=0,vs=0;reg [10:0] ix=0;reg [9:0] iy=0;reg [7:0] gray=0;
 wire hold,locked,valid,ready,toggle,lowc;wire [47:0] ascii;wire [3:0] count;wire [7:0] threshold;wire [23:0] pixel;
 plate_segmenter #(.X_START(2),.Y_START(2),.ENABLE_NZ_OCR(1),.BLACK_INK(1),.ADAPTIVE_THRESHOLD(1),.MIN_HEIGHT(12)) dut(
 .clk(clk),.rst_n(rst),.enable(en),.in_valid(iv),.in_sop(sop),.in_x(ix),.in_y(iy),.in_gray(gray),.adjust(8'd128),
 .pixel_clk(pc),.pixel_rst_n(rst),.vsync(vs),.x_pos(12'd800),.y_pos(12'd280),.pixel(pixel),.ready(ready),.count(count),.threshold(threshold),.low_contrast(lowc),.display_toggle(toggle),
 .accept_frame(accept),.snapshot_ready(1'b1),.capture_hold(hold),.recognized_locked(locked),.recognized_valid(valid),.recognized_ascii(ascii));
 reg [7:0] image[0:122879];integer f,x,y;
 task boundary;begin @(negedge pc);vs=1;repeat(8) @(negedge pc);vs=0;repeat(8) @(negedge pc);end endtask
 initial begin
  $readmemh("@IMAGE@",image);
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<5;f=f+1) begin
   @(negedge clk);en=0;repeat(8) @(negedge clk);en=1;boundary;wait(dut.state==1);
   @(negedge clk);iv=1;sop=1;accept=1;ix=0;iy=0;
   @(negedge clk);sop=0;accept=0;
   for(y=0;y<96;y=y+1) for(x=0;x<256;x=x+1) begin
    ix=x+2;iy=y+2;gray=image[f*24576+y*256+x];@(negedge clk);
   end
   iv=0;wait(dut.state==22);boundary;
   $display("PLATE RTL case=%0d threshold=%0d LOW=%0d chars=%0d locked=%0d valid=%0d ascii=%s pixel=%h",f,threshold,lowc,count,locked,valid,ascii,pixel);
   if(!valid || ascii!=="BKT682" || count!=6 || lowc) $fatal(1,"field plate not recognized case=%0d ascii=%s",f,ascii);


  end
  $display("PASS field plate: three sizes plus shadow/gradient recognized; sparse text retained");$finish;
 end
 initial begin #100000000;$fatal(1,"plate timeout state=%0d",dut.state);end
endmodule
'''
simulate('field_plate',tb.replace('@TICK@',chr(96)).replace('@IMAGE@',p.as_posix()),['src/plate_segmenter.v'],timeout=180)
