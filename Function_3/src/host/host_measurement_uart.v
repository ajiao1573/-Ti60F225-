`ifndef HOST_MEASUREMENT_UART_V
`define HOST_MEASUREMENT_UART_V
// One outstanding request. The desktop serial owner serializes all requests.
// Reserve a reply before executing any action; requests while TX is occupied
// are ignored. Status has one snapshot bank; ACKs use independent two-byte data.
// No image transfer or second 48-byte reply bank in measurement firmware.
module host_measurement_uart #(parameter CLOCK_HZ=96000000,BAUD=115200,APP_TASK=1)(
 input clk,rst_n,rx,output tx,input [383:0] status_payload,
 input command_ready,output reg command_valid,output reg [7:0] command_code,
 output reg [15:0] command_value,input image_ready,input [7:0] image_data);
 function [7:0] crc8;
  input [7:0] crc,value;integer k;reg [7:0] v;
  begin v=crc^value;for(k=0;k<8;k=k+1)v=v[7]?(v<<1)^8'h07:v<<1;crc8=v;end
 endfunction
 wire rv,re;wire [7:0] rd;wire byte_busy;
 reg byte_valid;reg [7:0] byte_data;
 host_uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) receiver(.clk(clk),.rst_n(rst_n),.rx(rx),.valid(rv),.error(re),.data(rd));
 host_uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) transmitter(.clk(clk),.rst_n(rst_n),.valid(byte_valid),.data(byte_data),.tx(tx),.busy(byte_busy));
 reg [2:0] ps;reg [7:0] seq,cmd,len,crc,first;reg [5:0] ri;
 localparam TIMEOUT=CLOCK_HZ/20,TW=$clog2(TIMEOUT+1);
 reg [TW-1:0] idle;
 reg active,is_status;reg [5:0] ti;reg [7:0] txseq,ackcmd,ackerror,txcrc;
 reg [383:0] held_status;
 reg [7:0] validation;
 wire available=!active && !byte_busy && !byte_valid;
 wire accepted=rv && ps==7 && rd==crc && available;
 // Storage is not reset: active gates use until a complete snapshot is captured.
 always @(posedge clk)if(rst_n && accepted && cmd==1 && validation==0)held_status<=status_payload;
 always @* begin
  validation=0;
  case(cmd)
   8'h01:if(len!=0)validation=1;
   8'h13:if(len!=1)validation=1;else if(first!=APP_TASK)validation=2;
   8'h20:if(APP_TASK!=1)validation=2;else if(len!=1 || first>1)validation=1;
   8'h21:if(APP_TASK!=3)validation=2;else if(len!=0)validation=1;else if(status_payload[2*8+:8]==2)validation=3;
   8'h22:if(APP_TASK!=3)validation=2;else if(len!=0)validation=1;
   default:validation=2;
  endcase
  if(validation==0 && cmd!=1 && !command_ready)validation=3;
 end
 reg [7:0] nextbyte;
 wire [5:0] last_index=is_status?6'd54:6'd8;
 always @* begin
  nextbyte=0;
  case(ti)
   0:nextbyte=8'ha5;1:nextbyte=8'h5a;2:nextbyte=1;3:nextbyte=txseq;
   4:nextbyte=is_status?8'h81:8'h80;5:nextbyte=is_status?48:2;
   default:if(ti==last_index)nextbyte=txcrc;
    else if(is_status)nextbyte=held_status[(ti-6)*8+:8];
    else nextbyte=ti==6?ackcmd:ackerror;
  endcase
 end
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin
  ps<=0;seq<=0;cmd<=0;len<=0;crc<=0;first<=0;ri<=0;idle<=0;
  active<=0;is_status<=0;ti<=0;txseq<=0;ackcmd<=0;ackerror<=0;txcrc<=0;
  byte_valid<=0;byte_data<=0;command_valid<=0;command_code<=0;command_value<=0;
 end else begin
  byte_valid<=0;command_valid<=0;
  if(active && !byte_busy && !byte_valid)begin
   byte_data<=nextbyte;byte_valid<=1;
   if(ti>=2 && ti<last_index)txcrc<=crc8(txcrc,nextbyte);
   if(ti==last_index)active<=0;else ti<=ti+1'b1;
  end
  if(ps==0 || rv)idle<=0;
  else if(idle==TIMEOUT-1)begin idle<=0;ps<=0;end
  else idle<=idle+1'b1;
  if(re)ps<=0;
  else if(rv)case(ps)
   0:if(rd==8'ha5)ps<=1;
   1:ps<=rd==8'h5a ? 2:rd==8'ha5 ? 1:0;
   2:if(rd==1)begin crc<=crc8(0,rd);ps<=3;end else ps<=rd==8'ha5 ? 1:0;
   3:begin seq<=rd;crc<=crc8(crc,rd);ps<=4;end
   4:begin cmd<=rd;crc<=crc8(crc,rd);ps<=5;end
   5:begin len<=rd;crc<=crc8(crc,rd);first<=0;ri<=0;ps<=rd>48?0:rd==0?7:6;end
   6:begin if(ri==0)first<=rd;crc<=crc8(crc,rd);if(ri==len-1)ps<=7;else ri<=ri+1'b1;end
   7:begin ps<=0;if(accepted)begin
    active<=1;is_status<=cmd==1 && validation==0;txseq<=seq;ti<=0;txcrc<=0;ackcmd<=cmd;ackerror<=validation;
    if(cmd!=1 && validation==0)begin command_valid<=1;command_code<=cmd;command_value<={8'd0,first};end
   end end
  endcase
 end
endmodule
`endif
