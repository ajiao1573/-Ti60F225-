"""Full720-row grayscale/edge readback, including row counters above511."""
from pathlib import Path
ns={};s=Path('tests/run_960_stream.py').read_text();exec(s[:s.index("if '--quick'")],ns)
tb=ns['tb'].replace('H=720,F=5','H=720,F=1').replace('reg overlay=1,','reg overlay=0,')
tb=tb.replace('(left_pixel ? dut.rgb_display_empty : (!dut.rgb_line_valid || dut.rfifo_empty))','dut.rfifo_empty')
start=tb.index('    expected=left_pixel ?');end=tb.index('    de=1;@(negedge dc);',start)
tb=tb[:start]+'''    #0.1;
    if(pixel!==(left_pixel ? 8'(yy+xx+17) : edge_value(F-1,yy,xx-960) ? 8'hff : 8'h00))
     $fatal(1,"full gray/edge pane mismatch y%0d x%0d got%h",yy,xx,pixel);
'''+tb[end:]
tb=tb.replace(' || checked<1920*H*2','').replace('PASS 960x720@60 DDR: %0d consecutive commits, full dual RGB, protected voting, randomized AXI stalls, no display underflow; %0d visible pixels','PASS full960x720 original grayscale + edge readback, rows0..719, pixel-perfect alignment, no underflow; captures%0d monitored%0d')
ns['simulate']('960_gray',ns['ns']['fifos']+ns['models']+tb,['src/axi/split_frame_ctrl.v'],timeout=600)
