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
 reg [31:0] mem[0:4095];integer wp=0,rp=0,j;
 assign prog_full_o=wp-rp>=1024;assign empty_o=wp==rp;
 assign rdata=mem[rp%4096];
 always @(posedge wr_clk_i or posedge a_rst_i)
  if(a_rst_i) wp=0;else if(wr_en_i) begin
   if(wp-rp>4092) $fatal(1,"RGB display FIFO overflow");
   for(j=0;j<4;j=j+1) mem[(wp+j)%4096]=wdata[32*j+:32];wp=wp+4;
  end
 always @(posedge rd_clk_i or posedge a_rst_i)
  if(a_rst_i) rp=0;else if(rd_en_i) begin
   if(empty_o) $fatal(1,"RGB display FIFO underflow");rp<=rp+1;
  end
endmodule

module tb;
 localparam H=12,F=1;
 reg ac=0,pc=0,dc=0;always #5.208333 ac=~ac;always #5.952381 pc=~pc;always #3.367003 dc=~dc;
 reg overlay=1,cv=0,left_pixel=0;reg[23:0] rgb=0;wire[23:0] output_rgb;wire[9:0] underflows;reg temporal=1,inject_read_error=0,inject_write_error=0;reg reset=1,sof=0,eof=0,gv=0,ev=0,freeze=0,hist=0,comp=0,vs=0,de=0;
 reg [7:0] gd=0,ed=0;reg [2:0] replay=7,left=0,right=7;
 wire ready,frozen,dh,dcmp,rr;wire [3:0] count;
 wire [31:0] aw,ar;wire [7:0] awlen,arlen,pixel;wire av,wv,wl,rv;
 wire [127:0] wd;reg [127:0] rd=0;
 reg aready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
 split_frame_ctrl #(.HISTORY_ENABLE(1),.TEMPORAL_ENABLE(1),.COLOR_ENABLE(1),.C_BUF_SIZE(23),.CONFIG_GUARD(1),.MOTION_PROTECT(1),.COMPACT_BURSTS(1),.EDGE_LINES(H),.GRAY_LINES(H)) dut(
 .axi_clk(ac),.axi_reset(reset),.axi_awaddr(aw),.axi_awlen(awlen),.axi_awvalid(av),.axi_awready(aready),
 .axi_wdata(wd),.axi_wvalid(wv),.axi_wready(wready),.axi_wlast(wl),.axi_bresp(inject_write_error && dut.wstate==15 ? 2'd2 : 2'd0),.axi_bvalid(bvalid),
 .axi_araddr(ar),.axi_arlen(arlen),.axi_arvalid(rv),.axi_arready(arready),.axi_rdata(rd),
 .axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rresp(inject_read_error && dut.reading_temporal ? 2'd2 : 2'd0),.axi_rready(rr),
 .wframe_pclk(pc),.wframe_sof(sof),.wframe_eof(eof),.capture_ready(ready),
 .gray_data_en(gv),.gray_data(gd),.edge_data_en(ev),.edge_data(ed),
 .temporal_requested(temporal),.edge_configuration(12'h001),.edge_protect(ed!=0),.freeze_requested(freeze),.history_requested(hist),.compare_requested(comp),
 .replay_requested(replay),.left_requested(left),.right_requested(right),
 .display_history(dh),.display_compare(dcmp),.frozen(frozen),.history_count(count),
 .rgb_data_en(cv),.rgb_data(rgb),.left_rgb_data_en(1'b0),.left_rgb_data(24'd0),.rframe_left(left_pixel),.rframe_rgb(output_rgb),.overlay_requested(overlay),.display_underflow_total(underflows),.rframe_pclk(dc),.rframe_vsync(vs),.rframe_data_en(de),.rframe_data(pixel));
 reg [127:0] mem[0:65535];reg [127:0] live[0:2097151];
 reg writing=0,reading=0,hold_b=0,r_taken=0;integer wb=0,rb=0,wlimit=0,rlimit=0,delay_b=0;
 reg [31:0] wa=0,ra=0;integer history_rows=0,totalwrites=0,cycles=0,temporal_reads=0;
 reg [31:0] rng=32'h1972319;
 integer f=0,x,y,j,slot,row,bitx;
 function bit edge_value;input integer frame,line,col;
  begin edge_value=(((col+line+frame/3)%8)>>(frame%3))&1;end
 endfunction
 always @(posedge ac) begin
  r_taken = rvalid && rr; cycles<=cycles+1;if(cycles>24000000) $fatal(1,"timeout");
  if(!reset) begin
   if(av && aready) begin
    if(writing || delay_b!=0) $fatal(1,"AW overlap");
    writing<=1;wa<=aw;wb<=0;wlimit<=awlen;
    if(aw>=32'h02000000 && (awlen!=7 || aw[6:0]!=0)) $fatal(1,"history address/burst");
   end
   if(wv && wready) begin
    if(!writing || wl!=(wb==wlimit)) $fatal(1,"W protocol");
    if(wa<32'h02000000) live[wa/16+wb]<=wd;
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
    if(dut.reading_temporal) begin
     if(arlen!=7 || ar[6:0]!=0) $fatal(1,"temporal burst layout");
     if(((ar-32'h02000000)>>17)==dut.history_write_index) $fatal(1,"uncommitted frame read");
     temporal_reads<=temporal_reads+1;
    end
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
   rvalid=reading && rng[3] && rng[4];rlast=rb==rlimit;
   rd=ra>=32'h02000000 ? mem[(ra-32'h02000000)/16+rb] : live[ra/16+rb];
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


 function [23:0] color;input integer ff,line,col;
 begin color={8'(ff+1),8'(line+17),8'(col+31)};end endfunction
 task capture;input integer ff;
 integer xx,yy;
 begin
  f=ff;
  if(!ready) $fatal(1,"dropped camera SOP frame %0d",ff);
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<1600;xx=xx+1) begin
    sof=yy==0 && xx==0;gv=xx<960;ev=gv;cv=gv;
    eof=yy==H-1 && xx==959;gd=8'(yy+xx+17);
    ed=edge_value(ff,yy,xx) ? 255:0;rgb=color(ff,yy,xx);
    @(negedge pc);
   end
  end
  gv=0;ev=0;cv=0;sof=0;eof=0;
  repeat(6000) @(negedge pc);
  if(dut.completed_generation!=ff+1) $fatal(1,"frame not committed before next 60Hz SOP %0d",ff);
 end endtask

 integer rgb_reads=0,old_reads,xx,yy,k;reg mode;reg [23:0] expected_rgb;reg [7:0] expected_gray;
 always @(posedge ac) if(rv && arready && ar<32'h02000000 && ar[22]) rgb_reads=rgb_reads+1;
 task show;input color_mode;
 begin
  overlay=color_mode;old_reads=rgb_reads;boundary;
  repeat(6000) @(negedge dc);
  for(yy=0;yy<H;yy=yy+1) begin
   for(xx=0;xx<1920;xx=xx+1) begin
    left_pixel=xx<960;de=1;#0.1;
    if(dut.display_overlay!==color_mode) $fatal(1,"mode changed during visible frame");
    if(color_mode) begin
     expected_rgb=left_pixel ? color(0,yy,xx) : edge_value(0,yy,xx-960) ? 24'hff0000 : color(0,yy,xx-960);
     if(output_rgb!==expected_rgb) $fatal(1,"RGB mode transition y%0d x%0d actual%h expected%h",yy,xx,output_rgb,expected_rgb);
    end else begin
     expected_gray=left_pixel ? 8'(yy+xx+17) : edge_value(0,yy,xx-960) ? 255:0;
     if(pixel!==expected_gray) $fatal(1,"gray mode transition y%0d x%0d actual%h expected%h",yy,xx,pixel,expected_gray);
    end
    if(yy==2 && xx==500) overlay=!color_mode;
    @(negedge dc);
   end
   de=0;repeat(280) @(negedge dc);
  end
  if(color_mode && rgb_reads-old_reads!=2*H) $fatal(1,"RGB row read more than once: bursts%0d",rgb_reads-old_reads);
  if(underflows!=0) $fatal(1,"display underflow %0d",underflows);
 end endtask
 initial begin
  repeat(10) @(negedge pc);reset=0;repeat(100) @(negedge pc);capture(0);
  freeze=1;wait(frozen);
  for(k=0;k<4;k=k+1) begin show(0);show(1);end
  $display("PASS 96MHz DDR, 148.5MHz HDMI: 8 gray/color transitions, exact RGB888 and red-edge pixels, one RGB read per row, 25%% read duty, zero underflow");$finish;
 end
endmodule
