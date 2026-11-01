"""Color overlay with temporal packing, early reads and burst resumption."""
from pathlib import Path
import ast
from run_canny import simulate
s=Path('tests/run_temporal_majority.py').read_text();ns={};exec(s[:s.index("verify('temporal_majority',")],ns)
models=next(n.value.value for n in ast.parse(Path('tests/run_overlay.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='models' for t in n.targets))
tb=ns['tb'][:ns['tb'].index(' integer ff,before_reads;')]
tb=tb.replace('.TEMPORAL_ENABLE(1),', '.TEMPORAL_ENABLE(1),.COLOR_ENABLE(1),.C_BUF_SIZE(23),')
tb=tb.replace('reg temporal=1,', 'reg overlay=0,cv=0,lv=0;reg [23:0] rgb=0;wire [23:0] display_rgb;reg temporal=1,')
tb=tb.replace('.overlay_requested(1\'b0)', '.rgb_data_en(cv),.rgb_data(rgb),.left_rgb_data_en(lv),.left_rgb_data(rgb),.rframe_left(1\'b0),.rframe_rgb(display_rgb),.overlay_requested(overlay)')
tb=tb.replace('live[0:1048575]', 'live[0:2097151]').replace('(dut.latest_frame_index<<22)', '(dut.latest_frame_index<<23)')
tb=tb.replace('integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0;', 'integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0,resumes=0,overlaps=0;')
tb=tb.replace('temporal_reads<=temporal_reads+1;', '''temporal_reads<=temporal_reads+1;
     if(!dut.temporal_phase && dut.temporal_resume_addr) resumes<=resumes+1;
     if(dut.wstate==6 || dut.wstate==7 || dut.wstate==8) overlaps<=overlaps+1;''')
tb=tb.replace('ed=edge_value(ff,y,x) ? 255 : 0;', 'ed=edge_value(ff,y,x) ? 255 : 0;cv=1;lv=!y[0] && !x[0];rgb=color(ff,y,x);')
tb=tb.replace('ev=0;eof=0;\n  wait(', 'ev=0;eof=0;cv=0;lv=0;\n  wait(')
tb+=r'''
 function [23:0] color;input integer ff,line,col;
 begin color={8'(ff+1),8'(line+17),8'(col+31)};end
 endfunction
 task show_overlay;input integer ff;
 integer xx,yy;reg [23:0] expected;
 begin
  overlay=1;boundary;repeat(800) @(negedge dc);
  for(yy=0;yy<6;yy=yy+1) begin
   for(xx=0;xx<848;xx=xx+1) begin
    expected=vote(ff,yy,xx) ? 24'hff0000 : color(ff,yy,xx);
    if(dut.rfifo_empty || dut.rgb_display_empty || display_rgb!==expected)
     $fatal(1,"temporal color resume y=%0d x=%0d actual=%h expected=%h",yy,xx,display_rgb,expected);
    de=1;@(negedge dc);
   end
   de=0;repeat(600) @(negedge dc);
  end
 end endtask
 integer ff;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  capture_one(0,1);capture_one(1,1);
  overlay=1;boundary;
  // Keep visible overlay consumption active while captures and DDR voting
  // compete with left/right color display bursts on the same read channel.
  fork
   begin for(ff=2;ff<7;ff=ff+1) begin capture_one(ff,1);check_live(ff,1);end end
   begin repeat(170000) begin @(negedge dc);de=!dut.rfifo_empty && !dut.rgb_display_empty;end de=0;end
  join
  show_overlay(6);
  if(resumes==0 || overlaps==0) $fatal(1,"did not exercise burst resume/early prefetch");
  $display("PASS temporal color concurrency: correct voted red edges + current RGB, raw history, overlapping history read/write, %0d burst resumes",resumes);$finish;
 end
endmodule
'''
simulate('temporal_color_speed',ns['fifos']+models+tb,['src/axi/split_frame_ctrl.v'])
