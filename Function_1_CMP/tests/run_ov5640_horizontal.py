"""Read the actual sensor ROM and permit only the horizontal orientation change."""
from pathlib import Path
import re
from run_canny import simulate,OUT
baseline=Path('backup_before_horizontal_fix/src/cmos_i2c/ov5640_1080p30_regs.v').read_text(encoding='utf-8')
entries={int(i):(int(v,16),int(d)) for i,v,d in re.findall(r"9'd(\d+): begin data=24'h([0-9a-f]+); delay_ms=8'd(\d+); end",baseline)}
assert len(entries)==268 and entries[214][0]==0x382106
entries[214]=(0x382100,entries[214][1])
OUT.joinpath('ov5640_horizontal_expected.hex').write_text(''.join(f'{entries[i][0]:06x}\n' for i in range(268)))
OUT.joinpath('ov5640_horizontal_delays.hex').write_text(''.join(f'{entries[i][1]:02x}\n' for i in range(268)))
tb=r"""
`timescale 1ns/1ps
module tb;
 reg [8:0] index=9'h1ff;wire [23:0] data;wire [7:0] delay_ms;wire [8:0] count;
 ov5640_1080p30_regs dut(index,data,delay_ms,count);
 reg [23:0] expected[0:267];reg [7:0] delays[0:267];integer i;
 initial begin
  $readmemh("tests/generated/ov5640_horizontal_expected.hex",expected);
  $readmemh("tests/generated/ov5640_horizontal_delays.hex",delays);
  for(i=0;i<268;i=i+1) begin
   index=i;#1;
   if(count!==268 || data!==expected[i] || delay_ms!==delays[i])
    $fatal(1,"ROM orientation index=%0d got=%h expected=%h",i,data,expected[i]);
  end
  $display("PASS sensor horizontal correction: all 268 actual ROM entries/delays, only 3821 06->00, vertical 3820=46 retained");$finish;
 end
endmodule
"""
simulate('ov5640_horizontal',tb,['src/cmos_i2c/ov5640_1080p30_regs.v'])
