"""Full960 shape RAM extent, four candidates and post-frame time budget."""
from pathlib import Path
s=Path('tests/run_shape_full.py').read_text()
s=s.replace('W,H=848,636','W,H=960,720')
s=s.replace('lambda x,y:200<=x<=640 and 510<=y<=634','lambda x,y:200<=x<=740 and 590<=y<=718')
s=s.replace('lambda x,y:False]', 'lambda x,y:False,lambda x,y:any((x-cx)**2+(y-cy)**2<=90**2 for cx,cy in [(240,180),(720,180),(240,540),(720,540)])]')
s=s.replace('shape_detect dut', 'shape_detect #(.WIDTH(960),.HEIGHT(720)) dut')
s=s.replace('expected[0:4]', 'expected[0:5]').replace('expected[4]=0;', 'expected[4]=0;expected[5]=1;').replace('f<5;', 'f<6;')
s=s.replace('timeout<300000', 'timeout<220000')
s=s.replace('   repeat(6) @(negedge clk);', '   $display("shape frame%0d post-frame cycles=%0d (<220000 of248000 vertical blank budget)",f,timeout);repeat(6) @(negedge clk);')
s=s.replace('PASS 848x636 recognition: large circle/rectangle/triangle, target at RAM row 634, blank clears, 2696640 input pixels', 'PASS 960x720 recognition: large shapes, row718 target, blank clears, four circles; post-frame budget and result CDC')
s=s.replace("simulate('shape_full'", "simulate('960_shape'").replace("simulate('shape_cdc'", "simulate('960_shape_cdc'")
exec(compile(s,'960_shape_generated','exec'))
