`ifndef SHAPE_OSD_V
`define SHAPE_OSD_V
// Centred below the 848x636 pane on 1280x720 HDMI: icon, then result name.
module shape_osd #(parameter X_START=528,Y_START=680)(
 input [11:0] x_pos,y_pos,input [1:0] shape,
 output [23:0] pixel,output active);
 wire [11:0] dx=x_pos-X_START,dy=y_pos-Y_START;
 wire [3:0] ix=dx[4:1],iy=(dy-12'd4)>>1;
 reg [15:0] icon_row;
 always @* begin
  icon_row=0;
  case(shape)
   1:case(iy)
    0,15:icon_row=16'h03c0;
    1,14:icon_row=16'h0c30;
    2,13:icon_row=16'h1008;
    3,12:icon_row=16'h2004;
    4,5,10,11:icon_row=16'h4002;
    default:icon_row=16'h8001;
   endcase
   2:icon_row=(iy==0 || iy==15) ? 16'hffff : 16'h8001;
   3:icon_row=iy==15 ? 16'hffff : (16'h0180<<((iy+1)>>1)) | (16'h0180>>((iy+1)>>1));
   default:icon_row=0;
  endcase
 end
 wire [71:0] text=shape==1 ? "Circle   " : shape==2 ? "Rectangle" :
                       shape==3 ? "Triangle " : "No shape ";
 wire [11:0] tx=dx-12'd48,ty=dy-12'd12;
 wire [3:0] char_index=tx[7:4];
 wire [2:0] col=tx[3:1],row=ty[3:1];
 wire [7:0] code=char_index<9 ? text[71-char_index*8-:8] : 8'd32;
 function [4:0] font;
  input [7:0] c;input [2:0] r;
  reg [34:0] bits;
  begin
   case(c)
    "C":bits=35'b01110100011000010000100001000101110;
    "R":bits=35'b11110100011000111110101001001010001;
    "T":bits=35'b11111001000010000100001000010000100;
    "N":bits=35'b10001110011010110011100011000110001;
    "a":bits=35'b00000000000111000001011111000101111;
    "c":bits=35'b00000000000111010000100001000101110;
    "e":bits=35'b00000000000111010001111111000001110;
    "g":bits=35'b00000011111000110001011110000101110;
    "h":bits=35'b10000100001011011001100011000110001;
    "i":bits=35'b00100000000110000100001000010001110;
    "l":bits=35'b01100001000010000100001000010001110;
    "n":bits=35'b00000000001111010001100011000110001;
    "o":bits=35'b00000000000111010001100011000101110;
    "p":bits=35'b00000111101000110001111101000010000;
    "r":bits=35'b00000000001011011001100001000010000;
    "s":bits=35'b00000000000111110000011100000111110;
    "t":bits=35'b00100001001111100100001000010100010;
    default:bits=0;
   endcase
   font=r<7 ? bits[34-r*5-:5] : 5'd0;
  end
 endfunction
 wire [4:0] dots=font(code,row);
 wire icon_ink=dx<32 && dy>=4 && dy<36 && icon_row[15-ix];
 wire text_ink=dx>=48 && dx<192 && dy>=12 && dy<26 && col<5 && dots[4-col];
 assign active=x_pos>=X_START && x_pos<X_START+224 && y_pos>=Y_START && y_pos<Y_START+40;
 assign pixel=(icon_ink || text_ink) ? 24'h00ff80 : 24'h081020;
endmodule
`endif
