"""960-wide live majority voting and full-size history; random AXI stalls."""
from pathlib import Path
from run_canny import simulate
s=Path('tests/run_temporal_majority.py').read_text();ns={}
exec(s[:s.index("verify('temporal_majority',")],ns)
tb=ns['tb'].replace('848','960').replace('847','959').replace('432','960').replace('awlen!=6','awlen!=7').replace('arlen!=6','arlen!=7')
# Small-height transaction test still has grayscale for its first three rows.
tb=tb.replace('for(yy=0;yy<6;yy=yy+1) begin\n   for(xx=0;', '''for(yy=0;yy<6;yy=yy+1) begin
   if(yy<3) for(xx=0;xx<960;xx=xx+1) begin
    if(dut.rfifo_empty || pixel!==8'((yy+xx)&255)) $fatal(1,"gray row alignment");
    de=1;@(negedge dc);
   end
   for(xx=0;''')
simulate('960_temporal',ns['fifos']+tb,['src/axi/split_frame_ctrl.v'])
