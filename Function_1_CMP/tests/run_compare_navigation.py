"""Drive physical key gestures through frame selection and DDR pixel readout."""
from pathlib import Path
import ast,subprocess
from run_canny import simulate

fixture=ast.parse(Path('tests/run_history.py').read_text())
fixture.body=[node for node in fixture.body if not (isinstance(node,ast.Expr) and
 isinstance(node.value,ast.Call) and isinstance(node.value.func,ast.Name) and node.value.func.id=='simulate')]
context={};exec(compile(fixture,'tests/run_history.py','exec'),context)
tb=context['tb'];fifos=context['fifos']
tb=tb.replace('hist=0,comp=0,vs=0','hist=0,vs=0')
tb=tb.replace('reg [2:0] replay=7,left=0,right=7;', '''
 reg [1:0] keys=3;wire [2:0] gear;wire [2:0] algorithm;wire [1:0] mode;wire [9:0] threshold;
 wire kfreeze,comp;wire [2:0] replay,left,right;
 video_key_control #(.CLOCK_HZ(100),.DEBOUNCE(3)) keyctrl(
 pc,!reset,keys,gear,algorithm,mode,threshold,kfreeze,comp,replay,left,right);
 task press;input [1:0] mask;input integer cycles;
 begin keys=~mask;repeat(cycles+8) @(negedge pc);keys=3;repeat(12) @(negedge pc);end
 endtask
 task rowpair;input integer l,r,yy;integer col;
 begin
  @(negedge dc);
  for(col=0;col<432;col=col+1) take(l,2*yy,2*col);
  for(col=0;col<432;col=col+1) take(r,2*yy,2*col);
  de=0;repeat(600) @(negedge dc);
 end
 endtask''')
at=tb.index('  hist=1;replay=0;boundary;')
tb=tb[:at]+r'''
  press(2,110);press(2,110);press(2,110);press(3,10);
  if(gear!=3 || !kfreeze || !comp || left!=0 || right!=7) $fatal(1,"comparison defaults");
  hist=1;boundary;repeat(800) @(negedge dc);
  rowpair(1,8,0);
  press(2,10);
  if(right!=1 || dut.display_right!=7) $fatal(1,"key response or mid-frame selection changed");
  rowpair(1,8,1);rowpair(1,8,2);
  boundary;repeat(800) @(negedge dc);
  if(dut.display_right!=1) $fatal(1,"new right frame not applied at boundary");
  for(y=0;y<3;y=y+1) rowpair(1,2,y);
  press(2,10);press(1,10);boundary;repeat(800) @(negedge dc);
  if(left!=1 || right!=2) $fatal(1,"left wrap");
  for(y=0;y<3;y=y+1) rowpair(2,3,y);
  repeat(5) press(2,10);press(1,10);press(1,10);
  boundary;repeat(800) @(negedge dc);
  if(left!=6 || right!=7) $fatal(1,"left wraps from zero to right-1");
  for(y=0;y<3;y=y+1) rowpair(7,8,y);
  press(3,10);boundary;repeat(800) @(negedge dc);
  if(dcmp || comp) $fatal(1,"return to replay");
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(8,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  if(!frozen || totalwrites!=beforewrites) $fatal(1,"navigation changed frozen DDR");
  $display("PASS real key -> DDR navigation: 0/7 -> 0/1 -> 1/2 -> 6/7, chronological pixels, frame-boundary updates, no frozen writes, chord back to replay");$finish;
 end
endmodule
'''
try:
 simulate('compare_navigation',fifos+tb,['src/video_key_control.v','src/axi/split_frame_ctrl.v'])
except subprocess.CalledProcessError as error:
 print(error.stdout or '')
 raise
