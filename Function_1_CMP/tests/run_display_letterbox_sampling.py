"""Actual top capture phase and line-tail zeros at the real odd image height."""
from pathlib import Path
import re
from run_canny import simulate
s=Path('example_top.v').read_text(encoding='utf-8')
decl='\n'.join(re.search(r'wire\s+\[[^\]]+\]\s+'+n+r'\s*=.*?;',s,re.S).group(0) for n in ['roi_x','roi_y'])
a=s.index('wire gray_sample_en=');b=s.index('wire split_store_eof=',a)
fragment=s[a:b]
left=re.search(r'\.left_rgb_data_en\((.*?)\)',s).group(1)
tb=r'''`timescale 1ns/1ps
module tb;
 reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;
 reg rstn_sys=0,rgb_store_en=0;reg [10:0] full_view_x=0,full_view_y=0;
 reg [7:0] gray_data=0;
 integer x,y,count=0,leftcount=0,index,row,expected;
''' +decl+'\nwire left_take='+left+';\n'+fragment+r'''
 always @(posedge cmos_pclk) if(rstn_sys) begin
  if(left_take) leftcount=leftcount+1;
  if(gray_store_en) begin
   index=count%432;row=count/432;
   expected=index<424 ? ((2*index+3*(2*row+1))&255) : 0;
   if(gray_store_data!==8'(expected)) $fatal(1,"phase/padding sample %d got=%h expected=%h",count,gray_store_data,expected);
   count=count+1;
  end
 end
 initial begin
  repeat(5) @(negedge cmos_pclk);rstn_sys=1;
  for(y=0;y<477;y=y+1) begin
   for(x=0;x<848;x=x+1) begin
    @(negedge cmos_pclk);full_view_x=x;full_view_y=y;rgb_store_en=1;gray_data=(x+3*y)&255;
   end
   @(negedge cmos_pclk);rgb_store_en=0;repeat(12) @(negedge cmos_pclk);
  end
  if(count!=238*432 || leftcount!=238*424 || gray_pad_count!=0) $fatal(1,"238 row totals %d %d",count,leftcount);
  $display("PASS actual top reference capture: original odd-row sampling phase, 238 rows, 424 pixels + 8 zero pad per row, 477-row EOF");$finish;
 end
endmodule
'''
simulate('display_letterbox_sampling',tb,[],timeout=180)
