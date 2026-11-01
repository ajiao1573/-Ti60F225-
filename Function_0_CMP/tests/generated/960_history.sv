`timescale 1ns/1ps
// Behavioral FIFOs are test doubles for the generated Efinix IP. They check
// over/underflow and retain the actual 8-to-128-bit packing convention.
module W0_FIFO_8(input wr_clk_i,wr_en_i,input [7:0] wdata,input a_rst_i,
 input rd_clk_i,rd_en_i,output [127:0] rdata,output prog_empty_o,empty_o,output [9:0] rd_datacount_o);
 reg [7:0] mem[0:8191];integer wp=0,rp=0,j;
 assign empty_o=(wp-rp)<16;assign prog_empty_o=(wp-rp)<=2032;
 assign rd_datacount_o=(wp-rp)/16;
 genvar b;generate for(b=0;b<16;b=b+1) begin
  assign rdata[b*8+:8]=mem[(rp+b)%8192];
 end endgenerate
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>=8192) $fatal(1,"write fifo overflow");mem[wp%8192]=wdata;wp=wp+1;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i) begin
   if(wp-rp<16) $fatal(1,"write fifo underflow");rp<=rp+16;
  end
endmodule
module R0_FIFO_8(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,
 output prog_full_o,input rd_clk_i,rd_en_i,output [7:0] rdata,output empty_o,almost_empty_o);
 reg [7:0] mem[0:8191];integer wp=0,rp=0,j;
 assign prog_full_o=wp-rp>=4096;assign empty_o=wp==rp;assign almost_empty_o=wp-rp<16;
 assign rdata=mem[rp%8192];
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>8176) $fatal(1,"display fifo overflow");
   for(j=0;j<16;j=j+1) mem[(wp+j)%8192]=wdata[8*j+:8];wp=wp+16;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i && !empty_o) rp<=rp+1;
endmodule


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
    if(aw>=32'h02000000 && (awlen!=7 || aw[6:0]!=0)) $fatal(1,"history address/burst");
   end
   if(wv && wready) begin
    if(!writing || wl!=(wb==wlimit)) $fatal(1,"W protocol");
    if(wa>=32'h02000000) begin
     mem[(wa-32'h02000000)/16+wb]<=wd;
     slot=(wa-32'h02000000)>>17;row=(wa & 32'h1ffff)>>7;
     for(j=0;j<128;j=j+1) begin
      bitx=128*wb+j;
      if(wd[j] !== (bitx<960 ? edge_value(f,row,bitx) : 1'b0)) $fatal(1,"packed binary frame=%0d slot=%0d row=%0d x=%0d",f,slot,row,bitx);
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
   if(pixel !== (col>=960 ? 8'd0 : edge_value(expected_frame,line,col) ? 8'hff : 8'd0))
    $fatal(1,"history pixel frame=%0d y=%0d x=%0d actual=%h",expected_frame,line,col,pixel);
   de=1;@(negedge dc);
  end
 endtask
 integer beforewrites;
 initial begin
  repeat(10) @(negedge pc);reset=0;
  for(f=0;f<9;f=f+1) begin
   wait(ready);@(negedge pc);sof=1;@(negedge pc);sof=0;
   for(y=0;y<3;y=y+1) for(x=0;x<960;x=x+1) begin
    @(negedge pc);gv=1;gd=x+y;end
   @(negedge pc);gv=0;
   for(y=0;y<6;y=y+1) for(x=0;x<960;x=x+1) begin
    @(negedge pc);ev=1;ed=edge_value(f,y,x) ? 255 : 0;eof=(y==5 && x==959);
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
   for(x=0;x<960;x=x+1) take(1,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  replay=7;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<960;x=x+1) take(8,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  comp=1;boundary;repeat(800) @(negedge dc);
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<960;x=x+1) take(1,y,x);
   for(x=0;x<960;x=x+1) take(8,y,x);
   de=0;repeat(600) @(negedge dc);
  end
  freeze=0;repeat(50) @(negedge pc);if(ready) $fatal(1,"resume before history reader leaves");
  hist=0;boundary;wait(ready);
  if(count!=8) $fatal(1,"resume erased history");
  $display("PASS 8-slot packed binary DDR ring, wrap, delayed B freeze, no frozen writes, chronological replay, dual-frame row alignment, resume");$finish;
 end
endmodule
