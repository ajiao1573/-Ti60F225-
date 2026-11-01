from run_canny import simulate
from pathlib import Path
simulate('ddr',Path('tests/tb_split_frame_ctrl.sv').read_text(),['src/axi/split_frame_ctrl.v'])
tb=Path('tests/tb_split_frame_ctrl.sv').read_text()
tb=tb[:tb.index(' integer x,y;')]+'''
 integer x;
 initial begin
  repeat(8) @(negedge pc);reset=0;wait(ready);
  @(negedge pc);sof=1;bresp=2;
  @(negedge pc);sof=0;
  for(x=0;x<2304;x=x+1) begin
   @(negedge pc);gv=1;gd=((x%432)+(x/432)+17)&255;
   @(negedge pc);gv=0;
  end
  wait(dut.wstate==5);repeat(30) @(negedge pc);
  if(ready || dut.frame_available || awvalid || wvalid) $fatal(1,"DDR error published frame");
  @(negedge pc);reset=1;repeat(8) @(negedge pc);reset=0;
  wait(ready);
  if(dut.frame_available) $fatal(1,"reset retained failed frame");
  $display("PASS DDR write-error containment and reset recovery");$finish;
 end
endmodule
'''
simulate('ddr_error',tb,['src/axi/split_frame_ctrl.v'])
