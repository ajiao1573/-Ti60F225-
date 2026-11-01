// Register transaction master. SDA is open drain; SCL uses the existing output pad.
// Read address phase ends with STOP, then a new START for the read byte.
module ov5640_sccb_master #(parameter CLOCK_HZ=96000000, BUS_HZ=100000)(
 input clk,rst_n,start,read_en,input [15:0] address,input [7:0] write_data,
 input sda_i,output reg scl,output wire sda_o,sda_oe,
 output reg busy,done,error,output reg [7:0] read_data
);
localparam DIV=(CLOCK_HZ/(BUS_HZ*4)<1)?1:CLOCK_HZ/(BUS_HZ*4);
localparam IDLE=0,START_A=1,START_B=2,START_C=3,SEND=4,ACK=5,
 STOP_A=6,STOP_B=7,STOP_C=8,RECV=9,NACK=10,FINISH=11;
reg [3:0] state;
reg [31:0] divider;
reg [1:0] phase,byte_index;
reg [2:0] bit_index;
reg [7:0] tx;
reg [15:0] addr_latched;
reg [7:0] data_latched;
reg reading,read_phase,drive_low;
assign sda_o=1'b0;
assign sda_oe=drive_low;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  state<=IDLE;divider<=0;phase<=0;byte_index<=0;bit_index<=7;
  tx<=0;addr_latched<=0;data_latched<=0;reading<=0;read_phase<=0;
  drive_low<=0;scl<=1;busy<=0;done<=0;error<=0;read_data<=0;
 end else begin
  done<=0;
  if(state==IDLE) begin
   divider<=0;scl<=1;drive_low<=0;
   if(start) begin
    busy<=1;error<=0;reading<=read_en;read_phase<=0;
    addr_latched<=address;data_latched<=write_data;
    tx<=8'h78;byte_index<=0;bit_index<=7;phase<=0;state<=START_A;
   end
  end else if(divider==DIV-1) begin
   divider<=0;
   case(state)
    START_A: begin scl<=1;drive_low<=0;state<=START_B;end
    START_B: begin drive_low<=1;state<=START_C;end
    START_C: begin scl<=0;phase<=0;state<=SEND;end
    SEND: case(phase)
     0: begin scl<=0;drive_low<=!tx[bit_index];phase<=1;end
     1: begin scl<=1;phase<=2;end
     2: phase<=3;
     3: begin
      scl<=0;phase<=0;
      if(bit_index==0) state<=ACK;else bit_index<=bit_index-1'b1;
     end
    endcase
    ACK: case(phase)
     0: begin drive_low<=0;phase<=1;end
     1: begin scl<=1;phase<=2;end
     2: begin if(sda_i) error<=1;phase<=3;end
     3: begin
      scl<=0;phase<=0;bit_index<=7;
      if(error) state<=STOP_A;
      else if(read_phase) begin read_data<=0;state<=RECV;end
      else if((reading && byte_index==2) || (!reading && byte_index==3)) state<=STOP_A;
      else begin
       byte_index<=byte_index+1'b1;
       case(byte_index)
        0: tx<=addr_latched[15:8];
        1: tx<=addr_latched[7:0];
        default: tx<=data_latched;
       endcase
       state<=SEND;
      end
     end
    endcase
    RECV: case(phase)
     0: begin drive_low<=0;phase<=1;end
     1: begin scl<=1;phase<=2;end
     2: begin read_data<={read_data[6:0],sda_i};phase<=3;end
     3: begin scl<=0;phase<=0;
      if(bit_index==0) state<=NACK;else bit_index<=bit_index-1'b1;
     end
    endcase
    NACK: case(phase)
     0: begin drive_low<=0;phase<=1;end
     1: begin scl<=1;phase<=2;end
     2: phase<=3;
     3: begin scl<=0;phase<=0;state<=STOP_A;end
    endcase
    STOP_A: begin scl<=0;drive_low<=1;state<=STOP_B;end
    STOP_B: begin scl<=1;state<=STOP_C;end
    STOP_C: begin drive_low<=0;state<=FINISH;end
    FINISH: begin
     if(reading && !read_phase && !error) begin
      read_phase<=1;tx<=8'h79;bit_index<=7;phase<=0;state<=START_A;
     end else begin busy<=0;done<=1;state<=IDLE;end
    end
    default: begin error<=1;state<=STOP_A;end
   endcase
  end else divider<=divider+1'b1;
 end
end
endmodule
