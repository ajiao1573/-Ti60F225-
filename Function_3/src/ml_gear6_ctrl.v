`ifndef ML_GEAR6_CTRL_V
`define ML_GEAR6_CTRL_V
`include "src/ml_int13_params.vh"
`include "src/ml_selftest_vectors.vh"

// ---------------------------------------------------------------------------
// Gear 6 (gear index 5) machine-learning endpoint.
//
// Owns one frozen integer classifier and exposes the single-transaction feature
// interface that a future outer-contour extractor will drive.  The camera path
// does NOT produce feature transactions in this build, so the live state is
// WAIT FEATURE; no constant or ROM vector is ever presented as a camera result.
//
// Self-test (gear 6 only): a short KEY+ press runs the fixed group of four
// frozen vectors back to back through the same classifier, comparing every
// result with the value the integer reference produced.  A short KEY- press
// clears the self-test and returns to WAIT FEATURE.  Each press also rotates
// which vector is shown in detail (VEC:1..VEC:4); TEST reflects the whole group.
//
// The self-test result is tagged SOURCE:SELFTEST and is never reused as a live
// classification: leaving the self-test clears the displayed result.
// ---------------------------------------------------------------------------


module ml_gear6_ctrl #(
 parameter integer FRAME_ID_W   = 12,
 parameter integer CONFIG_W     = 8,
 parameter [CONFIG_W-1:0] CONFIG_VERSION = 8'h01,
 parameter [2:0] ML_GEAR        = 3'd5
)(
 input clk,
 input rst_n,
 input [2:0] gear,
 input selftest_start,
 input selftest_clear,
 // future feature-extractor port (single transaction)
 input  ext_request_valid,
 output ext_request_ready,
 input  [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] ext_feature_bus,
 input  ext_feature_valid,
 input  [FRAME_ID_W-1:0] ext_frame_id,
 input  [CONFIG_W-1:0] ext_config,
 input  ext_cancel,
 // completed transaction (live or self-test), tagged by source
 output res_valid,
 output res_source,
 output [FRAME_ID_W-1:0] res_frame_id,
 output [1:0] res_class,
 output signed [`ML_ACC_W-1:0] res_accumulator,
 output [3:0] res_reason,
 // display bundle inputs for the cross-domain snapshot
 output osd_source,
 output [2:0] osd_state,
 output [1:0] osd_class,
 output [1:0] osd_vec,
 output osd_test_pass,
 output osd_test_done,
 output signed [`ML_ACC_W-1:0] osd_acc,
 output osd_acc_na,
 output [FRAME_ID_W-1:0] osd_frame_id,
 output reg [15:0] osd_frame_bcd,
 output [35:0] osd_digits,
 output osd_digits_valid,
 output osd_neg,
 // diagnostics
 output [7:0] txn_count
);
 wire gear_ok = (gear == ML_GEAR);
 // A transaction is only accepted when it carries this build's configuration
 // version: features produced under a different configuration are never
 // classified.  The extractor sees ready low and keeps holding its request.
 wire ext_cfg_ok = (ext_config == CONFIG_VERSION);

 // ---------------- classifier -------------------------------------------
 wire clf_ready, clf_valid, clf_busy, clf_cancel;
 wire [FRAME_ID_W-1:0] clf_frame_id;
 wire [1:0] clf_class;
 wire signed [`ML_ACC_W-1:0] clf_acc;
 wire [3:0] clf_reason, clf_reason_feature;
 wire [7:0] clf_dropped;

 reg  selftest_active;     // group in progress
 reg  selftest_display;    // sticky: self-test source owns the display
 reg  st_waiting;          // a self-test transaction is in flight
 reg  [1:0] vec_ptr;       // vector currently being issued
 reg  [1:0] disp_vec;      // vector whose detail is shown
 reg  vec_pass [0:3];
 reg  [1:0] vec_class [0:3];
 reg  signed [`ML_ACC_W-1:0] vec_acc [0:3];
 reg  live_have;
 reg  [1:0] live_class;
 reg  [7:0] txn_q;

 // self-test vector selection
 reg [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] st_bus;
 reg st_fv;
 reg [1:0] st_class;
 reg [3:0] st_reason;
 reg signed [`ML_ACC_W-1:0] st_acc;
 always @* begin
  case(vec_ptr)
   2'd0: begin
    st_bus={`ML_ST0_F12,`ML_ST0_F11,`ML_ST0_F10,`ML_ST0_F9,`ML_ST0_F8,`ML_ST0_F7,`ML_ST0_F6,
            `ML_ST0_F5,`ML_ST0_F4,`ML_ST0_F3,`ML_ST0_F2,`ML_ST0_F1,`ML_ST0_F0};
    st_fv=`ML_ST0_VALID; st_class=`ML_ST0_CLASS; st_reason=`ML_ST0_REASON; st_acc=`ML_ST0_ACC;
   end
   2'd1: begin
    st_bus={`ML_ST1_F12,`ML_ST1_F11,`ML_ST1_F10,`ML_ST1_F9,`ML_ST1_F8,`ML_ST1_F7,`ML_ST1_F6,
            `ML_ST1_F5,`ML_ST1_F4,`ML_ST1_F3,`ML_ST1_F2,`ML_ST1_F1,`ML_ST1_F0};
    st_fv=`ML_ST1_VALID; st_class=`ML_ST1_CLASS; st_reason=`ML_ST1_REASON; st_acc=`ML_ST1_ACC;
   end
   2'd2: begin
    st_bus={`ML_ST2_F12,`ML_ST2_F11,`ML_ST2_F10,`ML_ST2_F9,`ML_ST2_F8,`ML_ST2_F7,`ML_ST2_F6,
            `ML_ST2_F5,`ML_ST2_F4,`ML_ST2_F3,`ML_ST2_F2,`ML_ST2_F1,`ML_ST2_F0};
    st_fv=`ML_ST2_VALID; st_class=`ML_ST2_CLASS; st_reason=`ML_ST2_REASON; st_acc=`ML_ST2_ACC;
   end
   default: begin
    st_bus={`ML_ST3_F12,`ML_ST3_F11,`ML_ST3_F10,`ML_ST3_F9,`ML_ST3_F8,`ML_ST3_F7,`ML_ST3_F6,
            `ML_ST3_F5,`ML_ST3_F4,`ML_ST3_F3,`ML_ST3_F2,`ML_ST3_F1,`ML_ST3_F0};
    st_fv=`ML_ST3_VALID; st_class=`ML_ST3_CLASS; st_reason=`ML_ST3_REASON; st_acc=`ML_ST3_ACC;
   end
  endcase
 end

 // ---------------- decimal diagnostic ------------------------------------
 wire dec_busy, dec_done, dec_neg;
 wire [35:0] dec_digits;
 reg  conv_start;
 reg  signed [`ML_ACC_W-1:0] conv_src;
 reg  conv_src_valid;
 reg  [35:0] digits_q;
 reg  digits_valid_q;
 reg  neg_q;

 ml_dec9 u_dec9 (
  .clk(clk), .rst_n(rst_n), .start(conv_start), .value(conv_src),
  .busy(dec_busy), .done(dec_done), .negative(dec_neg), .digits(dec_digits));

 reg  acc_na_q;
 reg  signed [`ML_ACC_W-1:0] acc_q;
 reg  [FRAME_ID_W-1:0] frame_q;
 // Four BCD frame-id digits, produced here so the display path has no divider.
 // The id is 0..4095, so every quotient and remainder below is 0..9 and the
 // final slice to 4 bits is exact, not a truncation of a wider value.
 wire [11:0] fid_div1000 = clf_frame_id / 12'd1000;
 wire [11:0] fid_mod1000 = clf_frame_id % 12'd1000;
 wire [11:0] fid_div100  = fid_mod1000 / 12'd100;
 wire [11:0] fid_mod100  = fid_mod1000 % 12'd100;
 wire [11:0] fid_div10   = fid_mod100 / 12'd10;
 wire [11:0] fid_mod10   = fid_mod100 % 12'd10;
 wire [3:0]  fid_th = fid_div1000[3:0];
 wire [3:0]  fid_hu = fid_div100[3:0];
 wire [3:0]  fid_te = fid_div10[3:0];
 wire [3:0]  fid_ru = fid_mod10[3:0];
 reg  [1:0] disp_class_q;
 reg  test_done_q;
 reg  test_pass_q;

 wire [FRAME_ID_W-1:0] clf_frame_id_in = selftest_active ? {FRAME_ID_W{1'b0}} : ext_frame_id;
 wire st_issue = selftest_active && !st_waiting && !dec_busy;
 wire clf_req  = gear_ok && !clf_cancel &&
                 (selftest_active ? st_issue : (ext_request_valid && ext_cfg_ok && !dec_busy));
 assign clf_cancel = !gear_ok || (selftest_active ? selftest_clear : ext_cancel);
 assign ext_request_ready = gear_ok && !selftest_active && !dec_busy && clf_ready && ext_cfg_ok;

 ml_int13_classifier #(.FRAME_ID_W(FRAME_ID_W),.CONFIG_W(CONFIG_W)) u_classifier(
  .clk(clk), .rst_n(rst_n),
  .request_valid(clf_req), .request_ready(clf_ready),
  .feature_bus(selftest_active ? st_bus : ext_feature_bus),
  .feature_valid(selftest_active ? st_fv : ext_feature_valid),
  .frame_id(clf_frame_id_in), .config_version(CONFIG_VERSION),
  .cancel(clf_cancel),
  .result_valid(clf_valid), .result_frame_id(clf_frame_id), .result_config(),
  .result_class(clf_class), .result_accumulator(clf_acc),
  .result_reason(clf_reason), .result_reason_feature(clf_reason_feature),
  .busy(clf_busy), .dropped_requests(clf_dropped));

 // the vector whose detail is on screen (index 3 is the one just collected)
 wire [1:0] sel_class_next = (disp_vec==2'd0) ? vec_class[0] :
                             (disp_vec==2'd1) ? vec_class[1] :
                             (disp_vec==2'd2) ? vec_class[2] : clf_class;
 wire signed [`ML_ACC_W-1:0] sel_acc_next = (disp_vec==2'd0) ? vec_acc[0] :
                             (disp_vec==2'd1) ? vec_acc[1] :
                             (disp_vec==2'd2) ? vec_acc[2] : clf_acc;

 // self-test comparison against the frozen integer reference
 wire cmp_ok = (clf_class == st_class) &&
               ((st_class == `ML_CLS_INVALID) ? (clf_reason == st_reason)
                                             : (clf_acc == st_acc));

 function [2:0] class_state;
  input [1:0] c;
  begin
   class_state = (c == `ML_CLS_OK) ? `ML_STATE_OK :
                 (c == `ML_CLS_NG) ? `ML_STATE_NG : `ML_STATE_INVALID;
  end
 endfunction

 assign osd_state = selftest_display
                    ? (test_done_q ? class_state(disp_class_q) : `ML_STATE_BUSY)
                    : (live_have ? class_state(live_class)
                                 : (clf_busy ? `ML_STATE_BUSY : `ML_STATE_WAIT));
 assign osd_source      = selftest_display;
 assign osd_class       = disp_class_q;
 assign osd_vec         = disp_vec;
 assign osd_test_pass   = test_pass_q;
 assign osd_test_done   = test_done_q;
 assign osd_acc         = acc_q;
 assign osd_acc_na      = acc_na_q;
 assign osd_frame_id    = frame_q;
 assign osd_digits      = digits_q;
 assign osd_digits_valid= digits_valid_q;
 assign osd_neg         = neg_q;
 assign txn_count       = txn_q;

 assign res_valid       = clf_valid;
 assign res_source      = selftest_active;
 assign res_frame_id    = clf_frame_id;
 assign res_class       = clf_class;
 assign res_accumulator = clf_acc;
 assign res_reason      = clf_reason;

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   selftest_active<=1'b0; selftest_display<=1'b0; st_waiting<=1'b0;
   vec_ptr<=2'd0; disp_vec<=2'd3;
   live_have<=1'b0; live_class<=`ML_CLS_OK;
   acc_na_q<=1'b1; acc_q<={`ML_ACC_W{1'b0}}; frame_q<={FRAME_ID_W{1'b0}};
   osd_frame_bcd<=16'd0;
   disp_class_q<=`ML_CLS_INVALID; test_done_q<=1'b0; test_pass_q<=1'b0; txn_q<=8'd0;
   vec_pass[0]<=1'b0; vec_pass[1]<=1'b0; vec_pass[2]<=1'b0; vec_pass[3]<=1'b0;
   vec_class[0]<=`ML_CLS_INVALID; vec_class[1]<=`ML_CLS_INVALID;
   vec_class[2]<=`ML_CLS_INVALID; vec_class[3]<=`ML_CLS_INVALID;
   vec_acc[0]<={`ML_ACC_W{1'b0}}; vec_acc[1]<={`ML_ACC_W{1'b0}};
   vec_acc[2]<={`ML_ACC_W{1'b0}}; vec_acc[3]<={`ML_ACC_W{1'b0}};
  end else begin
   // leaving gear 6 always drops any in-flight or displayed result
   if(!gear_ok) begin
    selftest_active<=1'b0; selftest_display<=1'b0; st_waiting<=1'b0;
    live_have<=1'b0; test_done_q<=1'b0; test_pass_q<=1'b0;
    acc_na_q<=1'b1; acc_q<={`ML_ACC_W{1'b0}}; frame_q<={FRAME_ID_W{1'b0}};
    vec_pass[0]<=1'b0; vec_pass[1]<=1'b0; vec_pass[2]<=1'b0; vec_pass[3]<=1'b0;
   end else begin
    // ---- operator gestures (gear 6 only, pulses from video_key_control)
    if(selftest_clear) begin
     selftest_active<=1'b0; selftest_display<=1'b0; st_waiting<=1'b0;
     test_done_q<=1'b0; test_pass_q<=1'b0;
     live_have<=1'b0; acc_na_q<=1'b1; acc_q<={`ML_ACC_W{1'b0}};
     frame_q<={FRAME_ID_W{1'b0}}; osd_frame_bcd<=16'd0;
    end else if(selftest_start && !selftest_active) begin
     selftest_active<=1'b1; selftest_display<=1'b1; st_waiting<=1'b0;
     vec_ptr<=2'd0; test_done_q<=1'b0; test_pass_q<=1'b0;
     disp_vec<=disp_vec+2'd1;
     vec_pass[0]<=1'b0; vec_pass[1]<=1'b0; vec_pass[2]<=1'b0; vec_pass[3]<=1'b0;
     live_have<=1'b0;
    end else if(ext_cancel && !selftest_active) begin
     // a live transaction is abandoned: nothing old may stay on screen
     live_have<=1'b0; acc_na_q<=1'b1; acc_q<={`ML_ACC_W{1'b0}};
     frame_q<={FRAME_ID_W{1'b0}}; osd_frame_bcd<=16'd0;
     st_waiting<=1'b0;
    end

    // ---- self-test issue / collect
    if(selftest_active) begin
     if(clf_req && clf_ready) st_waiting<=1'b1;
     if(clf_valid) begin
      st_waiting<=1'b0;
      vec_class[vec_ptr]<=clf_class;
      vec_acc[vec_ptr]<=clf_acc;
      vec_pass[vec_ptr]<=cmp_ok;
      if(vec_ptr==2'd3) begin
       selftest_active<=1'b0;
       test_done_q<=1'b1;
       test_pass_q<=vec_pass[0] & vec_pass[1] & vec_pass[2] & cmp_ok;
       disp_class_q<=sel_class_next;
       acc_q<=sel_acc_next;
       acc_na_q<=(sel_class_next==`ML_CLS_INVALID);
       frame_q<={FRAME_ID_W{1'b0}};
      end else begin
       vec_ptr<=vec_ptr+2'd1;
      end
     end
    end else if(clf_valid) begin
     // ---- live result: the most recent completed transaction owns the display
     selftest_display<=1'b0;
     test_done_q<=1'b0;
     live_have<=1'b1;
     live_class<=clf_class;
     acc_q<=clf_acc;
     acc_na_q<=(clf_class==`ML_CLS_INVALID);
     frame_q<=clf_frame_id;
     osd_frame_bcd<={fid_th,fid_hu,fid_te,fid_ru};
    end

    if(clf_valid && txn_q!=8'hFF) txn_q<=txn_q+8'd1;
   end
  end
 end

 // decimal diagnostic: reconvert whenever the displayed accumulator changes
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   conv_start<=1'b0; conv_src<={`ML_ACC_W{1'b0}}; conv_src_valid<=1'b0;
   digits_q<=36'd0; digits_valid_q<=1'b0; neg_q<=1'b0;
  end else begin
   conv_start<=1'b0;
   if(dec_done) begin
    digits_q<=dec_digits; neg_q<=dec_neg; digits_valid_q<=1'b1;
   end
   if(acc_na_q) begin
    digits_valid_q<=1'b0; conv_src_valid<=1'b0;
   end else if(!dec_busy && !conv_start && (!conv_src_valid || conv_src!=acc_q)) begin
    conv_start<=1'b1; conv_src<=acc_q; conv_src_valid<=1'b1;
   end
  end
 end
endmodule
`endif
