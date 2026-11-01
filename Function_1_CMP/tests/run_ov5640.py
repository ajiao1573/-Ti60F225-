"""OV5640 SCCB bus-level regression, no sensor or DDR hardware required."""
from run_canny import simulate
simulate('ov5640_sccb',r"""
`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;wire scl,sdo,oe,pwdn,resetb,ready,failed;
 wire [15:0] id;wire [8:0] index;
 tri1 sda;reg slave_low=0;
 assign sda=oe ? sdo : 1'bz;
 assign sda=slave_low ? 1'b0 : 1'bz;
 ov5640_init #(.CLOCK_HZ(400000),.BUS_HZ(50000)) dut(
 .clk(clk),.rst_n(rst),.sda_i(sda),.scl(scl),.sda_o(sdo),.sda_oe(oe),
 .pwdn(pwdn),.resetb(resetb),.configured(ready),.failed(failed),.chip_id(id),.config_index(index));
 integer pos=0,nb=0,starts=0,stops=0,writes=0,reads=0,nacks=0;
 reg active=0,rd=0,absent=0,bad_id=0,inject=1;
 reg [7:0] accum=0,bytes[0:3],reply=0,regs[0:65535];
 reg [15:0] addr=0;real reset_stop=0;
 always @(negedge sda) if(scl && rst) begin
  active=1;pos=0;nb=0;rd=0;starts=starts+1;
  if(reset_stop!=0 && $realtime-reset_stop<20000) $fatal(1,"soft-reset wait too short");
 end
 always @(posedge sda) if(scl && rst) begin active=0;stops=stops+1;end
 always @(posedge scl) if(active && rst) begin
  if(!rd) begin
   if(pos<8) begin accum={accum[6:0],sda};pos=pos+1;end
   else begin
    bytes[nb]=accum;nb=nb+1;pos=0;
    if(nb==1 && accum!=8'h78 && accum!=8'h79) $fatal(1,"wrong address %h",accum);
    if(nb==1 && accum==8'h79) begin
     rd=1;reply=bad_id ? 8'hff : addr==16'h300a ? 8'h56 : 8'h40;reads=reads+1;
    end
    if(nb==3) addr={bytes[1],bytes[2]};
    if(nb==4) begin
     if(!sda) begin regs[addr]=accum;writes=writes+1;end
     if(addr==16'h3008 && accum==8'h82) reset_stop=$realtime;
    end
   end
  end else begin
   pos=pos+1;
   if(pos==9) begin if(sda!==1'b1) $fatal(1,"missing master NACK");rd=0;pos=0;nb=0;end
  end
 end
 always @(negedge scl) begin
  slave_low=0;
  if(active && !absent) begin
   if(rd && pos<8) slave_low=!reply[7-pos];
   else if(!rd && pos==8) begin
    // Reject the DATA byte of one register. It must be retried, not skipped.
    if(inject && nb==3 && addr==16'h3630) begin inject=0;nacks=nacks+1;end
    else slave_low=1;
   end
  end
 end
 integer cycles=0;
 always @(posedge clk) begin
  cycles=cycles+1;
  if(cycles>2500000) $fatal(1,"timeout state=%d index=%d",dut.state,index);
  if(oe && sdo!==0) $fatal(1,"SDA must be open drain");
 end
 initial begin
  repeat(4) @(negedge clk);rst=1;
  wait(!pwdn);if(cycles<400000 || resetb) $fatal(1,"PWDN timing");
  wait(resetb);if(cycles<400800) $fatal(1,"RESETB timing");
  wait(ready || failed);
  if(failed || id!=16'h5640 || nacks!=1 || writes!=268 || reads!=2)
   $fatal(1,"init ready=%b fail=%b id=%h writes=%d reads=%d nacks=%d",ready,failed,id,writes,reads,nacks);
  if({regs[16'h3808],regs[16'h3809]}!=1920 || {regs[16'h380a],regs[16'h380b]}!=1080) $fatal(1,"size");
  if({regs[16'h380c],regs[16'h380d]}!=2500 || {regs[16'h380e],regs[16'h380f]}!=1120) $fatal(1,"frame timing");
  if(regs[16'h3820]!=8'h46 || regs[16'h3821]!=8'h00) $fatal(1,"upright non-mirrored camera orientation not configured");
  if(regs[16'h4740]!=8'h20) $fatal(1,"DVP polarity must match high VS/HREF, rising PCLK");
  if(regs[16'h4300]!=0 || regs[16'h501f]!=3 || regs[16'h3008]!=2) $fatal(1,"RAW/run mode");
  reset_stop=0;
  @(negedge clk);rst=0;slave_low=0;active=0;bad_id=1;
  repeat(4) @(negedge clk);rst=1;
  wait(failed);if(ready || id!=16'hffff) $fatal(1,"wrong ID accepted");
  @(negedge clk);rst=0;slave_low=0;active=0;bad_id=0;absent=1;
  repeat(4) @(negedge clk);rst=1;
  wait(failed);if(ready) $fatal(1,"absent camera accepted");
  // A camera becoming ready after the first attempts must recover without FPGA reset.
  absent=0;bad_id=0;reset_stop=0;
  wait(ready);if(failed || id!=16'h5640 || writes!=536) $fatal(1,"automatic recovery failed");
  $display("PASS SCCB: chip ID, 268 writes, data-byte NACK retry, reset delays, wrong ID, absent-camera failures, 1s boot wait and automatic recovery");$finish;
 end
endmodule
""",['src/cmos_i2c/ov5640_sccb_master.v','src/cmos_i2c/ov5640_init.v','src/cmos_i2c/ov5640_1080p30_regs.v'])
