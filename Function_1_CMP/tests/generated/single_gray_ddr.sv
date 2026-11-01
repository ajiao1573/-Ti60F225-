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
reg ac=0,pc=0;always #5.208333 ac=~ac;always #6.734007 pc=~pc;
reg reset=1,vs=0,pop=0;wire available;wire[7:0]pixel;wire[31:0]frame_id;
wire[31:0]ar;wire[7:0]alen;wire av,rr;
reg arready=0,rv=0,last=0;reg[127:0]data=0;
split_frame_ctrl #(.SINGLE_VIEW(1),.EDGE_LINES(477),.GRAY_LINES(238),.LETTERBOX_TOP(79),.COMPACT_BURSTS(1),.C_BUF_SIZE(23)) dut(
.axi_clk(ac),.axi_reset(reset),.axi_awready(1'b0),.axi_wready(1'b0),.axi_bresp(2'd0),.axi_bvalid(1'b0),
.axi_araddr(ar),.axi_arlen(alen),.axi_arvalid(av),.axi_arready(arready),
.axi_rvalid(rv),.axi_rdata(data),.axi_rresp(2'd0),.axi_rlast(last),.axi_rready(rr),
.wframe_pclk(pc),.wframe_eof(1'b0),.wframe_sof(1'b0),.gray_data_en(1'b0),.gray_data(8'd0),
.edge_data_en(1'b0),.edge_data(8'd0),.freeze_requested(1'b0),.history_requested(1'b0),.compare_requested(1'b0),
.replay_requested(3'd0),.left_requested(3'd0),.right_requested(3'd0),.overlay_requested(1'b0),
.rframe_pclk(pc),.rframe_vsync(vs),.rframe_data_en(pop),.rframe_data(pixel),.stream_available(available),.display_frame_id(frame_id));
integer rows=0,beat=0,row=0,limit=0,tokens=0,j;reg reading=0,taken=0;
reg[31:0]rng=32'h1ac459;
function [7:0] value;input integer x,y;begin value=(x*5+y*3)&255;end endfunction
always @(posedge ac)begin
 taken=rv&&rr;
 if(!reset)begin
  if(av&&arready)begin
   if(reading || alen!=63 || ar!=(rows<<11))$fatal(1,"single view mixed gray/padded/row address row%0d ar%h len%0d",rows,ar,alen);
   row<=rows;rows<=rows+1;beat<=0;limit<=alen;reading<=1;
  end
  if(taken)begin if(last)reading<=0;else beat<=beat+1;end
 end
end
always @(negedge ac)begin
 rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
 arready=!reset&&!reading&&rng[0];
 if(!rv||taken)begin
  rv=!reset&&reading&&rng[1];last=beat==limit;
  for(j=0;j<16;j=j+1)data[j*8+:8]=beat<53 ? value(beat*16+j,row):8'he7;
 end
end
reg[15:0]prng=16'hfac9;
always @(negedge pc)begin
 prng={prng[14:0],prng[15]^prng[13]^prng[12]^prng[10]};
 pop=!reset&&vs&&available&&prng[2:0]!=0;
end
always @(posedge pc)if(!reset&&pop)begin
 if(!available || pixel!==value(tokens%848,tokens/848))$fatal(1,"single stream token%0d got%0d expected%0d",tokens,pixel,value(tokens%848,tokens/848));
 if(frame_id!=7)$fatal(1,"display frame id did not follow selected generation %0d",frame_id);
 tokens=tokens+1;
end
initial begin
 repeat(8)@(negedge pc);reset=0;
 force dut.frame_available=1'b1;force dut.completed_generation=32'd7;force dut.latest_frame_index=3'd0;
 // Low sync holds the consumer; controller reset/reselection still runs.
 vs=1;repeat(8)@(negedge pc);vs=0;repeat(100)@(negedge pc);vs=1;
 wait(tokens==848*477);repeat(1000)@(negedge pc);
 if(tokens!=848*477 || rows!=477 || available)$fatal(1,"single view budget rows%0d tokens%0d avail%b",rows,tokens,available);
 $display("PASS SINGLE_VIEW DDR read:477 edge-plane rows,53 effective beats/row,404496 exact gray bytes,no thumbnail/padding leak,96MHz AXI/74.25MHz pixel stalls,display generation7");$finish;
end
initial begin #15000000;$fatal(1,"single DDR timeout rows%0d tokens%0d",rows,tokens);end
endmodule
