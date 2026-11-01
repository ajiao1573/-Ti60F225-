"""Reproduce DDR starvation at96MHz and exercise gray/color transitions."""
from pathlib import Path
import sys
ns={};s=Path('tests/run_960_stream.py').read_text();exec(s[:s.index("if '--quick'")],ns)
tb=ns['tb'][:ns['tb'].index(' reg run_display=')]
tb=tb.replace('H=720,F=5','H=12,F=1').replace('repeat((875-H)*1600)', 'repeat(6000)')
# 25% ready read beats: deliberately below the old two-RGB-read demand,
# while still above the new one-RGB-read demand. Write stalls remain random.
tb=tb.replace('rvalid=reading && rng[3]', 'rvalid=reading && rng[3] && rng[4]')
tb+=r'''
 integer rgb_reads=0,old_reads,xx,yy,k;reg mode;reg [23:0] expected_rgb;reg [7:0] expected_gray;
 always @(posedge ac) if(rv && arready && ar<32'h02000000 && ar[22]) rgb_reads=rgb_reads+1;
 task show;input color_mode;
 begin
  overlay=color_mode;old_reads=rgb_reads;boundary;
  repeat(6000) @(negedge dc);
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<1920;xx=xx+1) begin
    left_pixel=xx<960;de=1;#0.1;
    if(dut.display_overlay!==color_mode) $fatal(1,"mode changed during visible frame");
    if(color_mode) begin
     expected_rgb=left_pixel ? color(0,yy,xx) : edge_value(0,yy,xx-960) ? 24'hff0000 : color(0,yy,xx-960);
     if(output_rgb!==expected_rgb) $fatal(1,"RGB mode transition y%0d x%0d actual%h expected%h",yy,xx,output_rgb,expected_rgb);
    end else begin
     expected_gray=left_pixel ? 8'(yy+xx+17) : edge_value(0,yy,xx-960) ? 255:0;
     if(pixel!==expected_gray) $fatal(1,"gray mode transition y%0d x%0d actual%h expected%h",yy,xx,pixel,expected_gray);
    end
    if(yy==2 && xx==500) overlay=!color_mode;
    @(negedge dc);
   end
   de=0;repeat(280) @(negedge dc);
  end
  if(color_mode && rgb_reads-old_reads!=2*H) $fatal(1,"RGB row read more than once: bursts%0d",rgb_reads-old_reads);
  if(underflows!=0) $fatal(1,"display underflow %0d",underflows);
 end endtask
 initial begin
  repeat(10) @(negedge pc);reset=0;repeat(100) @(negedge pc);capture(0);
  freeze=1;wait(frozen);
  for(k=0;k<4;k=k+1) begin show(0);show(1);end
  $display("PASS 96MHz DDR, 148.5MHz HDMI: 8 gray/color transitions, exact RGB888 and red-edge pixels, one RGB read per row, 25%% read duty, zero underflow");$finish;
 end
endmodule
'''
files=['src/axi/split_frame_ctrl.v']
if '--baseline' in sys.argv:
 # Demonstrate the same visible-pixel regression before the repair.
 tb=tb.replace('if(color_mode && rgb_reads-old_reads!=2*H)', 'if(color_mode && rgb_reads-old_reads!=4*H)')
 files=[str(Path('../ti60_A_960x720_60fps/src/axi/split_frame_ctrl.v').resolve())]
ns['simulate']('color_modes_baseline' if '--baseline' in sys.argv else 'color_modes_fix',ns['ns']['fifos']+ns['models']+tb,files,timeout=300)
