"""Three-frame voting through real history DDR reads and live DDR writes."""
from pathlib import Path
import ast
from run_canny import simulate
import sys

def verify(name, tb, files, timeout=180):
 if '--full-only' not in sys.argv or name=='temporal_majority_full':
  try:simulate(name,tb,files,timeout=timeout)
  except Exception as error:
   if getattr(error,'stdout',None):print(error.stdout)
   raise

source=Path('tests/run_history.py').read_text()
base=next(n.value.value for n in ast.parse(source).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
fifos=Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
tb=base[:base.index(' integer beforewrites;')]
tb=tb.replace('.HISTORY_ENABLE(1),', '.HISTORY_ENABLE(1),.TEMPORAL_ENABLE(1),')
tb=tb.replace('reg reset=1,', 'reg temporal=1,inject_read_error=0,inject_write_error=0;reg reset=1,')
tb=tb.replace(".axi_rresp(2'd0)", ".axi_rresp(inject_read_error && dut.reading_temporal ? 2'd2 : 2'd0)")
tb=tb.replace(".axi_bresp(2'd0)", ".axi_bresp(inject_write_error && dut.wstate==15 ? 2'd2 : 2'd0)")
tb=tb.replace('.freeze_requested(freeze)', '.temporal_requested(temporal),.freeze_requested(freeze)')
tb=tb.replace('reg [127:0] mem[0:65535];', 'reg [127:0] mem[0:65535];reg [127:0] live[0:1048575];')
tb=tb.replace('begin edge_value=((col+3*line+5*frame)%17)<7;end', 'begin edge_value=(((col+line+frame/3)%8)>>(frame%3))&1;end')
tb=tb.replace('if(wa>=32\'h02000000) begin', 'if(wa<32\'h02000000) live[wa/16+wb]<=wd;\n    if(wa>=32\'h02000000) begin')
tb=tb.replace(': 0;\n  end\n end\n task boundary', ': live[ra/16+rb];\n  end\n end\n task boundary')
# Observe temporal fetch addresses; assert no uncommitted slot is read.
tb=tb.replace('reading<=1;ra<=ar;rb<=0;rlimit<=arlen;', '''reading<=1;ra<=ar;rb<=0;rlimit<=arlen;
    if(dut.reading_temporal) begin
     if(arlen!=6 || ar[6:0]!=0) $fatal(1,"temporal burst layout");
     if(((ar-32'h02000000)>>17)==dut.history_write_index) $fatal(1,"uncommitted frame read");
     temporal_reads<=temporal_reads+1;
    end''')
tb=tb.replace('integer history_rows=0,totalwrites=0,cycles=0;', 'integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0;')
tb+=r'''
 task capture_one;input integer ff;input enable_vote;
 begin
  wait(ready);f=ff;temporal=enable_vote;@(negedge pc);sof=1;@(negedge pc);sof=0;
  // Change the request during a frame: only its accepted SOP must matter.
  repeat(30) @(negedge pc);temporal=!enable_vote;
  for(y=0;y<3;y=y+1) for(x=0;x<432;x=x+1) begin
   @(negedge pc);gv=1;gd=x+y;end
  @(negedge pc);gv=0;
  for(y=0;y<6;y=y+1) for(x=0;x<848;x=x+1) begin
   @(negedge pc);ev=1;ed=edge_value(ff,y,x) ? 255 : 0;eof=y==5 && x==847;end
  @(negedge pc);ev=0;eof=0;
  wait(dut.completed_generation==ff+1);repeat(80) @(negedge pc);
 end endtask
 function bit vote;input integer ff,line,col;
  bit a,b,c;
  begin a=edge_value(ff,line,col);b=edge_value(ff-1,line,col);c=edge_value(ff-2,line,col);
   vote=(a&b)|(a&c)|(b&c);end
 endfunction
 task check_live;input integer ff;input enable_vote;
 integer xx,yy,beat,lane,idx;
 reg [7:0] expected;
 begin
  for(yy=0;yy<6;yy=yy+1) for(xx=0;xx<1024;xx=xx+1) begin
   idx=((dut.latest_frame_index<<22)+(yy<<11)+xx)/16;lane=xx%16;
   expected=xx<848 ? ((enable_vote && ff>=2 ? vote(ff,yy,xx) : edge_value(ff,yy,xx)) ? 255 : 0) : 0;
   if(live[idx][lane*8+:8] !== expected)
    $fatal(1,"live voting frame=%0d y=%0d x=%0d actual=%h expected=%h",ff,yy,xx,live[idx][lane*8+:8],expected);
  end
 end endtask
 task display_live;input integer ff;input enable_vote;
 integer xx,yy;reg [7:0] expected;
 begin
  hist=0;boundary;repeat(800) @(negedge dc);
  for(yy=0;yy<6;yy=yy+1) begin
   for(xx=0;xx<848;xx=xx+1) begin
    expected=(enable_vote && ff>=2 ? vote(ff,yy,xx) : edge_value(ff,yy,xx)) ? 255 : 0;
    if(dut.rfifo_empty || pixel!==expected) $fatal(1,"display majority alignment frame=%0d y=%0d x=%0d",ff,yy,xx);
    de=1;@(negedge dc);
   end
   de=0;repeat(600) @(negedge dc);
  end
 end endtask
 integer ff,before_reads;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  // 11 frames cross the 8-slot wrap. Frame 5 bypasses voting; frame 6
  // resumes using RAW history, rather than the previously filtered output.
  for(ff=0;ff<11;ff=ff+1) begin
   before_reads=temporal_reads;
   capture_one(ff,ff!=5);
   check_live(ff,ff!=5);
   if(temporal_reads-before_reads != (ff>=2 && ff!=5 ? 12 : 0)) $fatal(1,"temporal read count/SOP latch");
   display_live(ff,ff!=5);
  end
  // History must still be raw and replay remains compatible.
  freeze=1;wait(frozen);hist=1;replay=7;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(10,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  // Interrupt display bursts with a frame boundary while voting is active.
  hist=0;freeze=0;boundary;wait(ready);
  fork
   begin capture_one(11,1);check_live(11,1);end
   begin wait(dut.reading_temporal);boundary;end
  join
  display_live(11,1);
  $display("PASS majority3: all 8 binary combinations, startup bypass, raw history/no feedback, 8-slot wrap, SOP switching, live DDR + HDMI pixels, AXI backpressure and display restart during temporal reads");$finish;
 end
endmodule
'''
verify('temporal_majority',fifos+tb,['src/axi/split_frame_ctrl.v'])
# Two matching rows decide every pixel without reading the third frame.
stable=tb.replace('(((col+line+frame/3)%8)>>(frame%3))&1', '((col+line)%17)<7')
stable=stable.replace(' ? 12 : 0)', ' ? 6 : 0)')
verify('temporal_majority_stable',fifos+stable,['src/axi/split_frame_ctrl.v'])
mixed=tb.replace('(((col+line+frame/3)%8)>>(frame%3))&1', '(line%2==0 ? ((col+line)%17)<7 : (((col+line+frame/3)%8)>>(frame%3))&1)')
mixed=mixed.replace(' ? 12 : 0)', ' ? 9 : 0)')
verify('temporal_majority_mixed',fifos+mixed,['src/axi/split_frame_ctrl.v'])
# Exact three-slot depth must also wrap; raw current row already has a slot.
small=tb.replace('.HISTORY_ENABLE(1),', '.HISTORY_ENABLE(1),.FRAME_DEPTH(3),')
small=small.replace('reg [2:0] replay=7,left=0,right=7;', 'reg [1:0] replay=2,left=0,right=2;').replace('wire [3:0] count;', 'wire [2:0] count;').replace('replay=7;', 'replay=2;')
verify('temporal_majority_depth3',fifos+small,['src/axi/split_frame_ctrl.v'])

# Both newly added DDR operations must fail closed, without frame publication.
start=tb.index(' integer ff,before_reads;')
for operation in ('read','write'):
 error_tb=tb[:start]+f'''
 initial begin
  repeat(10) @(negedge pc);reset=0;
  capture_one(0,1);capture_one(1,1);inject_{operation}_error=1;
  fork
   capture_one(2,1);
   begin wait(dut.wstate==5);end
  join_any
  disable fork;
  repeat(100) @(negedge pc);
  if(dut.completed_generation!=2 || dut.history_write_index!=2 || count!=2 || ready)
   $fatal(1,"temporal {operation} error published incomplete frame");
  $display("PASS temporal {operation} AXI error blocks partial frame publication");$finish;
 end
endmodule
'''
 verify('temporal_majority_'+operation+'_error',fifos+error_tb,['src/axi/split_frame_ctrl.v'])

# Native thumbnails must still encode raw history when live edges are filtered.
native=tb.replace('.TEMPORAL_ENABLE(1),', '.TEMPORAL_ENABLE(1),.HISTORY_COMPARE_NATIVE(1),')
native=native.replace('if(aw>=32\'h02000000 && (awlen!=6 || aw[6:0]!=0))',
 "if(aw>=32'h02000000 && (aw>=32'h02100000 ? (awlen!=26 || aw[8:0]!=0) : (awlen!=6 || aw[6:0]!=0)))")
native=native.replace('if(wa>=32\'h02000000) begin',r'''if(wa>=32'h02100000) begin
     row=(wa & 32'hfffff)>>9;
     for(j=0;j<16;j=j+1) begin
      bitx=wb*16+j;
      if(wd[j*8+:8] !== ((bitx<424 &&
       (edge_value(f,2*row,2*bitx) || edge_value(f,2*row,2*bitx+1) ||
        edge_value(f,2*row+1,2*bitx) || edge_value(f,2*row+1,2*bitx+1))) ? 8'hff : 8'd0))
       $fatal(1,"raw temporal thumbnail mismatch");
     end
    end else if(wa>=32'h02000000) begin''')
verify('temporal_majority_native',fifos+native,['src/axi/split_frame_ctrl.v'])

# Opt-in full ROI verification, including interleaved left grayscale reads.
import sys
if '--full' in sys.argv or '--full-only' in sys.argv:
 full=tb.replace('.EDGE_LINES(6),.GRAY_LINES(3)', '.EDGE_LINES(636),.GRAY_LINES(318)').replace('cycles>3000000', 'cycles>12000000')
 full=full.replace('y<3;', 'y<318;').replace('y<6;', 'y<636;').replace('yy<6;', 'yy<636;').replace('y==5 && x==847', 'y==635 && x==847')
 full=full.replace(' ? 12 : 0)', ' ? 1272 : 0)').replace('ff<11;', 'ff<3;').replace('take(10,', 'take(2,').replace('capture_one(11,', 'capture_one(3,').replace('check_live(11,', 'check_live(3,').replace('display_live(11,', 'display_live(3,')
 full=full.replace('for(yy=0;yy<636;yy=yy+1) begin\n   for(xx=0;xx<848;', '''for(yy=0;yy<636;yy=yy+1) begin
   if(yy>=159 && yy<=476) for(xx=0;xx<432;xx=xx+1) begin
    if(dut.rfifo_empty || pixel!==8'((yy-159+xx)&255)) $fatal(1,"grayscale interleave alignment");
    de=1;@(negedge dc);
   end
   for(xx=0;xx<848;''')
 full=full.replace('PASS majority3: all 8 binary combinations, startup bypass, raw history/no feedback, 8-slot wrap, SOP switching, live DDR + HDMI pixels, AXI backpressure and display restart during temporal reads', 'PASS majority3 full 848x636: 4 live frames, startup bypass, grayscale interleave, raw history replay, voting with AXI backpressure and display restart')
 verify('temporal_majority_full',fifos+full,['src/axi/split_frame_ctrl.v'],timeout=300)
