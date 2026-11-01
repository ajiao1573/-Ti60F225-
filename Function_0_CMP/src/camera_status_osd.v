`ifndef CAMERA_STATUS_OSD_V
`define CAMERA_STATUS_OSD_V
// Board-visible camera status, using global 1920x1080 coordinates.
module camera_status_osd #(parameter X_START=1504,Y_START=24)(
 input [11:0] x_pos,y_pos,input ready,failed,size_error,pclk_alive,
 input [15:0] chip_id,input [8:0] config_index,
 input [9:0] input_fps,input [11:0] width,height,
 output [23:0] pixel,output active);
 wire [11:0] dx=x_pos-X_START;
 wire [1:0] line_index=y_pos<Y_START+24 ? 0 : y_pos<Y_START+48 ? 1 : 2;
 wire [11:0] dy=y_pos-Y_START-(line_index==0 ? 0 : line_index==1 ? 24 : 48)-4;
 wire [4:0] char_index=dx[8:4];
 wire [2:0] col=dx[3:1],row=dy[3:1];
 function [7:0] hexchar;input [3:0] d;begin hexchar=d<10 ? 8'd48+d : 8'd55+d;end endfunction
 reg [191:0] text;
 always @* begin
  case(line_index)
   0:begin
    text=failed ? "CAM:ERROR  PCLK:0       " : ready ?
         "CAM:READY  PCLK:0       " : "CAM:WAIT   PCLK:0       ";
    text[63-:8]=pclk_alive ? "1" : "0";
   end
   1:begin
    text="ID:0000 IDX:0000        ";
    text[167-:8]=hexchar(chip_id[15-:4]);
    text[159-:8]=hexchar(chip_id[11-:4]);
    text[151-:8]=hexchar(chip_id[7-:4]);
    text[143-:8]=hexchar(chip_id[3-:4]);
    text[95-:8]=8'd48+(config_index/1000)%10;
    text[87-:8]=8'd48+(config_index/100)%10;
    text[79-:8]=8'd48+(config_index/10)%10;
    text[71-:8]=8'd48+(config_index/1)%10;
   end
   2:begin
    text="IN:0000 W:0000 H:0000   ";
    text[167-:8]=8'd48+(input_fps/1000)%10;
    text[159-:8]=8'd48+(input_fps/100)%10;
    text[151-:8]=8'd48+(input_fps/10)%10;
    text[143-:8]=8'd48+(input_fps/1)%10;
    text[111-:8]=8'd48+(width/1000)%10;
    text[103-:8]=8'd48+(width/100)%10;
    text[95-:8]=8'd48+(width/10)%10;
    text[87-:8]=8'd48+(width/1)%10;
    text[55-:8]=8'd48+(height/1000)%10;
    text[47-:8]=8'd48+(height/100)%10;
    text[39-:8]=8'd48+(height/10)%10;
    text[31-:8]=8'd48+(height/1)%10;
   end
   default:text=0;
  endcase
 end
 wire [7:0] code=char_index<24 ? text[191-char_index*8-:8] : 8'd32;
 function [4:0] font;
  input [7:0] c;input [2:0] r;
  reg [34:0] bits;
  begin
   case(c)
    8'd75:bits=35'b10001100101010011000101001001010001;
    8'd88:bits=35'b10001100010101000100010101000110001;
    8'd48:bits=35'b01110100011001110101110011000101110;
    8'd53:bits=35'b11111100001000011110000010000111110;
    8'd54:bits=35'b01110100001000011110100011000101110;
    8'd55:bits=35'b11111000010000100010001000100001000;
    8'd56:bits=35'b01110100011000101110100011000101110;
    8'd57:bits=35'b01110100011000101111000010000101110;
    8'd65:bits=35'b01110100011000111111100011000110001;
    8'd66:bits=35'b11110100011000111110100011000111110;
    8'd67:bits=35'b01111100001000010000100001000001111;
    8'd68:bits=35'b11110100011000110001100011000111110;
    8'd69:bits=35'b11111100001000011110100001000011111;
    8'd70:bits=35'b11111100001000011110100001000010000;
    8'd71:bits=35'b01110100011000010111100011000101111;
    8'd72:bits=35'b10001100011000111111100011000110001;
    8'd73:bits=35'b01110001000010000100001000010001110;
    8'd76:bits=35'b10000100001000010000100001000011111;
    8'd77:bits=35'b10001110111010110101100011000110001;
    8'd78:bits=35'b10001110011100110101100111001110001;
    8'd79:bits=35'b01110100011000110001100011000101110;
    8'd80:bits=35'b11110100011000111110100001000010000;
    8'd82:bits=35'b11110100011000111110101001001010001;
    8'd83:bits=35'b01111100001000001110000010000111110;
    8'd84:bits=35'b11111001000010000100001000010000100;
    8'd86:bits=35'b10001100011000110001100010101000100;
    8'd87:bits=35'b10001100011000110101101011010101010;
    8'd89:bits=35'b10001100010101000100001000010000100;
    8'd85:bits=35'b10001100011000110001100011000101110;
    8'd90:bits=35'b11111000010001000100010001000011111;
    8'd47:bits=35'b00001000010001000100010001000010000;
    8'd58:bits=35'b00000001000010000000001000010000000;
    8'd43:bits=35'b00000001000010011111001000010000000;
    8'd49:bits=35'b00100011000010000100001000010001110;
    8'd50:bits=35'b01110100010000100010001000100011111;
    8'd51:bits=35'b11110000010000101110000010000111110;
    8'd52:bits=35'b00010001100101010010111110001000010;
    default:bits=0;
   endcase
   font=r<7 ? bits[34-r*5-:5] : 5'b0;
  end
 endfunction
 wire [4:0] dots=font(code,row);
 wire ink=active && dy<14 && col<5 && dots[4-col];
 assign active=x_pos>=X_START && x_pos<X_START+384 && y_pos>=Y_START && y_pos<Y_START+72;
 assign pixel=ink ? ((failed || size_error) ? 24'hff6060 : ready ? 24'h60ff80 : 24'hffff60) : 24'h081020;
endmodule
`endif
