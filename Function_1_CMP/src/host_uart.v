`ifndef TI60_HOST_UART_V
`define TI60_HOST_UART_V
// 8N1 byte receiver. Synchronize the external pin and verify both framing bits.
module host_uart_rx #(parameter CLOCK_HZ=96000000,BAUD=115200)(
 input clk,rst_n,rx,output reg valid,output reg error,output reg [7:0] data
);
 localparam DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 localparam CW=$clog2(DIV+1);
 reg [1:0] sync;
 reg [1:0] state;
 reg [CW-1:0] timer;
 reg [2:0] bit_index;
 reg [7:0] work;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin sync<=3;state<=0;timer<=0;bit_index<=0;work<=0;data<=0;valid<=0;error<=0;end
  else begin
   sync<={sync[0],rx};valid<=0;error<=0;
   case(state)
    0:if(!sync[1]) begin state<=1;timer<=DIV/2-1;end
    1:if(timer!=0) timer<=timer-1'b1;
      else if(sync[1]) state<=0;
      else begin state<=2;timer<=DIV-1;bit_index<=0;end
    2:if(timer!=0) timer<=timer-1'b1;
      else begin
       work[bit_index]<=sync[1];timer<=DIV-1;
       if(bit_index==7) state<=3;else bit_index<=bit_index+1'b1;
      end
    3:if(timer!=0) timer<=timer-1'b1;
      else begin
       state<=0;
       if(sync[1]) begin data<=work;valid<=1;end else error<=1;
      end
   endcase
  end
 end
endmodule

module host_uart_tx #(parameter CLOCK_HZ=96000000,BAUD=115200)(
 input clk,rst_n,valid,input [7:0] data,output tx,output reg busy
);
 localparam DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 localparam CW=$clog2(DIV+1);
 reg [CW-1:0] timer;
 reg [3:0] bit_index;
 reg [9:0] shift;
 assign tx=busy ? shift[0]:1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin timer<=0;bit_index<=0;shift<=10'h3ff;busy<=0;end
  else if(!busy) begin
   if(valid) begin shift<={1'b1,data,1'b0};bit_index<=0;timer<=DIV-1;busy<=1;end
  end else if(timer!=0) timer<=timer-1'b1;
  else begin
   timer<=DIV-1;shift<={1'b1,shift[9:1]};
   if(bit_index==9) busy<=0;else bit_index<=bit_index+1'b1;
  end
 end
endmodule

// UART_PROTOCOL.md V1. One active reply plus one queued reply. Never execute a
// command unless its ACK has a reserved queue slot. Excess requests are ignored
// (host timeout/retry), rather than applying a write with no matching response.
module host_uart #(parameter CLOCK_HZ=96000000,BAUD=115200,CALIBRATION_ENABLE=0)(
 input clk,rst_n,rx,output tx,input [383:0] status_payload,
 input command_ready,output reg command_valid,output reg [7:0] command_code,
 output reg [15:0] command_value,
 output reg image_arm,output image_read,output [15:0] image_address,
 input image_ready,input [7:0] image_data
);
 function [7:0] crc8;
  input [7:0] crc,value;integer k;reg [7:0] v;
  begin
   v=crc^value;
   for(k=0;k<8;k=k+1) v=v[7] ? (v<<1)^8'h07:v<<1;
   crc8=v;
  end
 endfunction
 wire rx_valid,rx_error;wire [7:0] rx_data;
 host_uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) receiver(
  .clk(clk),.rst_n(rst_n),.rx(rx),.valid(rx_valid),.error(rx_error),.data(rx_data));
 reg byte_valid;reg [7:0] byte_data;wire byte_busy;
 host_uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) transmitter(
  .clk(clk),.rst_n(rst_n),.valid(byte_valid),.data(byte_data),.tx(tx),.busy(byte_busy));

 reg [2:0] parse_state;
 reg [7:0] request_seq,request_cmd,request_length,request_crc,first_byte,second_byte;
 reg [5:0] request_index;
 localparam TIMEOUT=(CLOCK_HZ/20<1 ? 1:CLOCK_HZ/20);
 localparam TW=$clog2(TIMEOUT+1);
 reg [TW-1:0] idle_count;
 reg queue_valid,packet_active;
 reg [7:0] queue_seq,queue_cmd,queue_length,packet_seq,packet_cmd,packet_length;
 reg [383:0] queue_payload,packet_payload;
 reg [5:0] packet_index;
 reg [7:0] packet_crc;
 reg [7:0] validation;
 reg image_requested;reg[1:0] image_state;reg[5:0] image_index;
 reg[15:0] image_base;reg[7:0] image_seq;reg[383:0] image_payload;
 assign image_read=image_state==1;
 assign image_address=image_base+image_index;
 always @* begin
  validation=0;
  case(request_cmd)
   8'h01:if(request_length!=0) validation=1;
   8'h10:if(request_length!=2 || {second_byte,first_byte}>1023) validation=1;
   8'h11:if(request_length!=1) validation=1;
   8'h12:if(request_length!=0) validation=1;
   8'h13:if(request_length!=1) validation=1;else if(first_byte!=0) validation=2;
   8'h14:if(request_length!=1 || first_byte>1) validation=1;
   8'h30:if(!CALIBRATION_ENABLE)validation=2;else if(request_length!=0)validation=1;else if(image_requested&&!image_ready)validation=3;
   8'h31:if(!CALIBRATION_ENABLE)validation=2;else if(request_length!=0)validation=1;
   8'h32:if(!CALIBRATION_ENABLE)validation=2;else if(request_length!=2 || {second_byte,first_byte}>57552)validation=1;else if(!image_ready)validation=3;
   default:validation=2;
  endcase
  if(validation==0 && request_cmd!=8'h01 && request_cmd!=8'h30 && request_cmd!=8'h31 && request_cmd!=8'h32 && !command_ready) validation=3;
 end
 reg [7:0] next_packet_byte;
 always @* begin
  next_packet_byte=0;
  case(packet_index)
   0:next_packet_byte=8'ha5;
   1:next_packet_byte=8'h5a;
   2:next_packet_byte=1;
   3:next_packet_byte=packet_seq;
   4:next_packet_byte=packet_cmd;
   5:next_packet_byte=packet_length;
   default:if(packet_index==6+packet_length) next_packet_byte=packet_crc;
           else if(packet_index>=6 && packet_index<6+packet_length)
            next_packet_byte=packet_payload[(packet_index-6)*8+:8];
  endcase
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   image_arm<=0;image_requested<=0;image_state<=0;image_index<=0;image_base<=0;image_seq<=0;image_payload<=0;
   parse_state<=0;request_seq<=0;request_cmd<=0;request_length<=0;request_crc<=0;
   first_byte<=0;second_byte<=0;request_index<=0;idle_count<=0;
   queue_valid<=0;queue_seq<=0;queue_cmd<=0;queue_length<=0;queue_payload<=0;
   packet_active<=0;packet_seq<=0;packet_cmd<=0;packet_length<=0;packet_payload<=0;
   packet_index<=0;packet_crc<=0;byte_valid<=0;byte_data<=0;
   command_valid<=0;command_code<=0;command_value<=0;
  end else begin
   command_valid<=0;byte_valid<=0;
   if(image_state==1)image_state<=2;
   if(image_state==2)begin
    image_payload[image_index*8+:8]<=image_data;
    if(image_index==47)begin
     image_state<=0;queue_valid<=1;queue_seq<=image_seq;queue_cmd<=8'hb2;queue_length<=48;
     queue_payload<={image_data,image_payload[375:0]};
    end else begin image_index<=image_index+1'b1;image_state<=1;end
   end
   if(queue_valid && !packet_active) begin
    packet_active<=1;packet_seq<=queue_seq;packet_cmd<=queue_cmd;
    packet_length<=queue_length;packet_payload<=queue_payload;
    packet_index<=0;packet_crc<=0;queue_valid<=0;
   end
   if(packet_active && !byte_busy && !byte_valid) begin
    byte_data<=next_packet_byte;byte_valid<=1;
    if(packet_index>=2 && packet_index<6+packet_length)
     packet_crc<=crc8(packet_crc,next_packet_byte);
    if(packet_index==6+packet_length) packet_active<=0;
    else packet_index<=packet_index+1'b1;
   end
   if(parse_state==0 || rx_valid) idle_count<=0;
   else if(idle_count==TIMEOUT-1) begin parse_state<=0;idle_count<=0;end
   else idle_count<=idle_count+1'b1;
   if(rx_error) begin parse_state<=0;idle_count<=0;end
   else if(rx_valid) begin
    case(parse_state)
     0:if(rx_data==8'ha5) parse_state<=1;
     1:if(rx_data==8'h5a) parse_state<=2;
       else parse_state<=rx_data==8'ha5 ? 1:0;
     2:if(rx_data==1) begin request_crc<=crc8(0,rx_data);parse_state<=3;end
       else parse_state<=rx_data==8'ha5 ? 1:0;
     3:begin request_seq<=rx_data;request_crc<=crc8(request_crc,rx_data);parse_state<=4;end
     4:begin request_cmd<=rx_data;request_crc<=crc8(request_crc,rx_data);parse_state<=5;end
     5:begin
      request_length<=rx_data;request_crc<=crc8(request_crc,rx_data);
      request_index<=0;first_byte<=0;second_byte<=0;
      if(rx_data>48) parse_state<=0;
      else parse_state<=rx_data==0 ? 7:6;
     end
     6:begin
      if(request_index==0) first_byte<=rx_data;
      if(request_index==1) second_byte<=rx_data;
      request_crc<=crc8(request_crc,rx_data);
      if(request_index==request_length-1) parse_state<=7;
      else request_index<=request_index+1'b1;
     end
     7:begin
      parse_state<=0;
      if(rx_data==request_crc && !queue_valid && image_state==0) begin
       queue_valid<=1;queue_seq<=request_seq;
       if(request_cmd==8'h01 && validation==0) begin
        queue_cmd<=8'h81;queue_length<=48;queue_payload<=status_payload;
       end else if(request_cmd==8'h31 && validation==0)begin
        queue_cmd<=8'hb1;queue_length<=8;queue_payload<={320'd0,16'd57600,16'd180,16'd320,7'd0,image_requested,7'd0,image_ready};
       end else if(request_cmd==8'h32 && validation==0)begin
        queue_valid<=0;image_state<=1;image_index<=0;image_base<={second_byte,first_byte};image_seq<=request_seq;
       end else begin
        queue_cmd<=8'h80;queue_length<=2;queue_payload<={368'd0,validation,request_cmd};
        if(validation==0 && request_cmd==8'h30)begin image_arm<=!image_arm;image_requested<=1;end
        else if(validation==0) begin
         command_valid<=1;command_code<=request_cmd;
         command_value<=request_cmd==8'h10 ? {second_byte,first_byte}:{8'd0,first_byte};
        end
       end
      end
     end
    endcase
   end
  end
 end
endmodule
`endif
