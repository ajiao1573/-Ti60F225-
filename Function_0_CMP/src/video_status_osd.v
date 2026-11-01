`ifndef VIDEO_STATUS_OSD_V
`define VIDEO_STATUS_OSD_V
// Three readable status lines. Inputs are latched at HDMI vertical blank.
module video_status_osd #(parameter X_START=16,Y_START=68,FW=3,STATE_ONLY=0)(
 input [11:0] x_pos,y_pos,input [2:0] gear,input [2:0] algorithm,
 input overlay,history,compare,input [FW-1:0] replay,left_frame,right_frame,
 input frozen,input [FW:0] frame_count,
 output [23:0] pixel,output active);
 wire [11:0] dx=x_pos-X_START;
 wire [1:0] line_index=y_pos<Y_START+24 ? 0 : y_pos<Y_START+48 ? 1 : 2;
 wire [11:0] dy=y_pos-Y_START-(line_index==0 ? 0 : line_index==1 ? 24 : 48)-4;
 wire [4:0] char_index=dx[8:4];
 wire [2:0] col=dx[3:1],row=dy[3:1];
 reg [191:0] text;
 always @* begin
  if(STATE_ONLY) begin
   if(line_index==0) text=frozen ? "STATE:FROZEN            " : "STATE:CAPTURING         ";
   else if(line_index==1) begin
    text="FRAMES:0/8              ";text[135:128]=8'd48+frame_count;
   end else text="                        ";
  end else case(line_index)
   0:case(gear)
    0:text="GEAR:1 THRESHOLD        ";
    1:text="GEAR:2 ALGORITHM        ";
    2:text="GEAR:3 DISPLAY          ";
    3:text="GEAR:4 HISTORY          ";
    4:text="GEAR:5 SHAPE            ";
    default:text="                        ";
   endcase
   1:case(algorithm)
    0:text="ALG:SOBEL               ";
    1:text="ALG:SOBEL+MEDIAN        ";
    2:text="ALG:CANNY               ";
    3:text="ALG:CANNY+MEDIAN        ";
    4:text="ALG:MAJORITY3           ";
    default:text="ALG:SOBEL               ";
   endcase
   default:begin
    if(history) begin
     text=compare ? "VIEW:COMPARE L:0 R:7    " : "VIEW:REPLAY FRAME:7     ";
     if(compare) begin text[71:64]=8'd48+left_frame;text[39:32]=8'd48+right_frame;end
     else text[47:40]=8'd48+replay;
    end
    else if(gear==4) text="VIEW:SHAPE DETECTION    ";
    else text=overlay ? "VIEW:COLOR+RED          " : "VIEW:GRAY+EDGE          ";
   end
  endcase
 end
 wire [7:0] code=text[191-char_index*8-:8];
 function [4:0] font;
  input [7:0] c;input [2:0] r;
  reg [34:0] bits;
  begin
   case(c)
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
 assign pixel=ink ? (line_index==0 ? 24'h00ffff : line_index==1 ? 24'hffff00 : 24'h00ff80) : 24'h081020;
endmodule
`endif
