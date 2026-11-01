"""Full-size DDR/color regression, using asynchronous behavioral FIFO models."""
from pathlib import Path
from run_canny import simulate
import subprocess,sys

base=Path('tests/tb_split_frame_ctrl.sv').read_text()
models=r'''
module W0_FIFO_32(input wr_clk_i,wr_en_i,input [31:0] wdata,input a_rst_i,
 input rd_clk_i,rd_en_i,output [127:0] rdata,output empty_o,output [9:0] rd_datacount_o);
 reg [31:0] mem[0:2047];integer wp=0,rp=0;
 assign empty_o=(wp-rp)<4;assign rd_datacount_o=(wp-rp)/4;
 genvar b;generate for(b=0;b<4;b=b+1) begin
  assign rdata[b*32+:32]=mem[(rp+b)%2048];
 end endgenerate
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>=2048) $fatal(1,"RGB capture FIFO overflow");mem[wp%2048]=wdata;wp=wp+1;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i) begin
   if(wp-rp<4) $fatal(1,"RGB capture FIFO underflow");rp<=rp+4;
  end
endmodule
module R0_FIFO_32(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,
 output prog_full_o,input rd_clk_i,rd_en_i,output [31:0] rdata,output empty_o);
 reg [31:0] mem[0:2047];integer wp=0,rp=0,j;
 assign prog_full_o=wp-rp>=512;assign empty_o=wp==rp;
 assign rdata=mem[rp%2048];
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>2044) $fatal(1,"RGB display FIFO overflow");
   for(j=0;j<4;j=j+1) mem[(wp+j)%2048]=wdata[32*j+:32];wp=wp+4;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i) begin
   if(empty_o) $fatal(1,"RGB display FIFO underflow");rp<=rp+1;
  end
endmodule
'''
s=base[:base.index('module tb;')]+models+base[base.index('module tb;'):]
def edit(a,b):
 global s
 assert a in s,a
 s=s.replace(a,b)
edit('split_frame_ctrl dut(', 'split_frame_ctrl #(.COMPACT_BURSTS(1),.COLOR_ENABLE(1),.C_BUF_SIZE(23)) dut(')
edit('cycle>3000000','cycle>10000000')
edit('wire ready;', '''reg rv=0,lv=0,left_pixel=0,requested=0;reg [23:0] rgb=0;wire mode;wire [23:0] output_rgb;
 integer write_limit,read_limit,write_beats=0;
 reg [127:0] ddr_mem[0:524287];reg [31:0] read_addr;
 function [23:0] color;
 input integer yy,xx;
 begin color={8'((yy+xx+13)&255),8'((yy*3+xx+47)&255),8'((yy+xx*5+81)&255)};end
 endfunction
 function [7:0] edge_pixel;
 input integer yy,xx;begin edge_pixel=((yy+xx)%11==0)?255:0;end
 endfunction
 wire ready;''')
edit('.gray_data_en(gv)', '.left_rgb_data_en(lv),.left_rgb_data(rgb),.rframe_left(left_pixel),.rgb_data_en(rv),.rgb_data(rgb),.overlay_requested(requested),.display_overlay(mode),.rframe_rgb(output_rgb),\n  .gray_data_en(gv)')
edit('if(awlen!=127 || awaddr[10:0]!=0)', 'if(awlen!=(awaddr[22] ? (awaddr[11] ? 95 : 127) : awaddr[21] ? (awaddr[20] ? 111 : 31) : 63) || awaddr[10:0]!=0)')
edit('writing<=1;addr<=awaddr;beat<=0;', 'writing<=1;addr<=awaddr;beat<=0;write_limit<=awlen;')
edit('wlast!==(beat==127)', 'wlast!==(beat==write_limit)')
edit('if(wvalid && wready) begin', 'if(wvalid && wready) begin\n    write_beats<=write_beats+1;')
start=s.index('    isgray=addr[21];')
end=s.index('    if(wlast) begin',start)
s=s[:start]+r'''
    ddr_mem[(addr>>4)+beat]<=wdata;
    if(addr[22]) begin
     row=(addr & 32'h3fffff)>>12;
     for(j=0;j<4;j=j+1) begin
      byte_x=(addr[11]?512:0)+beat*4+j;
      if(byte_x<848) begin
       if(wdata[j*32+:32] !== {8'd0,color(row,byte_x)})
        $fatal(1,"RGB write mismatch row=%0d x=%0d",row,byte_x);
      end else if(wdata[j*32+:32]!==0) $fatal(1,"RGB padding");
     end
    end else if(addr[21] && addr[20]) begin
     row=(addr & 32'hfffff)>>11;
     for(j=0;j<4;j=j+1) begin
      byte_x=beat*4+j;
      if(byte_x<424) begin
       if(wdata[j*32+:32] !== {8'd0,color(row*2,byte_x*2)})
        $fatal(1,"left RGB write mismatch row=%0d x=%0d",row,byte_x);
      end else if(wdata[j*32+:32]!==0) $fatal(1,"left RGB padding");
     end
    end else begin
     isgray=addr[21];row=(addr & 32'h1fffff)>>11;
     for(j=0;j<16;j=j+1) begin
      byte_x=beat*16+j;
      if(byte_x<(isgray?432:848)) begin
       if(wdata[j*8+:8] !== (isgray ? 8'((row+byte_x+17)&255) : edge_pixel(row,byte_x)))
        $fatal(1,"plane write mismatch addr=%h beat=%0d byte=%0d",addr,beat,j);
      end else if(wdata[j*8+:8]!==0) $fatal(1,"nonzero padding");
     end
    end
''' +s[end:]
edit('if(isgray) gray_rows<=gray_rows+1;else edge_rows<=edge_rows+1;', 'if(!addr[22] && !(addr[21] && addr[20])) begin if(isgray) gray_rows<=gray_rows+1;else edge_rows<=edge_rows+1;end')
edit('rows==954','rows==2544')
edit('reading<=1;readbeat<=0;delay_r<=20;', 'reading<=1;readbeat<=0;delay_r<=20;read_addr<=araddr;read_limit<=arlen;')
edit('rlast=readbeat==127','rlast=readbeat==read_limit')
edit("rdata={16{8'hff}};", 'rdata=ddr_mem[(read_addr>>4)+readbeat];')
edit(' integer x,y;', r'''
 integer xx,yy;reg [7:0] expected;reg [23:0] expected_rgb;
 task refresh;
 begin
  @(negedge dc);display_en=0;vs=1;repeat(8) @(negedge dc);vs=0;
  repeat(2000) @(negedge dc);
 end
 endtask
 task show_frame;
 input overlay;
 begin
  for(yy=42;yy<=677;yy=yy+1) begin
   for(xx=0;xx<1280;xx=xx+1) begin
    @(negedge dc);
    if(mode!==overlay) $fatal(1,"mode changed during active frame");
    left_pixel=yy>=201 && yy<=518 && xx<424;
    display_en=overlay ? (left_pixel || xx>=432) :
                  ((yy>=201 && yy<=518) || xx>=432);
    #1;
    if(display_en) begin
     if(overlay) begin
      expected_rgb=left_pixel ? color(2*(yy-201),2*xx) :
         edge_pixel(yy-42,xx-432) ? 24'hff0000 : color(yy-42,xx-432);
      if(output_rgb!==expected_rgb) $fatal(1,"overlay mismatch y=%0d x=%0d got=%h expected=%h",yy,xx,output_rgb,expected_rgb);
     end else begin
      if(xx<432) expected=8'((yy-201+xx+17)&255);
      else expected=edge_pixel(yy-42,xx-432);
      if(pixel!==expected) $fatal(1,"split mismatch y=%0d x=%0d got=%h expected=%h",yy,xx,pixel,expected);
     end
    end
    // Request opposite mode mid-frame; it must wait until vertical blank.
    if(yy==300 && xx==500) requested=!overlay;
   end
   @(negedge dc);display_en=0;repeat(370) @(negedge dc);
  end
 end
 endtask
 integer x,y;''')
edit('  for(y=0;y<318;y=y+1) begin', '''  // Classification overlaps RGB capture after ten lines.
  for(y=0;y<636;y=y+1) begin
   for(x=0;x<848;x=x+1) begin
    @(negedge pc);rv=1;lv=!y[0] && !x[0];rgb=color(y,x);
    gv=(y>=10 && !y[0] && !x[0]);gd=((y-10)/2+x/2+17)&255;
   end
   @(negedge pc);rv=0;lv=0;gv=0;
   if(y>=10 && !y[0]) begin
    for(x=424;x<432;x=x+1) begin @(negedge pc);gv=1;gd=((y-10)/2+x+17)&255;end
    @(negedge pc);gv=0;
   end
   repeat(500) @(negedge pc);
  end
  for(y=313;y<318;y=y+1) begin''')
edit('ed=(y+x+93)&255;', 'ed=edge_pixel(y,x);')
tail=s.index('  $display("PASS DDR:')
s=s[:tail]+r'''
  refresh;show_frame(0);
  refresh;show_frame(1);
  refresh;show_frame(0);
  if(display_count!=1) $fatal(1,"mode change counted as new image");
  @(negedge dc);reset=1;repeat(8) @(negedge dc);reset=0;
  if(mode!==0) $fatal(1,"reset did not restore split mode");
  if(write_beats!=228960) $fatal(1,"write traffic mismatch %0d",write_beats);
  $display("PASS color DDR: 2544 variable-length bursts, 228960 data beats, left original RGB + right overlay, full 848x636 alignment, split-overlay-split, stalled AXI restart, final-B commit, reset");$finish;
 end
endmodule
'''
name='color_overlay'
if '--single' in sys.argv:
 s=s.replace('.COLOR_ENABLE(1)', '.COLOR_ENABLE(1),.OVERLAY_SINGLE(1)')
 s=s.replace('left_pixel=yy>=201 && yy<=518 && xx<424;', 'left_pixel=0;')
 s=s.replace('display_en=overlay ? (left_pixel || xx>=432)', 'display_en=overlay ? (xx>=216 && xx<1064)')
 s=s.replace('edge_pixel(yy-42,xx-432) ? 24\'hff0000 : color(yy-42,xx-432)', 'edge_pixel(yy-42,xx-216) ? 24\'hff0000 : color(yy-42,xx-216)')
 s=s.replace('left original RGB + right overlay', 'centered camera RGB with red edges')
 name='color_single'
if '--streaming' in sys.argv:
 # Local linking emits edges while gray and RGB are still being captured.
 s=s.replace('gv=(y>=10 && !y[0] && !x[0]);gd=((y-10)/2+x/2+17)&255;',
             'gv=(y>=10 && !y[0] && !x[0]);gd=((y-10)/2+x/2+17)&255;ev=(y>=12);ed=edge_pixel(y-12,x);')
 s=s.replace('@(negedge pc);rv=0;lv=0;gv=0;', '@(negedge pc);rv=0;lv=0;gv=0;ev=0;')
 old='hold_final_b=1;\n  for(y=0;y<636;y=y+1) begin'
 assert old in s
 s=s.replace(old,'hold_final_b=1;\n  for(y=624;y<636;y=y+1) begin')
 s=s.replace('PASS color DDR:', 'PASS concurrent streaming gray/RGB/edge DDR:')
 name='color_single_streaming' if '--single' in sys.argv else 'color_streaming'
if '--raw-gray' in sys.argv:
 # Original luma is captured beside RGB, before all algorithm windows.
 s=s.replace('gv=(y>=10 && !y[0] && !x[0]);gd=((y-10)/2+x/2+17)&255;',
             'gv=(!y[0] && !x[0]);gd=(y/2+x/2+17)&255;')
 s=s.replace('if(y>=10 && !y[0])', 'if(!y[0])')
 s=s.replace('((y-10)/2+x+17)', '(y/2+x+17)')
 start=s.index('  for(y=313;y<318;y=y+1) begin')
 end=s.index('  // Arbitrarily long processing interval',start)
 s=s[:start]+s[end:]
 s=s.replace('PASS concurrent streaming gray/RGB/edge DDR:', 'PASS original gray + streaming camera RGB/edge DDR:')
 name='color_single_raw_streaming' if '--single' in sys.argv else 'color_split_raw_streaming'
if '--native-history' in sys.argv:
 # Exercise the production color writer with the additional packed history
 # and byte-wide native crops while all four camera planes overlap.
 s=s.replace('.COMPACT_BURSTS(1),', '.HISTORY_ENABLE(1),.HISTORY_COMPARE_NATIVE(1),.COMPACT_BURSTS(1),')
 s=s.replace('.gray_data_en(gv)', '''.freeze_requested(1'b0),.history_requested(1'b0),.compare_requested(1'b0),
  .replay_requested(3'd0),.left_requested(3'd0),.right_requested(3'd0),.gray_data_en(gv)''')
 s=s.replace('integer write_limit,read_limit,write_beats=0;', 'integer write_limit,read_limit,write_beats=0,packed_rows=0,crop_rows=0;')
 s=s.replace('if(awlen!=(awaddr[22]', "if(awlen!=(awaddr>=32'h02100000 ? 26 : awaddr>=32'h02000000 ? 6 : awaddr[22]")
 s=s.replace('|| awaddr[10:0]!=0)', "|| (awaddr>=32'h02100000 ? awaddr[8:0]!=0 : awaddr>=32'h02000000 ? awaddr[6:0]!=0 : awaddr[10:0]!=0))")
 start=s.index('    ddr_mem[(addr>>4)+beat]<=wdata;')
 end=s.index('    if(wlast) begin',start)
 s=s[:start]+r'''
    if(addr>=32'h02100000) begin
     row=(addr-32'h02100000)>>9;
     for(j=0;j<16;j=j+1) begin
      byte_x=16*beat+j;
      if(wdata[j*8+:8]!==((byte_x<424 && (edge_pixel(2*row,2*byte_x)!=0 || edge_pixel(2*row,2*byte_x+1)!=0 ||
          edge_pixel(2*row+1,2*byte_x)!=0 || edge_pixel(2*row+1,2*byte_x+1)!=0)) ? 8'hff : 8'd0))
       $fatal(1,"concurrent thumbnail write");
     end
    end else if(addr>=32'h02000000) begin
     row=(addr-32'h02000000)>>7;
     for(j=0;j<128;j=j+1) begin
      byte_x=128*beat+j;
      if(wdata[j] !== (byte_x<848 ? edge_pixel(row,byte_x)!=0 : 1'b0)) $fatal(1,"concurrent packed history write");
     end
    end else begin
''' +s[start:end]+'''    end
''' +s[end:]
 s=s.replace('if(!addr[22] &&', "if(addr>=32'h02100000) crop_rows<=crop_rows+1;\n     else if(addr>=32'h02000000) packed_rows<=packed_rows+1;\n     else if(!addr[22] &&")
 s=s.replace('rows==2544', 'rows==3498').replace('write_beats!=228960', 'write_beats!=241998')
 s=s.replace('  refresh;show_frame(0);', '''  if(packed_rows!=636 || crop_rows!=318 || dut.history_count!=1) $fatal(1,"native history complete-frame publication");
  refresh;show_frame(0);''',1)
 s=s.replace('2544 variable-length bursts, 228960 data beats', '3498 variable-length bursts, 241998 data beats, 636 packed history rows, 318 native thumbnail rows')
 name='color_native_capture'
try:
 simulate(name,s,['src/axi/split_frame_ctrl.v'],timeout=300)
except subprocess.CalledProcessError as error:
 print(error.stdout or '')
 raise
