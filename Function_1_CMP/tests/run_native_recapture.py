"""Entering comparison must NOT recapture: verify actual top freeze wiring.

The old design replaced the history ring with a fresh eight-frame batch on
every comparison entry. Gear 4 now freezes the live stream on gear entry and
comparison/replay read the stored frames, so the recapture trigger is gone.
This test statically rejects any leftover recapture path and simulates the
real expressions copied out of example_top.v.
"""
from pathlib import Path
import subprocess
from run_canny import simulate

top = Path('example_top.v').read_text(encoding='utf-8')
ctrl = Path('src/axi/split_frame_ctrl.v').read_text(encoding='utf-8')

assert 'compare_capture_toggle' not in top, 'stale comparison recapture trigger in top'
assert 'recapture' not in top, 'stale recapture reference in top'
assert 'recapture' not in ctrl, 'stale recapture logic in DDR controller'
assert '.freeze_requested(history_freeze_request)' in top.replace(' ', ''), \
    'DDR controller is not frozen by the combined freeze request'

wiring = top[top.index('    wire history_requested='):top.index('    wire overlay_requested=')]
tb = '''
module tb;
 localparam ENABLE_DDR_FRAME=1,ENABLE_2FRAME_COMP=1;
 reg freeze_requested=0,compare_requested=0,history_frozen=0;
 reg [2:0] main_gear=3;
''' + wiring + '''
 initial begin
  #1;
  if(history_freeze_request!==1'b0 || compare_capture_mode!==1'b0) $fatal(1,"idle gear4 must keep capturing");
  // History display waits for stable stored frames, even with freeze held.
  freeze_requested=1;#1;
  if(history_requested!==1'b0) $fatal(1,"history display must wait for frozen");
  if(history_freeze_request!==1'b1) $fatal(1,"freeze toggle must stop capture");
  history_frozen=1;#1;
  if(history_requested!==1'b1) $fatal(1,"frozen gear4 must show history");
  // Comparison holds capture stopped and shows history once frozen.
  freeze_requested=0;compare_requested=1;#1;
  if(history_freeze_request!==1'b1 || compare_capture_mode!==1'b1) $fatal(1,"comparison must hold capture stopped");
  if(history_requested!==1'b1) $fatal(1,"frozen comparison must show history");
  history_frozen=0;#1;
  if(history_requested!==1'b0) $fatal(1,"unfrozen comparison must stay on live view");
  history_frozen=1;compare_requested=0;#1;
  if(history_freeze_request!==1'b0 || history_requested!==1'b0) $fatal(1,"leaving comparison must release the hold");
  main_gear=2;compare_requested=1;#1;
  if(compare_capture_mode!==1'b0 || history_requested!==1'b0) $fatal(1,"comparison hold must be gated to gear 4");
  freeze_requested=1;#1;
  if(history_freeze_request!==1'b1) $fatal(1,"freeze toggle lost outside gear 4");
  $display("PASS no recapture: comparison only holds freeze, gear-gated, history display waits for frozen");$finish;
 end
endmodule
'''
try:
 simulate('native_no_recapture',tb,[])
except subprocess.CalledProcessError as error:
 print(error.stdout or '')
 raise
