`timescale 1ns/1ns

// Two-line display: THR:dddd, then FPS:dddd (unique displayed images/sec).
module threshold_osd #(
    parameter LABEL_KIND=0,
    parameter [11:0] X_START = 12'd1136,
    parameter [11:0] Y_START = 12'd16
)(
    input      [11:0] x_pos,
    input      [11:0] y_pos,
    input       [9:0] threshold,
    input       [9:0] fps,
    input       [7:0] pixel_in,
    output      [7:0] pixel_out,
    output             osd_active
);

localparam [11:0] BOX_WIDTH  = 12'd128;
localparam [11:0] BOX_HEIGHT = 12'd46;

wire in_box = (x_pos >= X_START) && (x_pos < X_START + BOX_WIDTH) &&
              (y_pos >= Y_START) && (y_pos < Y_START + BOX_HEIGHT);
wire fps_line=y_pos>=Y_START+12'd24;
wire [11:0] text_y=Y_START+(fps_line ? 12'd28 : 12'd4);
wire in_text_y = y_pos>=text_y && y_pos<text_y+12'd14;
wire [11:0] rel_x = x_pos - X_START;
wire [11:0] rel_y = y_pos - text_y;
wire [2:0] char_index = rel_x[6:4];
wire [3:0] font_col = rel_x[3:1];
wire [2:0] font_row = rel_y[3:1];

wire [9:0] value=fps_line ? fps : threshold;
wire [9:0] quotient_1000 = value / 10'd1000;
wire [3:0] digit_thousands = quotient_1000[3:0];
wire [9:0] rem_1000 = value % 10'd1000;
wire [9:0] quotient_100 = rem_1000 / 10'd100;
wire [3:0] digit_hundreds = quotient_100[3:0];
wire [6:0] rem_100 = rem_1000 % 10'd100;
wire [6:0] quotient_10 = rem_100 / 7'd10;
wire [6:0] remainder_10 = rem_100 % 7'd10;
wire [3:0] digit_tens = quotient_10[3:0];
wire [3:0] digit_ones = remainder_10[3:0];

reg [4:0] char_code;
always @(*) begin
    case (char_index)
        3'd0: char_code = LABEL_KIND==4 ? (fps_line ? 10 : 25) : LABEL_KIND==1 ? (fps_line ? 14 : 17) : LABEL_KIND==2 ? (fps_line ? 12 : 20) : LABEL_KIND==3 ? (fps_line ? 23 : 14) : fps_line ? 5'd14 : 5'd10; // T
        3'd1: char_code = LABEL_KIND==4 ? (fps_line ? 18 : 24) : LABEL_KIND==1 ? (fps_line ? 12 : 18) : LABEL_KIND==2 ? (fps_line ? 21 : 14) : LABEL_KIND==3 ? (fps_line ? 24 : 12) : fps_line ? 5'd15 : 5'd11; // H
        3'd2: char_code = LABEL_KIND==4 ? (fps_line ? 10 : 19) : LABEL_KIND==1 ? (fps_line ? 17 : 19) : LABEL_KIND==2 ? 10 : LABEL_KIND==3 ? (fps_line ? 10 : 22) : fps_line ? 5'd16 : 5'd12; // R
        3'd3: char_code = 4'd13; // :
        3'd4: char_code = digit_thousands;
        3'd5: char_code = digit_hundreds;
        3'd6: char_code = digit_tens;
        default: char_code = digit_ones;
    endcase
end

function [4:0] glyph_row;
    input [4:0] code;
    input [2:0] row;
    begin
        glyph_row = 5'b00000;
        case (code)
            4'd0: case(row) 0:glyph_row=5'b01110; 1:glyph_row=5'b10001; 2:glyph_row=5'b10011; 3:glyph_row=5'b10101; 4:glyph_row=5'b11001; 5:glyph_row=5'b10001; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
            4'd1: case(row) 0:glyph_row=5'b00100; 1:glyph_row=5'b01100; 2:glyph_row=5'b00100; 3:glyph_row=5'b00100; 4:glyph_row=5'b00100; 5:glyph_row=5'b00100; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
            4'd2: case(row) 0:glyph_row=5'b01110; 1:glyph_row=5'b10001; 2:glyph_row=5'b00001; 3:glyph_row=5'b00010; 4:glyph_row=5'b00100; 5:glyph_row=5'b01000; 6:glyph_row=5'b11111; default:glyph_row=0; endcase
            4'd3: case(row) 0:glyph_row=5'b11110; 1:glyph_row=5'b00001; 2:glyph_row=5'b00001; 3:glyph_row=5'b01110; 4:glyph_row=5'b00001; 5:glyph_row=5'b00001; 6:glyph_row=5'b11110; default:glyph_row=0; endcase
            4'd4: case(row) 0:glyph_row=5'b00010; 1:glyph_row=5'b00110; 2:glyph_row=5'b01010; 3:glyph_row=5'b10010; 4:glyph_row=5'b11111; 5:glyph_row=5'b00010; 6:glyph_row=5'b00010; default:glyph_row=0; endcase
            4'd5: case(row) 0:glyph_row=5'b11111; 1:glyph_row=5'b10000; 2:glyph_row=5'b10000; 3:glyph_row=5'b11110; 4:glyph_row=5'b00001; 5:glyph_row=5'b00001; 6:glyph_row=5'b11110; default:glyph_row=0; endcase
            4'd6: case(row) 0:glyph_row=5'b01110; 1:glyph_row=5'b10000; 2:glyph_row=5'b10000; 3:glyph_row=5'b11110; 4:glyph_row=5'b10001; 5:glyph_row=5'b10001; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
            4'd7: case(row) 0:glyph_row=5'b11111; 1:glyph_row=5'b00001; 2:glyph_row=5'b00010; 3:glyph_row=5'b00100; 4:glyph_row=5'b01000; 5:glyph_row=5'b01000; 6:glyph_row=5'b01000; default:glyph_row=0; endcase
            4'd8: case(row) 0:glyph_row=5'b01110; 1:glyph_row=5'b10001; 2:glyph_row=5'b10001; 3:glyph_row=5'b01110; 4:glyph_row=5'b10001; 5:glyph_row=5'b10001; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
            4'd9: case(row) 0:glyph_row=5'b01110; 1:glyph_row=5'b10001; 2:glyph_row=5'b10001; 3:glyph_row=5'b01111; 4:glyph_row=5'b00001; 5:glyph_row=5'b00001; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
            4'd10: case(row) 0:glyph_row=5'b11111; 1:glyph_row=5'b00100; 2:glyph_row=5'b00100; 3:glyph_row=5'b00100; 4:glyph_row=5'b00100; 5:glyph_row=5'b00100; 6:glyph_row=5'b00100; default:glyph_row=0; endcase
            4'd11: case(row) 0:glyph_row=5'b10001; 1:glyph_row=5'b10001; 2:glyph_row=5'b10001; 3:glyph_row=5'b11111; 4:glyph_row=5'b10001; 5:glyph_row=5'b10001; 6:glyph_row=5'b10001; default:glyph_row=0; endcase
            4'd12: case(row) 0:glyph_row=5'b11110; 1:glyph_row=5'b10001; 2:glyph_row=5'b10001; 3:glyph_row=5'b11110; 4:glyph_row=5'b10100; 5:glyph_row=5'b10010; 6:glyph_row=5'b10001; default:glyph_row=0; endcase
            4'd13: case(row) 1:glyph_row=5'b00100; 2:glyph_row=5'b00100; 4:glyph_row=5'b00100; 5:glyph_row=5'b00100; default:glyph_row=0; endcase
            5'd14: case(row) 0:glyph_row=5'b11111; 1:glyph_row=5'b10000; 2:glyph_row=5'b10000; 3:glyph_row=5'b11110; 4:glyph_row=5'b10000; 5:glyph_row=5'b10000; 6:glyph_row=5'b10000; default:glyph_row=0; endcase
            5'd15: case(row) 0:glyph_row=5'b11110; 1:glyph_row=5'b10001; 2:glyph_row=5'b10001; 3:glyph_row=5'b11110; 4:glyph_row=5'b10000; 5:glyph_row=5'b10000; 6:glyph_row=5'b10000; default:glyph_row=0; endcase
            5'd16: case(row) 0:glyph_row=5'b01111; 1:glyph_row=5'b10000; 2:glyph_row=5'b10000; 3:glyph_row=5'b01110; 4:glyph_row=5'b00001; 5:glyph_row=5'b00001; 6:glyph_row=5'b11110; default:glyph_row=0; endcase
            17:case(row) 0:glyph_row=17;1:glyph_row=27;2:glyph_row=21;3:glyph_row=21;4:glyph_row=17;5:glyph_row=17;6:glyph_row=17;endcase // M
            18:case(row) 0:glyph_row=14;1:glyph_row=17;2:glyph_row=17;3:glyph_row=17;4:glyph_row=17;5:glyph_row=17;6:glyph_row=14;endcase // O
            19:case(row) 0:glyph_row=30;1:glyph_row=17;2:glyph_row=17;3:glyph_row=17;4:glyph_row=17;5:glyph_row=17;6:glyph_row=30;endcase // D
            20:case(row) 0,1,2,3,4,5:glyph_row=16;6:glyph_row=31;endcase // L
            21:case(row) 0:glyph_row=14;1:glyph_row=17;2:glyph_row=16;3:glyph_row=23;4:glyph_row=17;5:glyph_row=17;6:glyph_row=15;endcase // G
            22:case(row) 0,6:glyph_row=31;1:glyph_row=1;2:glyph_row=2;3:glyph_row=4;4:glyph_row=8;5:glyph_row=16;endcase // Z
            23:case(row) 0,6:glyph_row=15;1:glyph_row=16;2,3,4:glyph_row=16;5:glyph_row=16;endcase // C
            24:case(row) 0,5,6:glyph_row=17;1,2:glyph_row=25;3,4:glyph_row=21;endcase // N
            5'd25: case(row) 0,1,2,3,4,5:glyph_row=17;6:glyph_row=14;endcase // U
            default: glyph_row = 5'b00000;
        endcase
    end
endfunction

wire [4:0] row_bits = glyph_row(char_code, font_row);
wire glyph_on = in_box && in_text_y && (font_col < 4'd5) && row_bits[4-font_col];
assign osd_active = in_box;
assign pixel_out = glyph_on ? 8'hff : (in_box ? 8'h00 : pixel_in);

endmodule

// Toggle synchronizer and one-second event counter. CLOCK_HZ follows the
// actual 74.4 MHz display PLL, not the nominal 74.25 MHz HDMI label.
module frame_rate_meter #(parameter CLOCK_HZ=74400000)(
 input clk,input rst_n,input frame_toggle,
 output reg [9:0] fps
);
 localparam CW=($clog2(CLOCK_HZ)<1)?1:$clog2(CLOCK_HZ);
 reg [2:0] sync_toggle;
 reg [CW-1:0] ticks;
 reg [9:0] count;
 wire event_seen=sync_toggle[2]^sync_toggle[1];
 wire [9:0] counted=(event_seen && count<999) ? count+10'd1 : count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin sync_toggle<=0;ticks<=0;count<=0;fps<=0;end
  else begin
   sync_toggle<={sync_toggle[1:0],frame_toggle};
   if(ticks==CLOCK_HZ-1) begin ticks<=0;fps<=counted;count<=0;end
   else begin ticks<=ticks+1'b1;count<=counted;end
  end
 end
endmodule
