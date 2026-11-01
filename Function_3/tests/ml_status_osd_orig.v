`ifndef ML_STATUS_OSD_ORIG_V
`define ML_STATUS_OSD_ORIG_V
`include "src/ml_int13_params.vh"
// ---------------------------------------------------------------------------
// Gear 6 status panel.  Four 5x7 lines, 2x scaled, 16 px character pitch.
//
//   GEAR:6 ML
//   SOURCE:SELFTEST | SOURCE:LIVE
//   VEC:n TEST:PASS | FAIL | WAIT                       (self-test)
//   STATE:<class> ACC:<signed decimal>                  (self-test detail)
//   STATE:WAIT FEATURE | BUSY | OK | NG | INVALID       (live)
//   FR:dddd ACC:<signed decimal>                        (live detail)
//
// Every field arrives from one latched snapshot taken in the display clock
// domain, so a line can never mix the class of one transaction with the
// accumulator or identifier of another.  No divider is used in this module:
// the decimal accumulator and the four frame-id digits are produced upstream.
// ---------------------------------------------------------------------------
module ml_status_osd_orig #(
 parameter [11:0] X_START = 12'd32,
 parameter [11:0] Y_START = 12'd76
)(
 input [11:0] x_pos,
 input [11:0] y_pos,
 input gear6,
 input source,
 input [2:0] state,
 input [1:0] disp_class,
 input test_pass,
 input test_done,
 input [1:0] vec,
 input acc_na,
 input acc_neg,
 input [35:0] digits,
 input [15:0] frame_bcd,
 output [23:0] pixel,
 output active
);
 // The 5x7 glyph table is shared with the test bench, so it lives in its own
 // include; it is pulled in inside the module body because Verilog-2001 has no
 // file-scope functions.
 `include "src/ml_osd_font.vh"
`undef ML_OSD_FONT_VH

 // ---------------- accumulator field: sign + 9 digits, right aligned ------
 wire [3:0] d0 = digits[3:0];
 wire [3:0] d1 = digits[7:4];
 wire [3:0] d2 = digits[11:8];
 wire [3:0] d3 = digits[15:12];
 wire [3:0] d4 = digits[19:16];
 wire [3:0] d5 = digits[23:20];
 wire [3:0] d6 = digits[27:24];
 wire [3:0] d7 = digits[31:28];
 wire [3:0] d8 = digits[35:32];
 wire nz8 = (d8 != 4'd0);
 wire nz7 = nz8 | (d7 != 4'd0);
 wire nz6 = nz7 | (d6 != 4'd0);
 wire nz5 = nz6 | (d5 != 4'd0);
 wire nz4 = nz5 | (d4 != 4'd0);
 wire nz3 = nz4 | (d3 != 4'd0);
 wire nz2 = nz3 | (d2 != 4'd0);
 wire nz1 = nz2 | (d1 != 4'd0);
 wire [7:0] k8 = nz8 ? (8'd48 + {4'd0,d8}) : 8'h20;
 wire [7:0] k7 = nz7 ? (8'd48 + {4'd0,d7}) : 8'h20;
 wire [7:0] k6 = nz6 ? (8'd48 + {4'd0,d6}) : 8'h20;
 wire [7:0] k5 = nz5 ? (8'd48 + {4'd0,d5}) : 8'h20;
 wire [7:0] k4 = nz4 ? (8'd48 + {4'd0,d4}) : 8'h20;
 wire [7:0] k3 = nz3 ? (8'd48 + {4'd0,d3}) : 8'h20;
 wire [7:0] k2 = nz2 ? (8'd48 + {4'd0,d2}) : 8'h20;
 wire [7:0] k1 = nz1 ? (8'd48 + {4'd0,d1}) : 8'h20;
 wire [7:0] k0 = 8'd48 + {4'd0,d0};
 wire [7:0] sign_char = acc_neg ? "-" : " ";
 wire [79:0] acc_field = acc_na ? {"       N/A"} :
                         {sign_char,k8,k7,k6,k5,k4,k3,k2,k1,k0};

 // ---------------- fixed words ------------------------------------------
 reg [95:0] state_word;      // live STATE: field, 12 characters
 // Explicit sensitivity list: string-literal case items defeat Icarus' @*
 // inference (the block would keep its initial value), and synthesis treats
 // the list identically.
 always @(state) begin
  case(state)
   `ML_STATE_WAIT:    state_word = "WAIT FEATURE";
   `ML_STATE_BUSY:    state_word = "BUSY        ";
   `ML_STATE_OK:      state_word = "OK          ";
   `ML_STATE_NG:      state_word = "NG          ";
   `ML_STATE_INVALID: state_word = "INVALID     ";
   default:          state_word = "WAIT FEATURE";
  endcase
 end

 reg [55:0] class_word;      // self-test STATE: field, 7 characters
 always @(disp_class) begin
  case(disp_class)
   2'd0: class_word = "OK     ";
   2'd1: class_word = "NG     ";
   default: class_word = "INVALID";
  endcase
 end

 wire [31:0] test_word = !test_done ? "WAIT" : (test_pass ? "PASS" : "FAIL");
 wire [7:0]  vec_char  = 8'd49 + {6'd0,vec};

 reg [255:0] text0, text1, text2, text3_st, text3_live;
 always @(source or vec_char or test_word or state_word or class_word
          or acc_field or frame_bcd) begin
  text0 = {"GEAR:6 ML", "                       "};
  text1 = source ? {"SOURCE:SELFTEST", "                 "}
                 : {"SOURCE:LIVE", "                     "};
  text2 = source ? {"VEC:", vec_char, " TEST:", test_word, "                 "}
                 : {"STATE:", state_word, "              "};
  text3_st = {"STATE:", class_word, " ACC:", acc_field, "    "};
  text3_live = {"FR:",
                (8'd48 + {4'd0, frame_bcd[15:12]}),
                (8'd48 + {4'd0, frame_bcd[11:8]}),
                (8'd48 + {4'd0, frame_bcd[7:4]}),
                (8'd48 + {4'd0, frame_bcd[3:0]}),
                " ACC:", acc_field, "          "};
 end

 wire [11:0] dx = x_pos - X_START;
 wire [11:0] dy_full = y_pos - Y_START;
 wire [1:0] line_index = (dy_full < 12'd24) ? 2'd0 : (dy_full < 12'd48) ? 2'd1 :
                         (dy_full < 12'd72) ? 2'd2 : 2'd3;
 wire [11:0] dy = dy_full - (line_index==2'd0 ? 12'd0 : line_index==2'd1 ? 12'd24 :
                             line_index==2'd2 ? 12'd48 : 12'd72) - 12'd4;
 wire [4:0] char_index = dx[8:4];
 wire [2:0] col = dx[3:1];
 wire [2:0] row = dy[3:1];

 reg [255:0] sel_text;
 always @(line_index or source or text0 or text1 or text2 or text3_st or text3_live) begin
  case(line_index)
   2'd0: sel_text = text0;
   2'd1: sel_text = text1;
   2'd2: sel_text = text2;
   default: sel_text = source ? text3_st : text3_live;
  endcase
 end

 wire [7:0] code = sel_text[255-char_index*8 -: 8];

 wire [4:0] dots = ml_font(code, row);
 wire ink = active && (dy < 12'd14) && (col < 3'd5) && dots[4-col];
 assign active = gear6 && (x_pos >= X_START) && (x_pos < X_START+12'd512) &&
                 (y_pos >= Y_START) && (y_pos < Y_START+12'd96);
 assign pixel = ink ? (line_index==2'd0 ? 24'h00ffff : line_index==2'd1 ? 24'hffff00 :
                       line_index==2'd2 ? 24'h00ff80 : 24'hffffff) : 24'h081020;
endmodule
`endif
