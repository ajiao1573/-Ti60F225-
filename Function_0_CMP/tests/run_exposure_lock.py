from run_canny import simulate
simulate('exposure_lock',r"""
`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;wire scl,sdo,oe,pwdn,resetb,ready,failed;
 wire [15:0] id;wire [8:0] index;
 tri1 sda;reg slave_low=0;
 assign sda=oe ? sdo : 1'bz;
 assign sda=slave_low ? 1'b0 : 1'bz;
 ov5640_init #(.CLOCK_HZ(400000),.BUS_HZ(50000),.STARTUP_MS(1),.LOCK_EXPOSURE(1),.AE_SETTLE_MS(10)) dut(
 .clk(clk),.rst_n(rst),.sda_i(sda),.scl(scl),.sda_o(sdo),.sda_oe(oe),
 .pwdn(pwdn),.resetb(resetb),.configured(ready),.failed(failed),.chip_id(id),.config_index(index));
 integer pos=0,nb=0,starts=0,stops=0,writes=0,reads=0,nacks=0;
 reg active=0,rd=0,absent=0,bad_id=0,inject=1;
 integer late_nack=0;reg ready_seen=0;
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
     rd=1;reply=addr==16'h300a ? 8'h56 : addr==16'h300b ? 8'h40 : regs[addr];if(bad_id && dut.operation==15) reply=0;reads=reads+1;
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
  if(active && !absent && !(late_nack!=0 && dut.operation==late_nack)) begin
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
  cycles=cycles+1; if(!rst) ready_seen=0; else begin if(ready_seen && !ready) $fatal(1,"late AE operation interrupted capture"); if(ready) ready_seen=1; end
  if(cycles>2500000) $fatal(1,"timeout state=%d index=%d",dut.state,index);
  if(oe && sdo!==0) $fatal(1,"SDA must be open drain");
 end

 task boot(input integer kind);
 begin
 @(negedge clk);rst=0;slave_low=0;active=0;reset_stop=0;cycles=0;
 writes=0;reads=0;inject=0;late_nack=kind==2 ? 12 : kind==3 ? 14 : kind==5 ? 13 : kind==6 ? 16 : 0;bad_id=kind==4;
 regs[16'h3500]=0;regs[16'h3501]=(kind==1 || kind==6 ? 0 : 8'h20);regs[16'h3502]=0;
 regs[16'h350a]=0;regs[16'h350b]=kind==7 ? 8'h08 : 8'h20;
 repeat(4) @(negedge clk);rst=1;
 wait(ready);wait(dut.state==9 && dut.lock_attempted);
 repeat(4) @(negedge clk);
 if(!ready || failed) $fatal(1,"capture disabled");
 if(kind==0) begin
 if(!dut.exposure_locked || dut.exposure_lock_failed || regs[16'h3503]!=3 || dut.locked_exposure!=20'h02000 || dut.locked_gain!=32 || writes!=269 || reads!=9)
 $fatal(1,"lock verification: locked=%b failed=%b exp=%h gain=%h writes=%d reads=%d",dut.exposure_locked,dut.exposure_lock_failed,dut.locked_exposure,dut.locked_gain,writes,reads);
 end else begin
 if(dut.exposure_locked || !dut.exposure_lock_failed || regs[16'h3503]!=(kind==6 ? 3 : 0)) $fatal(1,"automatic-mode fallback");
 end
 end
 endtask
 initial begin
 boot(0);boot(1);boot(2);boot(3);boot(4);boot(5);boot(6);boot(7);
 $display("PASS exposure lock: current values frozen and verified, invalid exposure/gain, lock/read/verify failures restore auto, rollback NACK preserves capture");$finish;
 end
endmodule
""",['src/cmos_i2c/ov5640_sccb_master.v','src/cmos_i2c/ov5640_init.v','src/cmos_i2c/ov5640_1080p30_regs.v'])
