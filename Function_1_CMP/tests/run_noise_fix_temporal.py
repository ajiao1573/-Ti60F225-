from pathlib import Path
from run_canny import ROOT,OUT,simulate
s=(ROOT/'tests/run_temporal_majority.py').read_text();ns={}
exec(s[:s.index("verify('temporal_majority',")],ns)
tb=ns['tb'][:ns['tb'].index(' integer ff,before_reads;')]
tb=tb.replace('.TEMPORAL_ENABLE(1),','.TEMPORAL_ENABLE(1),.CONFIG_GUARD(1),.MOTION_PROTECT(1),')
tb=tb.replace('reg temporal=1,','reg protect=0;reg[11:0] configuration=0;reg temporal=1,')
tb=tb.replace('.temporal_requested(temporal)', '.temporal_requested(temporal),.edge_configuration(configuration),.edge_protect(protect)')
tb=tb.replace('(((col+line+frame/3)%8)>>(frame%3))&1','frame<2 ? 1 : frame<4 ? 0 : col==200+3*frame ? 1 : (((col+line+frame/3)%8)>>(frame%3))&1')
tb=tb.replace('wait(ready);f=ff;temporal=enable_vote;', 'wait(ready);f=ff;temporal=enable_vote;configuration=ff<2 ? 12\'h000:12\'h12f;')
tb=tb.replace('temporal=!enable_vote;', "temporal=!enable_vote;configuration=12'hbad;")
tb=tb.replace('ed=edge_value(ff,y,x) ? 255 : 0;', 'ed=edge_value(ff,y,x) ? 255 : 0;protect=protect_value(ff,y,x);')
tb=tb.replace('vote=(a&b)|(a&c)|(b&c);','vote=a && (protect_value(ff,line,col) || b || c);')
tb=tb.replace('enable_vote && ff>=2','enable_vote && ff>=4')
# Icarus requires function actual arguments declared before the instance.
decl=next(line for line in tb.splitlines() if 'integer f=' in line)
tb=tb.replace(decl,'',1).replace(' split_frame_ctrl #',decl+'\n split_frame_ctrl #',1)
tb+=r'''
 function bit protect_value;input integer ff,line,col;
 begin protect_value=ff>=4 && edge_value(ff,line,col) && (col==200+3*ff || col%11==0);end
 endfunction
 integer ff,prior_reads;
 initial begin
 repeat(10) @(negedge pc);reset=0;
 for(ff=0;ff<11;ff=ff+1) begin
  prior_reads=temporal_reads;
  capture_one(ff,1);check_live(ff,1);display_live(ff,1);
  if(ff<4 && temporal_reads!=prior_reads) $fatal(1,"mixed configuration history used ff=%0d",ff);
  if(ff>=4 && live[((dut.latest_frame_index<<22)+200+3*ff)/16][((200+3*ff)%16)*8+:8]!==255)
   $fatal(1,"moving strong contour erased");
 end
 freeze=1;wait(frozen);hist=1;replay=7;boundary;repeat(800) @(negedge dc);
 for(y=0;y<6;y=y+1) begin
 for(x=0;x<848;x=x+1) take(10,y,x);
 de=0;repeat(600) @(negedge dc);
 end
 $display("PASS guarded history: two compatible completed frames, mid-frame controls ignored, confidence-aligned moving edge retained, no old-only ghost, decoded 255 output, raw ring history/replay");$finish;
 end
endmodule
'''
try:simulate('noise_fix_temporal',ns['fifos']+tb,['src/axi/split_frame_ctrl.v'],timeout=180)
except Exception as error:
 if getattr(error,'stdout',None):print(error.stdout)
 raise
