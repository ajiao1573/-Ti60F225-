from pathlib import Path
from run_canny import simulate
from collections import deque

tb=r'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg [1:0] keys=3;
 wire [2:0] gear;wire [2:0] algorithm;wire [1:0] mode;wire [9:0] threshold;
 wire [7:0] plate_adjust_unused;wire frozen,compare;wire [2:0] replay,left,right;
 video_key_control #(.CLOCK_HZ(100),.DEBOUNCE(3)) dut(
  clk,rst,keys,gear,algorithm,mode,threshold,frozen,compare,replay,left,right,plate_adjust_unused);
 task press;input [1:0] mask;input integer cycles;
  begin keys=~mask;repeat(cycles+8) @(negedge clk);keys=3;repeat(12) @(negedge clk);end
 endtask
 initial begin
  repeat(8) @(negedge clk);rst=1;repeat(8) @(negedge clk);
  if(gear!=0 || threshold!=72) $fatal(1,"reset");
  press(2,10);if(threshold!=77) $fatal(1,"plus step5");
  press(1,10);if(threshold!=72) $fatal(1,"minus step5");
  press(2,70);if(threshold!=72 || gear!=0) $fatal(1,"500ms-1s ignored");
  press(2,110);if(gear!=1) $fatal(1,"next gear");
  press(2,10);if(algorithm!=4) $fatal(1,"majority3 appended");
  press(2,10);if(algorithm!=0) $fatal(1,"five algorithm wrap");
  press(1,10);if(algorithm!=4) $fatal(1,"majority3 reverse wrap");
  press(1,10);if(algorithm!=3) $fatal(1,"algorithm reverse");
  press(2,110);if(gear!=2) $fatal(1,"gear3");
  press(2,10);if(mode!=1) $fatal(1,"color mode");
  press(2,10);if(mode!=0 || frozen) $fatal(1,"two display modes wrap without freezing");
  press(1,10);if(mode!=1 || frozen) $fatal(1,"display reverse wrap");
  press(2,10);if(mode!=0) $fatal(1,"display toggle");
  press(2,110);if(gear!=3 || !frozen || compare || replay!=7 || left!=0 || right!=7) $fatal(1,"auto freeze defaults");
  press(1,10);if(replay!=6) $fatal(1,"replay previous");
  press(2,10);if(replay!=7) $fatal(1,"replay next");
  press(2,10);if(replay!=7) $fatal(1,"replay boundary");
  press(3,10);if(!compare) $fatal(1,"chord mode");
  press(2,10);if(left!=0 || right!=1) $fatal(1,"right wraps inwards from default pair");
  press(1,10);if(left!=0 || right!=1) $fatal(1,"only legal left frame");
  press(2,10);press(1,10);if(left!=1 || right!=2) $fatal(1,"left wraps inwards");
  press(1,10);if(left!=0 || right!=2) $fatal(1,"left previous");
  // ALL_COMPARE_PAIRS
  press(3,110);if(frozen || !compare || gear!=3) $fatal(1,"chord resume");
  press(3,110);if(!frozen) $fatal(1,"chord refreeze");
  // Partial release must not become another single-key action.
  keys=0;repeat(18) @(negedge clk);keys=2;repeat(18) @(negedge clk);keys=3;repeat(12) @(negedge clk);
  if(compare || gear!=3 || !frozen) $fatal(1,"partial release");
  press(2,110);if(gear!=4 || frozen) $fatal(1,"fifth gear leaves history and resumes");
  press(2,10);if(threshold!=77 || gear!=4) $fatal(1,"shape threshold plus");
  press(1,10);if(threshold!=72 || gear!=4) $fatal(1,"shape threshold minus");
  press(2,110);if(gear!=0) $fatal(1,"five gears forward wrap");
  press(1,110);if(gear!=4) $fatal(1,"five gears reverse wrap");
  press(1,110);if(gear!=3 || !frozen) $fatal(1,"shape back to history");
  press(2,110);if(gear!=4 || frozen) $fatal(1,"shape resumes again");
  press(1,210);if(gear!=0 || frozen || threshold!=72) $fatal(1,"2second home");
  keys=1;@(negedge clk);keys=3;repeat(12) @(negedge clk);
  if(threshold!=72) $fatal(1,"bounce");
  $display("PASS five gears, shape threshold, wrap both ways, step5, release timing, algorithms, display, auto freeze, replay, chords, limits, 2s home, bounce");$finish;
 end
endmodule
'''
# Drive the real button gestures along shortest paths to every legal frame pair.
state=(0,2);checks=[]
for target in ((left,right) for left in range(8) for right in range(left+1,8)):
 queue=deque([(state,[])]);seen={state}
 while queue:
  pair,path=queue.popleft()
  if pair==target:
   for mask,pair in path:
    checks.append(f'  press({mask},10);if(left!={pair[0]} || right!={pair[1]} || !compare || !frozen || gear!=3) $fatal(1,"compare pair navigation");')
   checks.append(f'  if(left!={target[0]} || right!={target[1]}) $fatal(1,"unreachable pair");')
   state=target;break
  left,right=pair
  for mask,nxt in ((2,(left,right+1 if right<7 else left+1)),
                   (1,(left-1 if left else right-1,right))):
   if nxt not in seen:seen.add(nxt);queue.append((nxt,path+[(mask,nxt)]))
 else:raise AssertionError(f'Unreachable comparison pair {target}')
tb=tb.replace('  // ALL_COMPARE_PAIRS','\n'.join(checks))
tb=tb.replace('chords, limits,','chords, all 28 comparison pairs, boundary wrapping, limits,')
simulate('video_keys',tb,['src/video_key_control.v'])

# Disabling history still permits the new recognition gear in both directions.
tb_basic=tb[:tb.index(' initial begin')]+r'''
 initial begin
  repeat(8) @(negedge clk);rst=1;repeat(8) @(negedge clk);
  press(2,110);press(2,10);if(algorithm!=0) $fatal(1,"disabled history skips temporal");
  press(2,110);press(2,110);
  if(gear!=4 || frozen) $fatal(1,"history disabled skips to shape");
  press(1,110);if(gear!=2) $fatal(1,"reverse skips history");
  press(1,210);press(1,110);if(gear!=4) $fatal(1,"reverse wraps to shape");
  press(2,110);if(gear!=0) $fatal(1,"forward wraps to threshold");
  $display("PASS five gears with history disabled");$finish;
 end
endmodule
'''
tb_basic=tb_basic.replace('.DEBOUNCE(3)', '.DEBOUNCE(3),.ENABLE_DDR_FRAME(0)')
simulate('video_keys_no_history',tb_basic,['src/video_key_control.v'])
