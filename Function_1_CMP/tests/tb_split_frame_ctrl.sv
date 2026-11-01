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
 reg reset=1,sof=0,eof=0,gv=0,ev=0;reg [7:0] gd=0,ed=0;
 wire ready;wire [31:0] awaddr,araddr,tp;wire [7:0] awlen,arlen;wire awvalid,wvalid,wlast,arvalid;
 wire [127:0] wdata;wire [15:0] strb;reg awready=0,wready=0,bvalid=0,arready=0;
 reg [1:0] bresp=0;reg [127:0] rdata=0;reg rvalid=0,rlast=0;
 reg vs=0,display_en=0;wire [7:0] pixel;wire display_toggle;
 split_frame_ctrl dut(.axi_clk(ac),.axi_reset(reset),.axi_awaddr(awaddr),.axi_awlen(awlen),
  .axi_awvalid(awvalid),.axi_awready(awready),.axi_wdata(wdata),.axi_wstrb(strb),.axi_wlast(wlast),
  .axi_wvalid(wvalid),.axi_wready(wready),.axi_bid(4'd0),.axi_bresp(bresp),.axi_bvalid(bvalid),
  .axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
  .axi_rid(4'd0),.axi_rdata(rdata),.axi_rresp(2'd0),.axi_rlast(rlast),.axi_rvalid(rvalid),
  .wframe_pclk(pc),.wframe_sof(sof),.wframe_eof(eof),.capture_ready(ready),
  .gray_data_en(gv),.gray_data(gd),.edge_data_en(ev),.edge_data(ed),
  .rframe_pclk(dc),.rframe_vsync(vs),.rframe_data_en(display_en),.rframe_data(pixel),.tp_o(tp),
  .display_frame_toggle(display_toggle));
 integer display_count=0;reg last_display_toggle=0;
 always @(posedge ac) begin
  if(reset) begin display_count=0;last_display_toggle=0;end
  else if(last_display_toggle!=display_toggle) begin display_count=display_count+1;last_display_toggle=display_toggle;end
 end
 integer cycle=0,beat=0,rows=0,delay_b=0,j,row,byte_x,frame;
 integer edge_rows=0,gray_rows=0,readbeat=0,delay_r=0;
 reg writing=0,reading=0,isgray;reg [31:0] addr;
 reg hold_final_b=0;reg [31:0] random_state=32'h19723;
 reg old_ar_stall=0,old_aw_stall=0,old_w_stall=0;
 reg [31:0] old_ar,old_aw;reg [127:0] old_w;
 // Stall all channels independently. Data must remain stable until accepted.
 always @(posedge ac) begin
  cycle<=cycle+1;
  if(cycle>3000000) $fatal(1,"timeout");
  if(!reset) begin
   if(old_ar_stall && (!arvalid || araddr!==old_ar)) $fatal(1,"AR changed under stall");
   if(old_aw_stall && (!awvalid || awaddr!==old_aw)) $fatal(1,"AW changed under stall");
   if(old_w_stall && (!wvalid || wdata!==old_w)) $fatal(1,"W changed under stall");
   old_ar_stall<=arvalid&&!arready;old_ar<=araddr;
   old_aw_stall<=awvalid&&!awready;old_aw<=awaddr;
   old_w_stall<=wvalid&&!wready;old_w<=wdata;
   if(awvalid && awready) begin
    if(writing || delay_b!=0) $fatal(1,"overlapping writes");
    if(awlen!=127 || awaddr[10:0]!=0) $fatal(1,"bad burst");
    writing<=1;addr<=awaddr;beat<=0;
   end
   if(wvalid && wready) begin
    if(!writing || strb!==16'hffff || wlast!==(beat==127)) $fatal(1,"bad W protocol");
    isgray=addr[21];row=(addr & 32'h1fffff)>>11;
    for(j=0;j<16;j=j+1) begin
     byte_x=beat*16+j;
     if(byte_x<(isgray?432:848)) begin
      if(wdata[j*8+:8] !== ((row+byte_x+(isgray?17:93))&255))
       $fatal(1,"DDR pixel mismatch addr=%h beat=%0d byte=%0d",addr,beat,j);
     end else if(wdata[j*8+:8]!==0) $fatal(1,"nonzero line padding");
    end
    if(wlast) begin
     writing<=0;delay_b<=17;rows<=rows+1;
     if(isgray) gray_rows<=gray_rows+1;else edge_rows<=edge_rows+1;
    end else beat<=beat+1;
   end
   if(delay_b!=0 && !(hold_final_b && rows==954)) delay_b<=delay_b-1;
   if(arvalid && arready) begin
    if(reading) $fatal(1,"overlapping reads");reading<=1;readbeat<=0;delay_r<=20;
   end
   if(delay_r!=0) delay_r<=delay_r-1;
   if(rvalid) begin
    if(!reading) $fatal(1,"unsolicited R");
    if(rlast) reading<=0;else readbeat<=readbeat+1;
   end
  end
 end
 always @(negedge ac) begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  awready=!reset && !writing && delay_b==0 && random_state[1];
  wready=!reset && writing && random_state[2];
  bvalid=!reset && delay_b==1;
  arready=!reset && !reading && random_state[3];
  rvalid=!reset && reading && delay_r==0 && random_state[4];
  rlast=readbeat==127;rdata={16{8'hff}};
 end
 integer x,y;
 initial begin
  repeat(8) @(negedge pc);reset=0;wait(ready);
  @(negedge pc);sof=1;@(negedge pc);sof=0;
  if(ready) $fatal(1,"capture ready failed to clear");
  for(y=0;y<318;y=y+1) begin
   for(x=0;x<432;x=x+1) begin
    @(negedge pc);gv=1;gd=(y+x+17)&255;
    @(negedge pc);gv=0;
   end
   repeat(800) @(negedge pc);
  end
  // Arbitrarily long processing interval must not publish gray alone.
  repeat(1000) @(negedge pc);
  if(ready || dut.frame_available) $fatal(1,"premature publication");
  hold_final_b=1;
  for(y=0;y<636;y=y+1) begin
   for(x=0;x<848;x=x+1) begin
    @(negedge pc);ev=1;ed=(y+x+93)&255;eof=(y==635 && x==847);
    // Current 64-pixel engine emits a pixel/clock and two fetch bubbles.
    if(x%64==63 || x==847) begin
     @(negedge pc);ev=0;eof=0;
     @(negedge pc);
    end
   end
  end
  wait(rows==954);repeat(100) @(negedge pc);
  if(ready || dut.frame_available) $fatal(1,"published before final B response");
  hold_final_b=0;wait(ready);
  if(edge_rows!=636 || gray_rows!=318 || !dut.frame_available) $fatal(1,"row totals");
  if(display_count!=0) $fatal(1,"FPS counted commit before display selection");
  @(negedge dc);vs=1;repeat(5) @(negedge dc);vs=0;
  // Interrupt the display while a stalled response is outstanding.
  wait(reading);repeat(4) @(negedge dc);vs=1;
  repeat(5) @(negedge dc);vs=0;
  repeat(500) @(negedge dc);
  if(dut.restart_pending) $fatal(1,"read restart did not drain");
  if(display_count!=1) $fatal(1,"Repeated display frame counted more than once");
  $display("PASS DDR: 954 rows, async clocks, randomized stalls, delayed commit, display restart");$finish;
 end
endmodule
