"""Verify the actual top-level recognition threshold and OSD source."""
from pathlib import Path
from run_canny import simulate
top=Path('example_top.v').read_text(encoding='utf-8')
fragment=top[top.index('    wire shape_requested='):top.index('    wire freeze_requested,compare_requested;')]
assert '.threshold(processing_threshold),.algorithm(algorithm_requested)' in top
assert 'canny_threshold_pixel_meta <= processing_threshold;' in top
tb='''module tb;
 reg [2:0] main_gear=0;reg [9:0] canny_threshold=0;
'''+fragment+'''
 integer g,t,expected;
 initial begin
  for(g=0;g<5;g=g+1) for(t=0;t<1024;t=t+1) begin
   main_gear=g;canny_threshold=t;#1;
   expected=g==4 ? (t>10 ? t-10 : 0) : t;
   if(processing_threshold!==expected) $fatal(1,"threshold g=%0d t=%0d got=%0d expected=%0d",g,t,processing_threshold,expected);
  end
  main_gear=4;canny_threshold=72;#1;if(processing_threshold!=62) $fatal(1,"default recognition 62");
  main_gear=0;#1;if(processing_threshold!=72) $fatal(1,"original threshold restored");
  $display("PASS actual top threshold: all 5120 gear/value combinations, gear5 minus10 saturation, default72->62, other modes, engine and OSD source");$finish;
 end
endmodule
'''
simulate('shape_threshold',tb,[])
