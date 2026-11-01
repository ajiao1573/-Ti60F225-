"""960-wide history: full-size replay and two full-size comparison panes."""
from pathlib import Path
from run_canny import simulate
import ast
s=Path('tests/run_history.py').read_text()
tb=next(n.value.value for n in ast.parse(s).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
tb=tb.replace('awlen!=6','awlen!=7').replace('848','960').replace('847','959').replace('432','960')
tb=tb.replace('for(y=0;y<3;y=y+1) begin\n   for(x=0;x<960;x=x+1) take(1,2*y,2*x);\n   for(x=0;x<960;x=x+1) take(8,2*y,2*x);', 'for(y=0;y<6;y=y+1) begin\n   for(x=0;x<960;x=x+1) take(1,y,x);\n   for(x=0;x<960;x=x+1) take(8,y,x);')
fifos=Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
simulate('960_history',fifos+tb,['src/axi/split_frame_ctrl.v'])
