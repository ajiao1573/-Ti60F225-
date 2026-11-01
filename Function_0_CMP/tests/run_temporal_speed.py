"""Compare identical temporal voting workloads against the pre-speed RTL."""
from pathlib import Path
import json,re
from run_canny import simulate
root=Path.cwd()
source=Path('tests/run_temporal_majority.py').read_text()
ns={};exec(source[:source.index("verify('temporal_majority',")],ns)
base=ns['tb'][:ns['tb'].index(' integer ff,before_reads;')]
base=base.replace('integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0;', 'integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0,write_beats_total=0;')
base=base.replace('if(wv && wready) begin', 'if(wv && wready) begin\n    write_beats_total<=write_beats_total+1;')
bench=base+r'''
 integer start_cycle,start_beats,elapsed,beats;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  capture_one(0,1);check_live(0,1);
  capture_one(1,1);check_live(1,1);
  // Prefetch a real live display frame, then let its FIFO backpressure the
  // shared reader while the next frame is captured and voted.
  boundary;repeat(800) @(negedge dc);
  start_cycle=cycles;start_beats=write_beats_total;
  capture_one(2,1);check_live(2,1);
  elapsed=cycles-start_cycle;beats=write_beats_total-start_beats;
  $display("METRIC cycles=%0d write_beats=%0d bursts=%0d",elapsed,beats,totalwrites);
  display_live(2,1);
  $display("PASS temporal speed fixture, exact live output and raw history");$finish;
 end
endmodule
'''
results={}
for rate,clock in [('camera_100MHz','5'),('ddr_saturated','0.5'),('stable_rows','0.5')]:
 results[rate]={}
 for version,rtl in [('before','backup_before_temporal_speed/src/axi/split_frame_ctrl.v'),('after','src/axi/split_frame_ctrl.v')]:
  name=f'temporal_speed_{rate}_{version}'
  fixture=bench.replace('always #5 pc=~pc',f'always #{clock} pc=~pc')
  if rate=='stable_rows':fixture=fixture.replace('(((col+line+frame/3)%8)>>(frame%3))&1', '((col+line)%17)<7')
  simulate(name,ns['fifos']+fixture,[rtl])
  log=Path(f'tests/generated/{name}.log').read_text()
  match=re.search(r'METRIC cycles=(\d+) write_beats=(\d+)',log)
  results[rate][version]={'axi_cycles':int(match[1]),'write_beats':int(match[2])}
 before=results[rate]['before'];after=results[rate]['after']
 assert before['write_beats']==906 and after['write_beats']==522
 assert after['axi_cycles']<before['axi_cycles']
 results[rate]['commit_cycles_reduction_percent']=round(100*(1-after['axi_cycles']/before['axi_cycles']),2)
 results[rate]['write_beats_reduction_percent']=round(100*(1-after['write_beats']/before['write_beats']),2)
Path('tests/generated/temporal_speed_comparison.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
