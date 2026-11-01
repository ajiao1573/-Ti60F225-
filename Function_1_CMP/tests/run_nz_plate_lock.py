"""End-to-end capture/segmentation/OCR/dual-clock lock and re-arm."""
from PIL import Image
from plate_reference import sample,oracle
from run_canny import simulate,OUT
cases=[('',Image.new('L',(256,96),190)),('BKT682',sample('BKT682',size=52)),
 ('ZX1470',sample('ZX1470',size=52)),('',sample('ABCXYZ',size=52)),
 ('',sample('DMN112',negative=True,size=52))]
for word,image in cases:
 if word:assert len(oracle(image)[4])==6
OUT.joinpath('nz_lock_input.hex').write_text(''.join(f'{v:02x}\n' for word,image in cases for v in image.tobytes()))
tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg pc=0;always #7 pc=~pc;
 reg rst=0,en=0,iv=0,sop=0,accept=0,snapshot=0,vs=0;
 reg [10:0] ix=0;reg [9:0] iy=0;reg [7:0] gray=0;
 wire hold,locked,valid,ready,toggle;wire [47:0] ascii;
 plate_segmenter #(.X_START(2),.Y_START(2),.ENABLE_NZ_OCR(1)) dut(
 .clk(clk),.rst_n(rst),.enable(en),.in_valid(iv),.in_sop(sop),.in_x(ix),.in_y(iy),.in_gray(gray),.adjust(8'd128),
 .pixel_clk(pc),.pixel_rst_n(rst),.vsync(vs),.x_pos(12'd0),.y_pos(12'd0),.pixel(),.ready(ready),.display_toggle(toggle),
 .accept_frame(accept),.snapshot_ready(snapshot),.capture_hold(hold),
 .recognized_locked(locked),.recognized_valid(valid),.recognized_ascii(ascii));
 reg [7:0] images[0:122879];integer x,y,old_bank;reg old_toggle;
 always @(posedge clk) if(rst && dut.state==48 && dut.capture_write) $fatal(1,"capturing into locked frame");
 task boundary;begin @(negedge pc);vs=1;repeat(8) @(negedge pc);vs=0;repeat(8) @(negedge pc);end endtask
 task rearm;begin
  @(negedge clk);en=0;repeat(8) @(negedge clk);en=1;snapshot=0;
  repeat(8) @(negedge pc);boundary;wait(dut.state==1);
  if(locked || valid) $fatal(1,"stale OCR after re-arm");
 end endtask
 task frame(input integer index);begin
  wait(dut.state==1);@(negedge clk);iv=1;sop=1;accept=1;ix=0;iy=0;
  @(negedge clk);sop=0;accept=0;
  if(!hold) $fatal(1,"did not reserve accepted DDR frame at SOP");
  for(y=0;y<96;y=y+1) for(x=0;x<256;x=x+1) begin
   ix=x+2;iy=y+2;gray=images[index*24576+y*256+x];@(negedge clk);
  end
  iv=0;
 end endtask
 initial begin
  $readmemh("tests/generated/nz_lock_input.hex",images);
  repeat(8) @(negedge clk);rst=1;en=1;wait(dut.state==1);
  @(negedge clk);iv=1;sop=1;accept=0;@(negedge clk);iv=0;sop=0;
  repeat(4) @(negedge clk);if(dut.state!=1 || hold) $fatal(1,"accepted a non-DDR source SOP");
  frame(0);wait(dut.state==22);boundary;wait(dut.state==1);
  if(hold || locked || valid) $fatal(1,"blank frame permanently froze");
  old_toggle=toggle;frame(1);wait(dut.state==21);repeat(50) @(negedge clk);boundary;
  if(toggle!==old_toggle || locked || !hold) $fatal(1,"published before full DDR frame committed");
  snapshot=1;wait(dut.state==22);boundary;wait(dut.state==48);
  if(!locked || !valid || ascii!=="BKT682") $fatal(1,"new format result %s valid=%0d",ascii,valid);
  old_bank=dut.display_bank;old_toggle=toggle;
  repeat(3) begin
   @(negedge clk);iv=1;sop=1;accept=1;gray=0;ix=0;iy=0;
   @(negedge clk);iv=0;sop=0;accept=0;boundary;
  end
  if(dut.display_bank!=old_bank || toggle!==old_toggle || ascii!=="BKT682" || !hold)
   $fatal(1,"live frames replaced frozen result");
  rearm;frame(2);snapshot=1;wait(dut.state==22);boundary;wait(dut.state==48);
  if(!locked || !valid || ascii!=="ZX1470") $fatal(1,"old format result %s valid=%0d",ascii,valid);
  rearm;frame(3);snapshot=1;wait(dut.state==22);boundary;wait(dut.state==1);
  if(locked || hold || valid || ascii!==48'h3f3f3f3f3f3f) $fatal(1,"unsupported text reported as a known plate");
  rearm;frame(4);snapshot=1;wait(dut.state==22);boundary;wait(dut.state==1);
  if(hold || locked || valid) $fatal(1,"inverse plate locked under white-background contract");
  // Re-arm while an old result is awaiting HDMI acknowledge. A late
  // request must not resurrect the cancelled result at the next blank.
  frame(1);snapshot=1;wait(dut.state==22);rearm;boundary;
  if(ready || locked || valid) $fatal(1,"cancelled pending result reappeared");
  frame(2);snapshot=1;wait(dut.state==22);boundary;wait(dut.state==48);
  if(!valid || ascii!=="ZX1470") $fatal(1,"recovery after pending-result cancellation");
  en=0;boundary;
  $display("PASS NZ auto-lock: accepted-frame gate, blank scan, DDR commit wait, both formats, frozen-bank protection, re-arm, invalid text and inverse rejection");$finish;
 end
 initial begin #100000000;$fatal(1,"lock timeout state=%0d candidate=%0d",dut.state,dut.work_candidate);end
endmodule
'''
simulate('nz_plate_lock',tb,['src/plate_segmenter.v'],timeout=240)