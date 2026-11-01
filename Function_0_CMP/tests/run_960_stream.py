"""Full-size concurrent capture/display, vote, RGB reuse, fixed 60Hz clocks.
Behavioral DDR/FIFOs check protocol, contents and stalls; not a DDR PHY model.
"""
from pathlib import Path
import ast,sys
from run_canny import simulate
ns={};s=Path('tests/run_temporal_majority.py').read_text();exec(s[:s.index("verify('temporal_majority',")],ns)
models=next(n.value.value for n in ast.parse(Path('tests/run_overlay.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='models' for t in n.targets))
# Match the enlarged production read FIFO. Write FIFO remains 2048 pixels.
a=models.index('module R0_FIFO_32');models=models[:a]+models[a:].replace('2047','4095').replace('2048','4096').replace('2044','4092').replace('>=512','>=1024')
tb=ns['tb'][:ns['tb'].index(' task capture_one;')]
tb=tb.replace('always #5.2 ac','always #5.208333 ac').replace('always #5 pc','always #5.952381 pc').replace('always #6.72 dc','always #3.367003 dc')
tb=tb.replace('.EDGE_LINES(6),.GRAY_LINES(3)', '.EDGE_LINES(H),.GRAY_LINES(H)').replace('module tb;', 'module tb;\n localparam H=720,F=5;')
tb=tb.replace('.TEMPORAL_ENABLE(1),','.TEMPORAL_ENABLE(1),.COLOR_ENABLE(1),.C_BUF_SIZE(23),.CONFIG_GUARD(1),.MOTION_PROTECT(1),')
tb=tb.replace('reg temporal=1,', 'reg overlay=1,cv=0,left_pixel=0;reg[23:0] rgb=0;wire[23:0] output_rgb;wire[9:0] underflows;reg temporal=1,')
tb=tb.replace(".overlay_requested(1'b0)", ".rgb_data_en(cv),.rgb_data(rgb),.left_rgb_data_en(1'b0),.left_rgb_data(24'd0),.rframe_left(left_pixel),.rframe_rgb(output_rgb),.overlay_requested(overlay),.display_underflow_total(underflows)")
tb=tb.replace('.temporal_requested(temporal)',".temporal_requested(temporal),.edge_configuration(12'h001),.edge_protect(ed!=0)")
tb=tb.replace('live[0:1048575]', 'live[0:2097151]').replace('cycles>3000000','cycles>24000000')
tb=tb.replace('848','960').replace('awlen!=6','awlen!=7').replace('arlen!=6','arlen!=7')
# All present edges carry protection: moving strong contours must stay visible.
tb+=r'''
 function [23:0] color;input integer ff,line,col;
 begin color={8'(ff+1),8'(line+17),8'(col+31)};end endfunction
 task capture;input integer ff;
 integer xx,yy;
 begin
  f=ff;
  if(!ready) $fatal(1,"dropped camera SOP frame %0d",ff);
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<1600;xx=xx+1) begin
    sof=yy==0 && xx==0;gv=xx<960;ev=gv;cv=gv;
    eof=yy==H-1 && xx==959;gd=8'(yy+xx+17);
    ed=edge_value(ff,yy,xx) ? 255:0;rgb=color(ff,yy,xx);
    @(negedge pc);
   end
  end
  gv=0;ev=0;cv=0;sof=0;eof=0;
  repeat((875-H)*1600) @(negedge pc);
  if(dut.completed_generation!=ff+1) $fatal(1,"frame not committed before next 60Hz SOP %0d",ff);
 end endtask
 reg run_display=1,display_done=0;integer dx,dy,refreshes=0,checked=0;
 initial begin
  wait(!reset);
  while(run_display) begin
   for(dy=0;dy<1125;dy=dy+1) begin
    for(dx=0;dx<2200;dx=dx+1) begin
     @(negedge dc);vs=dy>=1084 && dy<1089;
     de=dut.display_started && dy>=180 && dy<900 && dx<1920;
     left_pixel=dx<960;
     if(de) begin
      if((left_pixel ? dut.rgb_display_empty : (!dut.rgb_line_valid || dut.rfifo_empty)))
       $fatal(1,"continuous HDMI underflow frame%0d y%0d x%0d",refreshes,dy,dx);
      checked=checked+1;
     end
    end
   end
   refreshes=refreshes+1;
  end
  display_done=1;
 end
 integer ff,xx,yy;reg[23:0] expected;
 initial begin
  repeat(10) @(negedge pc);reset=0;repeat(100) @(negedge pc);
  for(ff=0;ff<F;ff=ff+1) capture(ff);
  freeze=1;wait(frozen);run_display=0;wait(display_done);
  // Exact pixel comparison after all capture traffic has settled.
  boundary;repeat(4000) @(negedge dc);
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<1920;xx=xx+1) begin
    left_pixel=xx<960;
    expected=left_pixel ? color(F-1,yy,xx) :
      edge_value(F-1,yy,xx-960) ? 24'hff0000 : color(F-1,yy,xx-960);
    #0.1;
    if(output_rgb!==expected) $fatal(1,"full RGB pane mismatch y%0d x%0d got%h expected%h",yy,xx,output_rgb,expected);
    de=1;@(negedge dc);
   end
   de=0;repeat(280) @(negedge dc);
  end
  if(underflows!=0 || checked<1920*H*2 || count!=F) $fatal(1,"60Hz accounting");
  $display("PASS 960x720@60 DDR: %0d consecutive commits, full dual RGB, protected voting, randomized AXI stalls, no display underflow; %0d visible pixels",F,checked);$finish;
 end
endmodule
'''
if '--quick' in sys.argv:
 tb=tb.replace('H=720,F=5','H=6,F=5').replace('dy<900','dy<180+H')
simulate('960_stream_quick' if '--quick' in sys.argv else '960_stream',ns['fifos']+models+tb,['src/axi/split_frame_ctrl.v'],timeout=1200)
