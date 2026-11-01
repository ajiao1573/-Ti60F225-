"""Odd-height chronological history ring, freeze, resume and comparison."""
import runpy,sys
import run_canny
simulate=run_canny.simulate
cases={};saved=sys.argv
run_canny.simulate=lambda name,tb,files,**kw:cases.update({name:(tb,files)})
try:
 sys.argv=['tests/run_history.py'];runpy.run_path('tests/run_history.py',run_name='__capture__')
finally:sys.argv=saved;run_canny.simulate=simulate
for name in ['history','history_depth3','history_startup_freeze']:
 s,files=cases[name]
 s=s.replace('.EDGE_LINES(6),.GRAY_LINES(3)','.EDGE_LINES(5),.GRAY_LINES(2),.LETTERBOX_TOP(79)')
 s=s.replace('y<3;y=y+1) for(x=0;x<432;','y<2;y=y+1) for(x=0;x<432;')
 s=s.replace('y<6;','y<5;').replace('y==5 &&','y==4 &&')
 s=s.replace('history_rows==54','history_rows==45').replace('history_rows==24','history_rows==20')
 simulate('display_letterbox_'+name,s,files,timeout=180)
