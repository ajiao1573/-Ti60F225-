// Power sequence, chip-ID check, full register initialization, bounded retries.
module ov5640_init #(parameter CLOCK_HZ=96000000,BUS_HZ=100000,STARTUP_MS=1000,RETRY_MS=1000,LOCK_EXPOSURE=0,AE_SETTLE_MS=2000)(
 input clk,rst_n,input sda_i,output scl,sda_o,sda_oe,
 output reg pwdn,resetb,output reg configured,failed,
 output reg [15:0] chip_id,output [8:0] config_index,
 output reg exposure_locked,exposure_lock_failed,
 output reg [19:0] locked_exposure,output reg [9:0] locked_gain
);
localparam MS=(CLOCK_HZ/1000<1)?1:CLOCK_HZ/1000;
localparam POWER=0,RELEASE=1,SETTLE=2,ID_HIGH=3,ID_LOW=4,WRITE=5,
 LAUNCH=6,WAIT_BUS=7,WAIT_DELAY=8,READY=9,FAULT=10,
 AE_WAIT=11,AE_CONTROL=12,AE_LOCK=13,AE_READ=14,AE_CHECK=15,AE_UNLOCK=16;
reg [4:0] state,operation;
reg lock_attempted;reg [2:0] ae_index;reg [7:0] ae_control;
reg [31:0] timer;
reg [8:0] index;
reg [1:0] retries;
reg start,read_en;
reg [15:0] address;
reg [7:0] write_data;
wire busy,done,error;
wire [7:0] read_data,reg_delay;
wire [23:0] reg_data;
wire [8:0] reg_count;
assign config_index=index;
ov5640_960x720_60_regs regs(index,reg_data,reg_delay,reg_count);
ov5640_sccb_master #(.CLOCK_HZ(CLOCK_HZ),.BUS_HZ(BUS_HZ)) bus(
 .clk(clk),.rst_n(rst_n),.start(start),.read_en(read_en),.address(address),
 .write_data(write_data),.sda_i(sda_i),.scl(scl),.sda_o(sda_o),.sda_oe(sda_oe),
 .busy(busy),.done(done),.error(error),.read_data(read_data));
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  state<=POWER;operation<=ID_HIGH;timer<=STARTUP_MS*MS-1;index<=0;retries<=0;
  start<=0;read_en<=0;address<=0;write_data<=0;
  pwdn<=1;resetb<=0;configured<=0;failed<=0;chip_id<=0;
  lock_attempted<=0;ae_index<=0;ae_control<=0;
  exposure_locked<=0;exposure_lock_failed<=0;locked_exposure<=0;locked_gain<=0;
 end else begin
  start<=0;
  case(state)
   POWER: if(timer!=0) timer<=timer-1'b1;
    else begin pwdn<=0;timer<=2*MS-1;state<=RELEASE;end
   RELEASE: if(timer!=0) timer<=timer-1'b1;
    else begin resetb<=1;timer<=21*MS-1;state<=SETTLE;end
   SETTLE: if(timer!=0) timer<=timer-1'b1;else state<=ID_HIGH;
   ID_HIGH,ID_LOW,WRITE: begin
    operation<=state;read_en<=state!=WRITE;
    address<=state==ID_HIGH ? 16'h300a : state==ID_LOW ? 16'h300b : reg_data[23:8];
    write_data<=reg_data[7:0];state<=LAUNCH;
   end
   LAUNCH: if(!busy) begin start<=1;state<=WAIT_BUS;end
   WAIT_BUS: if(done) begin
    if(error) begin
     if(retries==2) begin
      if(operation>=AE_CONTROL) begin
       // A late SCCB failure must not reset an in-flight image transaction.
       retries<=0;exposure_locked<=0;exposure_lock_failed<=1;
       state<=operation==AE_UNLOCK ? READY : AE_UNLOCK;
      end else begin state<=FAULT;timer<=RETRY_MS*MS-1;end
     end
     else begin retries<=retries+1'b1;state<=LAUNCH;end
    end else begin
     retries<=0;
     if(operation==ID_HIGH) begin chip_id[15:8]<=read_data;state<=ID_LOW;end
     else if(operation==ID_LOW) begin
      chip_id[7:0]<=read_data;
      if(chip_id[15:8]==8'h56 && read_data==8'h40) state<=WRITE;
      else begin state<=FAULT;timer<=RETRY_MS*MS-1;end
     end else if(operation==AE_CONTROL) begin ae_control<=read_data;state<=AE_LOCK;end
     else if(operation==AE_LOCK) begin ae_index<=0;state<=AE_READ;end
     else if(operation==AE_READ) begin
      case(ae_index)
       0:locked_exposure[19:16]<=read_data[3:0];
       1:locked_exposure[15:8]<=read_data;
       2:locked_exposure[7:0]<=read_data;
       3:locked_gain[9:8]<=read_data[1:0];
       4:locked_gain[7:0]<=read_data;
      endcase
      if(ae_index==4) state<=AE_CHECK;
      else begin ae_index<=ae_index+1'b1;state<=AE_READ;end
     end else if(operation==AE_CHECK) begin
      if(read_data[1:0]==3 && locked_exposure!=0 &&
         locked_exposure<=20'd17920 && locked_gain>=10'd16) begin
       exposure_locked<=1;exposure_lock_failed<=0;state<=READY;
      end else begin exposure_lock_failed<=1;state<=AE_UNLOCK;end
     end else if(operation==AE_UNLOCK) state<=READY;
     else begin timer<=reg_delay*MS;state<=WAIT_DELAY;end
    end
   end
   WAIT_DELAY: if(timer!=0) timer<=timer-1'b1;
    else if(index==reg_count-1'b1) state<=READY;
    else begin index<=index+1'b1;state<=WRITE;end
   READY: begin
    configured<=1;
    if(LOCK_EXPOSURE && !lock_attempted) begin
     lock_attempted<=1;timer<=AE_SETTLE_MS*MS;state<=AE_WAIT;
    end
   end
   AE_WAIT:if(timer!=0) timer<=timer-1'b1;else state<=AE_CONTROL;
   AE_CONTROL,AE_LOCK,AE_READ,AE_CHECK,AE_UNLOCK: begin
    operation<=state;
    read_en<=state==AE_CONTROL || state==AE_READ || state==AE_CHECK;
    address<=16'h3503;
    write_data<=state==AE_UNLOCK ? (ae_control & 8'hfc) : (ae_control | 8'h03);
    if(state==AE_READ) case(ae_index)
     0:address<=16'h3500;1:address<=16'h3501;2:address<=16'h3502;
     3:address<=16'h350a;4:address<=16'h350b;
    endcase
    state<=LAUNCH;
   end
   FAULT: begin
    failed<=1;configured<=0;
    if(timer!=0) timer<=timer-1'b1;
    else begin failed<=0;index<=0;retries<=0;chip_id<=0;lock_attempted<=0;exposure_locked<=0;exposure_lock_failed<=0;state<=ID_HIGH;end
   end
   default: state<=FAULT;
  endcase
 end
end
endmodule
