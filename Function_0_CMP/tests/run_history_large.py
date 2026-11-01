"""Native DDR crops, stored-frame comparison, live preview and binary replay."""
from pathlib import Path
import ast, subprocess
from run_canny import simulate

fixture = ast.parse(Path('tests/run_history.py').read_text())
fixture.body = [n for n in fixture.body if not (isinstance(n,ast.Expr) and
 isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Name) and n.value.func.id=='simulate')]
context = {}; exec(compile(fixture,'tests/run_history.py','exec'),context)
tb, fifos = context['full'], context['fifos']
tb = tb.replace('.HISTORY_ENABLE(1),', '.HISTORY_ENABLE(1),.HISTORY_COMPARE_NATIVE(1),.FRAME_DEPTH(2),.FW(3),')
tb = tb.replace('((col+3*line+5*frame)%17)<7',
 'col==line+frame || col==430+frame || col==434+frame || line==250+frame || line==254+frame || ((col+3*line+5*frame)%97)==0 || (col==112 && line==84) || (col==735 && line==551)')
tb = tb.replace('f<1','f<2').replace('cycles>3000000','cycles>20000000')
tb = tb.replace('vs=0,de=0;', 'vs=0;wire de;').replace('de=0;', 'lcd_request=0;').replace('de=1;', 'lcd_request=1;')
top = Path('example_top.v').read_text(encoding='utf-8')
logic = top[top.index('    wire history_play_pixel='):top.index('    wire display_stream_request=')]
at = tb.index(' reg [127:0] mem')
tb = tb[:at]+'''
 wire display_history=dh,display_compare=dcmp;
 reg lcd_request=0;reg [11:0] lcd_xpos=0,lcd_ypos=0;
 integer live_id[0:3];reg [127:0] crop_mem[0:131071];
 integer checked=0,side,srcx,srcy,expected_frame,crop_rows=0;
'''+logic+'''
 assign de=lcd_request && (display_compare ? history_compare_take : history_play_pixel);
'''+tb[at:]
tb = tb.replace('if(aw>=32\'h02000000 && (awlen!=6 || aw[6:0]!=0))',
 '''if(aw<32'h02000000 && !aw[21]) live_id[aw>>22]=f;
    if(aw>=32'h02100000 && (awlen!=26 || aw[8:0]!=0)) $fatal(1,"thumbnail burst");
    if(aw>=32'h02000000 && aw<32'h02100000 && (awlen!=6 || aw[6:0]!=0))''')
tb = tb.replace("if(wa>=32'h02000000) begin", '''if(wa>=32'h02100000) begin
     crop_mem[(wa-32'h02100000)/16+wb]<=wd;
     row=((wa-32'h02100000) & 32'hfffff)>>9;
     for(j=0;j<16;j=j+1) begin
      bitx=16*wb+j;
      if(wd[j*8+:8] !== ((bitx<424 && (edge_value(f,2*row,2*bitx) || edge_value(f,2*row,2*bitx+1) ||
                          edge_value(f,2*row+1,2*bitx) || edge_value(f,2*row+1,2*bitx+1))) ? 8'hff : 8'd0))
       $fatal(1,"thumbnail frame=%0d row=%0d col=%0d",f,row,bitx);
     end
    end else if(wa>=32'h02000000) begin''')
tb = tb.replace("if(wa>=32'h02000000) history_rows<=history_rows+1;",
 "if(wa>=32'h02000000 && wa<32'h02100000) history_rows<=history_rows+1;\n     if(wa>=32'h02100000) crop_rows<=crop_rows+1;")
tb = tb.replace("rd=ra>=32'h02000000 ? mem[(ra-32'h02000000)/16+rb] : 0;", '''if(ra>=32'h02100000) rd=crop_mem[(ra-32'h02100000)/16+rb];
   else if(ra>=32'h02000000) rd=mem[(ra-32'h02000000)/16+rb];
   else for(j=0;j<16;j=j+1) rd[j*8+:8]=edge_value(live_id[ra>>22],(ra & 32'h1fffff)>>11,(ra & 2047)+16*rb+j) ? 8'hff : 8'd0;''')
at = tb.index(' integer beforewrites;')
tb = tb[:at]+r'''
 task pane_row;input integer lf,rf,yy;integer xx,cc,rr;
 begin
  for(xx=0;xx<1280;xx=xx+1) begin
   lcd_ypos=yy;lcd_xpos=xx;lcd_request=1;#1;
   if(history_compare_pixel) begin
    side=xx>=650;cc=xx-(side ? 650 : 206);rr=yy-201;
    expected_frame=side ? rf : lf;
    if(dut.rfifo_empty || pixel!==((edge_value(expected_frame,2*rr,2*cc) || edge_value(expected_frame,2*rr,2*cc+1) ||
        edge_value(expected_frame,2*rr+1,2*cc) || edge_value(expected_frame,2*rr+1,2*cc+1)) ? 8'hff : 8'd0))
     $fatal(1,"thumbnail pane frame=%0d y=%0d x=%0d got=%h",expected_frame,yy,xx,pixel);
    checked=checked+1;
   end
   @(negedge dc);
  end
  lcd_request=0;repeat(370) @(negedge dc);
 end endtask
''' + tb[at:]
cut = tb.index('  if(count!=1')
capture = tb[tb.index('  for(f=0;'):cut]
tb = tb[:cut]+r'''
  freeze=1;hist=1;comp=1;left=0;right=1;wait(frozen);boundary;
  if(count!=2 || history_rows!=1272 || crop_rows!=636) $fatal(1,"initial native commits");
  wait(dut.read_pending);boundary;
  force dut.rfifo_full=1;repeat(19) @(negedge ac);release dut.rfifo_full;
  repeat(2000) @(negedge dc);
  for(y=201;y<=518;y=y+1) pane_row(0,1,y);
  if(checked!=269664 || dut.history_output_line!=318 || dut.history_underflow_total!=0) $fatal(1,"initial native raster");
  // Changing pair selection never touches the stored frames or the camera.
  right=0;boundary;repeat(2000) @(negedge dc);pane_row(0,0,201);
  beforewrites=totalwrites;right=1;boundary;repeat(2000) @(negedge dc);
  if(totalwrites!=beforewrites || count!=2 || !frozen) $fatal(1,"comparison navigation captured");
  // Refreshing frames: leave freeze (display returns to live, as the top
  // gates the history display behind frozen), capture new frames into the
  // ring, then re-freeze keeps the newest batch.
  freeze=0;hist=0;boundary;repeat(200) @(negedge dc);
  if(frozen) $fatal(1,"unfreeze did not release");
''' + capture.replace('f=0;f<2','f=2;f<4')+r'''
  freeze=1;hist=1;wait(frozen);boundary;repeat(2000) @(negedge dc);
  if(count!=2 || history_rows!=2544 || crop_rows!=1272) $fatal(1,"refreshed native commits");
  checked=0;
  for(y=201;y<=518;y=y+1) pane_row(2,3,y);
  if(checked!=269664 || dut.history_underflow_total!=0) $fatal(1,"refreshed comparison raster");
  beforewrites=totalwrites;
  comp=0;replay=1;boundary;repeat(2000) @(negedge dc);
  for(y=84;y<=719;y=y+1) begin
   for(x=216;x<1064;x=x+1) begin
    lcd_ypos=y;lcd_xpos=x;lcd_request=1;#1;
    if(dut.rfifo_empty || pixel!==(edge_value(3,y-84,x-216) ? 8'hff : 8'd0)) $fatal(1,"native -> full replay");
    @(negedge dc);
   end
   lcd_request=0;repeat(800) @(negedge dc);
  end
  if(totalwrites!=beforewrites || !frozen) $fatal(1,"frozen data overwritten");
  $display("PASS thumbnail comparison: 2x269664 binary pixels, full frames at exact 2:1 OR pooling, no recapture on pair/compare entry, unfreeze refresh and re-freeze, AXI restart/backpressure, zero underflow, full 1:1 replay");$finish;
 end
endmodule
'''
try:
 simulate('history_large',fifos+tb,['src/axi/split_frame_ctrl.v'],timeout=360)
except subprocess.CalledProcessError as error:
 print(error.stdout or '')
 raise
