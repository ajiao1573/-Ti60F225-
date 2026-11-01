`ifndef ML_INT13_CLASSIFIER_V
`define ML_INT13_CLASSIFIER_V
`include "src/ml_int13_params.vh"

// ---------------------------------------------------------------------------
// Frozen 13-feature integer linear classifier (outer contour, 2^24 scale).
//
//   A = offset_integer + sum(weight_integer[i] * feature[i])
//   A >= 0 -> NG (class 1) ;  A < 0 -> OK (class 0)
//
// No division, no shift, no re-normalisation, no saturation and no comparison
// against 0.5.  The threshold is already folded into offset_integer.
//
// Arithmetic: one 21x16 signed multiplier reused for 13 cycles, the full 37-bit
// product is sign extended into a 38-bit adder together with the 29-bit
// accumulator, and the reduced sum is range checked before it is narrowed back
// to 29 bits.  Verilog width/unsigned-propagation traps are avoided by
// declaring every operand signed and by extending explicitly.
//
// Transaction contract (one transaction at a time):
//   - request_valid && request_ready latches the complete snapshot: the 13
//     features, feature_valid, frame_id and configuration version.
//   - While busy the snapshot cannot be overwritten; a request presented while
//     busy is ignored and counted in dropped_requests.
//   - Feature legality is checked in the wide (16-bit) transport domain before
//     any narrowing:
//       * a value outside the 13-bit sign-extended transport encoding is a
//         FORMAT error,
//       * a value inside the transport but outside the proven model domain is a
//         DOMAIN error,
//       * feature_valid=0 is FEATURE_INVALID.
//     In every one of those cases the result is UNCLASSIFIED(INVALID) with a
//     reason, never OK/NG, and no previous result is inherited.
//   - reset > cancel > accept.  A cancelled transaction never publishes a
//     result, including a cancel that lands on the publishing cycle.
// ---------------------------------------------------------------------------

// reason codes (shared with tools/gen_ml_artifacts.py)


module ml_int13_classifier #(
 parameter integer FRAME_ID_W = 12,
 parameter integer CONFIG_W   = 8
)(
 input clk,
 input rst_n,
 // request side
 input request_valid,
 output request_ready,
 input [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] feature_bus,
 input feature_valid,
 input [FRAME_ID_W-1:0] frame_id,
 input [CONFIG_W-1:0] config_version,
 input cancel,
 // result side
 output result_valid,
 output reg [FRAME_ID_W-1:0] result_frame_id,
 output reg [CONFIG_W-1:0] result_config,
 output reg [1:0] result_class,
 output reg signed [`ML_ACC_W-1:0] result_accumulator,
 output reg [3:0] result_reason,
 output reg [3:0] result_reason_feature,
 // status
 output busy,
 output [7:0] dropped_requests
);
 localparam [1:0] S_IDLE = 2'd0, S_MUL = 2'd1, S_PUB = 2'd2;
 localparam integer PROD_W = `ML_COEF_W + `ML_INPUT_W;   // 37, exact product
 localparam integer SUM_W  = PROD_W + 1;               // 38, carry guard

 reg [1:0] state;
 reg [3:0] idx;
 reg [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] feat_q;
 reg signed [`ML_ACC_W-1:0] acc_q;

 // per-index selection: constant weight, raw feature slice and its domain
 reg signed [`ML_COEF_W-1:0]  w_sel;
 reg signed [`ML_INPUT_W-1:0] x_sel;
 reg signed [`ML_INPUT_W-1:0] lo_sel;
 reg signed [`ML_INPUT_W-1:0] hi_sel;
 always @* begin
  w_sel = `ML_W0; x_sel = feat_q[0*`ML_INPUT_W +: `ML_INPUT_W]; lo_sel = `ML_LO0; hi_sel = `ML_HI0;
  case(idx)
   4'd0:  begin w_sel=`ML_W0;  x_sel=feat_q[15:0];  lo_sel=`ML_LO0;  hi_sel=`ML_HI0;  end
   4'd1:  begin w_sel=`ML_W1;  x_sel=feat_q[31:16]; lo_sel=`ML_LO1;  hi_sel=`ML_HI1;  end
   4'd2:  begin w_sel=`ML_W2;  x_sel=feat_q[47:32]; lo_sel=`ML_LO2;  hi_sel=`ML_HI2;  end
   4'd3:  begin w_sel=`ML_W3;  x_sel=feat_q[63:48]; lo_sel=`ML_LO3;  hi_sel=`ML_HI3;  end
   4'd4:  begin w_sel=`ML_W4;  x_sel=feat_q[79:64]; lo_sel=`ML_LO4;  hi_sel=`ML_HI4;  end
   4'd5:  begin w_sel=`ML_W5;  x_sel=feat_q[95:80]; lo_sel=`ML_LO5;  hi_sel=`ML_HI5;  end
   4'd6:  begin w_sel=`ML_W6;  x_sel=feat_q[111:96]; lo_sel=`ML_LO6; hi_sel=`ML_HI6;  end
   4'd7:  begin w_sel=`ML_W7;  x_sel=feat_q[127:112]; lo_sel=`ML_LO7; hi_sel=`ML_HI7; end
   4'd8:  begin w_sel=`ML_W8;  x_sel=feat_q[143:128]; lo_sel=`ML_LO8; hi_sel=`ML_HI8; end
   4'd9:  begin w_sel=`ML_W9;  x_sel=feat_q[159:144]; lo_sel=`ML_LO9; hi_sel=`ML_HI9; end
   4'd10: begin w_sel=`ML_W10; x_sel=feat_q[175:160]; lo_sel=`ML_LO10; hi_sel=`ML_HI10; end
   4'd11: begin w_sel=`ML_W11; x_sel=feat_q[191:176]; lo_sel=`ML_LO11; hi_sel=`ML_HI11; end
   4'd12: begin w_sel=`ML_W12; x_sel=feat_q[207:192]; lo_sel=`ML_LO12; hi_sel=`ML_HI12; end
   default: begin w_sel=`ML_W0; x_sel=feat_q[15:0]; lo_sel=`ML_LO0; hi_sel=`ML_HI0; end
  endcase
 end

 // transport legality: the 13-bit signed encoding, sign extended into 16 bits
 wire format_ok = (x_sel[15:13] == {3{x_sel[12]}});
 // proven model domain for this feature
 wire domain_ok = (x_sel >= lo_sel) && (x_sel <= hi_sel);

 // exact 21x16 signed product, kept at full width
 wire signed [PROD_W-1:0] prod_full = w_sel * x_sel;
 // explicit sign extension into the 38-bit adder
 wire signed [SUM_W-1:0] acc_exts  = {{(SUM_W-`ML_ACC_W){acc_q[`ML_ACC_W-1]}}, acc_q};
 wire signed [SUM_W-1:0] prod_exts = {prod_full[PROD_W-1], prod_full};
 wire signed [SUM_W-1:0] acc_next  = acc_exts + prod_exts;
 // the reduced 29-bit value keeps the sign only if every upper bit agrees
 wire acc_fits = (acc_next[SUM_W-1:`ML_ACC_W-1] ==
                  {(SUM_W-`ML_ACC_W+1){acc_next[`ML_ACC_W-1]}});

 assign request_ready = (state == S_IDLE);
 assign busy          = (state != S_IDLE);
 assign result_valid  = (state == S_PUB) && !cancel;

 // refused requests are counted once per assertion burst
 reg refuse_d;
 reg [7:0] dropped_q;
 wire refuse = request_valid && !request_ready;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin refuse_d<=1'b0; dropped_q<=8'd0; end
  else begin
   refuse_d <= refuse;
   if(refuse && !refuse_d && dropped_q!=8'hFF) dropped_q <= dropped_q + 8'd1;
  end
 end
 assign dropped_requests = dropped_q;

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=S_IDLE; idx<=4'd0; feat_q<=0; acc_q<={`ML_ACC_W{1'b0}};
   result_frame_id<=0; result_config<=0; result_class<=`ML_CLS_INVALID;
   result_accumulator<={`ML_ACC_W{1'b0}}; result_reason<=`ML_R_RESET;
   result_reason_feature<=4'hF;
  end else begin
   case(state)
    S_IDLE: if(request_valid) begin
     feat_q<=feature_bus;
     result_frame_id<=frame_id;
     result_config<=config_version;
     idx<=4'd0;
     acc_q<=`ML_OFFSET;
     if(!feature_valid) begin
      result_class<=`ML_CLS_INVALID;
      result_accumulator<={`ML_ACC_W{1'b0}};
      result_reason<=`ML_R_FEATURE_INVALID;
      result_reason_feature<=4'hF;
      state<=S_PUB;
     end else begin
      state<=S_MUL;
     end
    end
    S_MUL: begin
     if(cancel) begin
      // drop the partial accumulation, publish nothing
      state<=S_IDLE;
      idx<=4'd0;
     end else if(!format_ok) begin
      result_class<=`ML_CLS_INVALID;
      result_accumulator<={`ML_ACC_W{1'b0}};
      result_reason<=`ML_R_FORMAT;
      result_reason_feature<=idx;
      state<=S_PUB;
     end else if(!domain_ok) begin
      result_class<=`ML_CLS_INVALID;
      result_accumulator<={`ML_ACC_W{1'b0}};
      result_reason<=`ML_R_DOMAIN;
      result_reason_feature<=idx;
      state<=S_PUB;
     end else if(!acc_fits) begin
      result_class<=`ML_CLS_INVALID;
      result_accumulator<={`ML_ACC_W{1'b0}};
      result_reason<=`ML_R_ARITHMETIC;
      result_reason_feature<=idx;
      state<=S_PUB;
     end else if(idx==`ML_FEATURE_COUNT-1) begin
      // acc_next[MSB] is the sign of the final accumulator: 0 -> A>=0 -> NG
      result_class<= acc_next[`ML_ACC_W-1] ? `ML_CLS_OK : `ML_CLS_NG;
      result_accumulator<=acc_next[`ML_ACC_W-1:0];
      result_reason<=`ML_R_NONE;
      result_reason_feature<=4'hF;
      state<=S_PUB;
     end else begin
      acc_q<=acc_next[`ML_ACC_W-1:0];
      idx<=idx+4'd1;
     end
    end
    S_PUB: begin
     state<=S_IDLE;
    end
    default: state<=S_IDLE;
   endcase
  end
 end
endmodule
`endif
