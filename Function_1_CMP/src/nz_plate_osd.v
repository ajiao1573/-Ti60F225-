`ifndef NZ_PLATE_OSD_V
`define NZ_PLATE_OSD_V
module nz_plate_osd #(parameter X_START=32,Y_START=80,SCALE=2,RESULT_ONLY=0,DIAGNOSTICS=0)(
 input [11:0] x_pos,y_pos,input locked,valid,input [47:0] ascii,
 input [2:0] reject_reason,input ready,low_contrast,overflow,input [3:0] characters,
 input [7:0] adjust,input ae_locked,ae_failed,input [9:0] missing,fps,
 output [23:0] pixel,output active
);
 wire [11:0] dx=x_pos-X_START,dy=y_pos-Y_START;
 wire [2:0] line_index=RESULT_ONLY ? 0 : dy/(12*SCALE);
 wire [5:0] char_index=dx/(8*SCALE);
 wire [3:0] row=(dy%(12*SCALE))/SCALE,col=(dx%(8*SCALE))/SCALE;
 wire [7:0] offset_abs=adjust>=128 ? adjust-8'd128 : 8'd128-adjust;
 reg [191:0] text;
 always @* begin
  if(RESULT_ONLY || line_index==2) begin
   text="PLATE:------            ";
   if(valid) text[143:96]=ascii;
   else if(locked) text="PLATE:UNREADABLE        ";
  end else if(line_index==0) begin
   text="NZ PLATE OCR           ";
   if(DIAGNOSTICS) begin
    text="NZ PLATE OCR   FPS:000 ";
    text[191-20*8-:8]=48+(fps/100)%10;text[191-21*8-:8]=48+(fps/10)%10;text[191-22*8-:8]=48+fps%10;
   end
  end else if(line_index==1) text=locked ? "STATE:FROZEN            " : "STATE:SEARCHING         ";
  else if(line_index==3) begin
   text=ready ? "CHARS:0 LOW:0 OVER:0    " : "ROI:CAPTURING           ";
   if(ready) begin
    text[191-6*8-:8]=48+characters;text[191-12*8-:8]=low_contrast ? "1":"0";
    text[191-19*8-:8]=overflow ? "1":"0";
   end
  end else if(line_index==4) begin
   text="LOCAL32 ADJ:+000        ";
   text[191-12*8-:8]=adjust>=128 ? "+":"-";
   text[191-13*8-:8]=48+offset_abs/100;text[191-14*8-:8]=48+(offset_abs/10)%10;text[191-15*8-:8]=48+offset_abs%10;
  end else if(line_index==5) begin
   text=ae_failed ? "AE:ERROR  MISS:000      " : ae_locked ? "AE:LOCKED MISS:000      " : "AE:AUTO   MISS:000      ";
   text[191-15*8-:8]=48+(missing/100)%10;text[191-16*8-:8]=48+(missing/10)%10;text[191-17*8-:8]=48+missing%10;
  end else begin
   if(!ready) text="CHECK:WAIT FRAME        ";
   else case(reject_reason)
    1:text="CHECK:LOW CONTRAST      ";
    2:text="CHECK:EXTRA OBJECTS     ";
    3:text="CHECK:NEED SIX CHARS    ";
    4:text="CHECK:ALIGN PLATE       ";
    5:text="CHECK:OCR RETRY         ";
    default:text="CHECK:READ OK           ";
   endcase
  end
 end
 wire [7:0] code=text[191-char_index*8-:8];
 function [4:0] font;
  input [7:0] c;input [3:0] r;reg [34:0] bits;
  begin
   case(c)
    8'd43:bits=35'b00000001000010011111001000010000000;
    8'd45:bits=35'b00000000000000011111000000000000000;
    8'd47:bits=35'b00001000010001000100010001000010000;
    8'd48:bits=35'b01110100011001110101110011000101110;
    8'd49:bits=35'b00100011000010000100001000010001110;
    8'd50:bits=35'b01110100010000100010001000100011111;
    8'd51:bits=35'b11110000010000101110000010000111110;
    8'd52:bits=35'b00010001100101010010111110001000010;
    8'd53:bits=35'b11111100001000011110000010000111110;
    8'd54:bits=35'b01110100001000011110100011000101110;
    8'd55:bits=35'b11111000010000100010001000100001000;
    8'd56:bits=35'b01110100011000101110100011000101110;
    8'd57:bits=35'b01110100011000101111000010000101110;
    8'd58:bits=35'b00000001000010000000001000010000000;
    8'd63:bits=35'b01110100010000100010001000000000100;
    8'd65:bits=35'b01110100011000111111100011000110001;
    8'd66:bits=35'b11110100011000111110100011000111110;
    8'd67:bits=35'b01111100001000010000100001000001111;
    8'd68:bits=35'b11110100011000110001100011000111110;
    8'd69:bits=35'b11111100001000011110100001000011111;
    8'd70:bits=35'b11111100001000011110100001000010000;
    8'd71:bits=35'b01110100011000010111100011000101111;
    8'd72:bits=35'b10001100011000111111100011000110001;
    8'd73:bits=35'b01110001000010000100001000010001110;
    8'd74:bits=35'b00111000100001000010100101001001100;
    8'd75:bits=35'b10001100101010011000101001001010001;
    8'd76:bits=35'b10000100001000010000100001000011111;
    8'd77:bits=35'b10001110111010110101100011000110001;
    8'd78:bits=35'b10001110011100110101100111001110001;
    8'd79:bits=35'b01110100011000110001100011000101110;
    8'd80:bits=35'b11110100011000111110100001000010000;
    8'd81:bits=35'b01110100011000110001101011001001101;
    8'd82:bits=35'b11110100011000111110101001001010001;
    8'd83:bits=35'b01111100001000001110000010000111110;
    8'd84:bits=35'b11111001000010000100001000010000100;
    8'd85:bits=35'b10001100011000110001100011000101110;
    8'd86:bits=35'b10001100011000110001100010101000100;
    8'd87:bits=35'b10001100011000110101101011010101010;
    8'd88:bits=35'b10001100010101000100010101000110001;
    8'd89:bits=35'b10001100010101000100001000010000100;
    8'd90:bits=35'b11111000010001000100010001000011111;
    default:bits=0;
   endcase
   font=r<7 ? bits[34-r*5-:5] : 5'd0;
  end
 endfunction
 wire [4:0] dots=font(code,row);
 wire ink=active && row<7 && col<5 && dots[4-col];
 assign active=x_pos>=X_START && x_pos<X_START+24*8*SCALE &&
  y_pos>=Y_START && y_pos<Y_START+(RESULT_ONLY ? 1 : DIAGNOSTICS ? 7 : 3)*12*SCALE;
 assign pixel=ink ? (valid ? 24'h00ff80 : locked ? 24'hffcc00 : 24'h00ffff) : 24'h081020;
endmodule
`endif
