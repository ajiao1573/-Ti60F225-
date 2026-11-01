from pathlib import Path
from run_canny import simulate

fifos=Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
tb=r'''
module tb;
 reg ac=0,pc=0,dc=0;always #5.2 ac=~ac;always #5 pc=~pc;always #6.72 dc=~dc;
 reg reset=1,sof=0,eof=0,gv=0,ev=0,freeze=0,hist=0,comp=0,vs=0,de=0;
 reg [7:0] gd=0,ed=0;reg [2:0] replay=7,left=0,right=7;
 wire ready,frozen,dh,dcmp,rr;wire [3:0] count;
 wire [31:0] aw,ar;wire [7:0] awlen,arlen,pixel;wire av,wv,wl,rv;
 wire [127:0] wd;reg [127:0] rd=0;
 reg aready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
 split_frame_ctrl #(.HISTORY_ENABLE(1),.COMPACT_BURSTS(1),.EDGE_LINES(6),.GRAY_LINES(3)) dut(
 .axi_clk(ac),.axi_reset(reset),.axi_awaddr(aw),.axi_awlen(awlen),.axi_awvalid(av),.axi_awready(aready),
 .axi_wdata(wd),.axi_wvalid(wv),.axi_wready(wready),.axi_wlast(wl),.axi_bresp(2'd0),.axi_bvalid(bvalid),
 .axi_araddr(ar),.axi_arlen(arlen),.axi_arvalid(rv),.axi_arready(arready),.axi_rdata(rd),
 .axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rresp(2'd0),.axi_rready(rr),
 .wframe_pclk(pc),.wframe_sof(sof),.wframe_eof(eof),.capture_ready(ready),
 .gray_data_en(gv),.gray_data(gd),.edge_data_en(ev),.edge_data(ed),
 .freeze_requested(freeze),.history_requested(hist),.compare_requested(comp),
 .replay_requested(replay),.left_requested(left),.right_requested(right),
 .display_history(dh),.display_compare(dcmp),.frozen(frozen),.history_count(count),
 .overlay_requested(1'b0),.rframe_pclk(dc),.rframe_vsync(vs),.rframe_data_en(de),.rframe_data(pixel));
 reg [127:0] mem[0:65535];
 reg writing=0,reading=0,hold_b=0,r_taken=0;integer wb=0,rb=0,wlimit=0,rlimit=0,delay_b=0;
 reg [31:0] wa=0,ra=0;integer history_rows=0,totalwrites=0,cycles=0;
 reg [31:0] rng=32'h1972319;
 integer f=0,x,y,j,slot,row,bitx;
 function bit edge_value;input integer frame,line,col;
  begin edge_value=((col+3*line+5*frame)%17)<7;end
 endfunction
 always @(posedge ac) begin
  r_taken = rvalid && rr; cycles<=cycles+1;if(cycles>3000000) $fatal(1,"timeout");
  if(!reset) begin
   if(av && aready) begin
    if(writing || delay_b!=0) $fatal(1,"AW overlap");
    writing<=1;wa<=aw;wb<=0;wlimit<=awlen;
    if(aw>=32'h02000000 && (awlen!=6 || aw[6:0]!=0)) $fatal(1,"history address/burst");
   end
   if(wv && wready) begin
    if(!writing || wl!=(wb==wlimit)) $fatal(1,"W protocol");
    if(wa>=32'h02000000) begin
     mem[(wa-32'h02000000)/16+wb]<=wd;
     slot=(wa-32'h02000000)>>17;row=(wa & 32'h1ffff)>>7;
     for(j=0;j<128;j=j+1) begin
      bitx=128*wb+j;
      if(wd[j] !== (bitx<848 ? edge_value(f,row,bitx) : 1'b0)) $fatal(1,"packed binary frame=%0d slot=%0d row=%0d x=%0d",f,slot,row,bitx);
     end
    end
    if(wl) begin
     writing<=0;delay_b<=9;totalwrites<=totalwrites+1;
     if(wa>=32'h02000000) history_rows<=history_rows+1;
    end else wb<=wb+1;
   end
   if(delay_b!=0 && !(hold_b && history_rows==54)) delay_b<=delay_b-1;
   if(rv && arready) begin
    if(reading) $fatal(1,"AR overlap");
    reading<=1;ra<=ar;rb<=0;rlimit<=arlen;
   end
   if(rvalid && rr) begin
    if(!reading) $fatal(1,"R unsolicited");
    if(rlast) reading<=0;else rb<=rb+1;
   end
  end
 end
 always @(negedge ac) begin
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  aready=!reset && !writing && delay_b==0 && rng[0];wready=writing && rng[1];
  bvalid=delay_b==1 && !(hold_b && history_rows==54);
  arready=!reset && !reading && rng[2];
  if(!rvalid || r_taken) begin
   rvalid=reading && rng[3];rlast=rb==rlimit;
   rd=ra>=32'h02000000 ? mem[(ra-32'h02000000)/16+rb] : 0;
  end
 end
 task boundary;begin
  @(negedge dc);de=0;vs=1;repeat(8) @(negedge dc);vs=0;repeat(150) @(negedge dc);
 end endtask
 task take;input integer expected_frame,line,col;
  begin
   // Real display never waits; the test enforces prefetch availability.
   if(dut.rfifo_empty) $fatal(1,"display underflow");
   if(pixel !== (col>=848 ? 8'd0 : edge_value(expected_frame,line,col) ? 8'hff : 8'd0))
    $fatal(1,"history pixel frame=%0d y=%0d x=%0d actual=%h",expected_frame,line,col,pixel);
   de=1;@(negedge dc);
  end
 endtask
 integer beforewrites;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  for(f=0;f<9;f=f+1) begin
   wait(ready);@(negedge pc);sof=1;@(negedge pc);sof=0;
   for(y=0;y<3;y=y+1) for(x=0;x<432;x=x+1) begin
    @(negedge pc);gv=1;gd=x+y;end
   @(negedge pc);gv=0;
   for(y=0;y<6;y=y+1) for(x=0;x<848;x=x+1) begin
    @(negedge pc);ev=1;ed=edge_value(f,y,x) ? 255 : 0;eof=(y==5 && x==847);
    if(f==8 && y==3 && x==0) begin freeze=1;hold_b=1;end
   end
   @(negedge pc);ev=0;eof=0;
   if(f==8) begin
    wait(history_rows==54);repeat(50) @(negedge pc);
    if(frozen || ready) $fatal(1,"froze/published before final response");
    hold_b=0;wait(frozen);
   end else wait(ready);
  end
  if(count!=8 || dut.history_write_index!=1) $fatal(1,"ring depth/wrap");
  beforewrites=totalwrites;repeat(100) @(negedge pc);
  if(totalwrites!=beforewrites || ready) $fatal(1,"write while frozen");
  hist=1;replay=0;boundary;
  if(!dh || dcmp) $fatal(1,"playback mode latch");
  repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(1,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  replay=7;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(8,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  comp=1;boundary;repeat(800) @(negedge dc);
  for(y=0;y<3;y=y+1) begin
   for(x=0;x<432;x=x+1) take(1,2*y,2*x);
   for(x=0;x<432;x=x+1) take(8,2*y,2*x);
   de=0;repeat(600) @(negedge dc);
  end
  freeze=0;repeat(50) @(negedge pc);if(ready) $fatal(1,"resume before history reader leaves");
  hist=0;boundary;wait(ready);
  if(count!=8) $fatal(1,"resume erased history");
  $display("PASS 8-slot packed binary DDR ring, wrap, delayed B freeze, no frozen writes, chronological replay, dual-frame row alignment, resume");$finish;
 end
endmodule
'''
simulate('history',fifos+tb,['src/axi/split_frame_ctrl.v'])



# Non-power-of-two depth must wrap and preserve chronological numbering.
small=tb.replace('.HISTORY_ENABLE(1),', '.HISTORY_ENABLE(1),.FRAME_DEPTH(3),')
small=small.replace('reg [2:0] replay','reg [1:0] replay').replace('wire [3:0] count','wire [2:0] count')
small=small.replace('replay=7,left=0,right=7', 'replay=2,left=0,right=2')
small=small.replace('f<9', 'f<4').replace('f==8','f==3').replace('history_rows==54','history_rows==24')
small=small.replace('count!=8', 'count!=3').replace('replay=7;', 'replay=2;')
small=small.replace('take(8,', 'take(3,')
simulate('history_depth3',fifos+small,['src/axi/split_frame_ctrl.v'])

# Freeze requested after the first frame: no refill pass, capture stops
# immediately; resume and re-freeze refresh the stored frames.
cut=tb.index(' integer beforewrites;')
startup=tb[:cut]+r'''
 task capture_one;input integer ff;
 begin
  wait(ready);f=ff;@(negedge pc);sof=1;@(negedge pc);sof=0;
  for(y=0;y<3;y=y+1) for(x=0;x<432;x=x+1) begin
   @(negedge pc);gv=1;gd=x+y;end
  @(negedge pc);gv=0;
  for(y=0;y<6;y=y+1) for(x=0;x<848;x=x+1) begin
   @(negedge pc);ev=1;ed=edge_value(ff,y,x) ? 255 : 0;eof=y==5 && x==847;end
  @(negedge pc);ev=0;eof=0;
 end endtask
 integer beforewrites;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  capture_one(0);freeze=1;wait(frozen);
  if(count!=1 || dut.history_write_index!=1) $fatal(1,"immediate freeze commit");
  beforewrites=totalwrites;repeat(100) @(negedge pc);
  if(totalwrites!=beforewrites || ready) $fatal(1,"capture continued after freeze");
  hist=1;replay=0;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(0,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  freeze=0;hist=0;boundary;wait(ready);
  capture_one(1);capture_one(2);freeze=1;wait(frozen);
  if(count!=3) $fatal(1,"resume and re-freeze count");
  hist=1;replay=2;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) take(2,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  $display("PASS startup freeze stops capture immediately, stored-frame replay, resume, re-freeze");$finish;
 end
endmodule
'''
simulate('history_startup_freeze',fifos+startup,['src/axi/split_frame_ctrl.v'])

# Real 848x636 size, all 636 packed rows and every replay pixel.
full=tb.replace('.EDGE_LINES(6),.GRAY_LINES(3)', '.EDGE_LINES(636),.GRAY_LINES(318)')
full=full.replace('f<9', 'f<1').replace('y<3', 'y<318').replace('y<6', 'y<636')
cut=full.index('  if(count!=8')
full=full[:cut]+r'''
  if(count!=1 || history_rows!=636) $fatal(1,"full size commit");
  hist=1;freeze=1;replay=0;boundary;repeat(800) @(negedge dc);
  for(y=0;y<636;y=y+1) begin
   for(x=0;x<848;x=x+1) take(0,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  $display("PASS 848x636: all packed DDR rows and 539328 replay pixels");$finish;
 end
endmodule
'''
simulate('history_full',fifos+full,['src/axi/split_frame_ctrl.v'])
