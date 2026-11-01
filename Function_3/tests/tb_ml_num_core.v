// Checkpoint bench for the finite-width numeric core.
//
//   vvp tb.vvp +PTS=verification/core/x.pts.hex +EXP=verification/core/x.exp.hex +N=102
//
// Loads the point records through the same host port the scanner front end uses,
// starts one frame, and compares every named checkpoint the core emits with the
// value tools/hwmodel.py produced for the same point set.  When the frame ends
// with valid=1 the 13 features are pushed through the frozen classifier RTL and
// the accumulator is compared with the hardware-model accumulator, so the check
// covers feature -> classification, not just feature production.
`include "src/ml_int13_params.vh"
`timescale 1ns/1ps
module tb_ml_num_core;
 localparam integer NPTS = 944;
 reg clk = 1'b0;
 reg rst_n = 1'b0;
 always #5 clk = ~clk;

 reg host_we = 1'b0;
 reg [10:0] host_addr = 11'd0;
 reg [63:0] host_wdata = 64'd0;
 reg start = 1'b0;
 reg [9:0] n_points = 10'd0;

 wire busy, done, valid, dbg_valid;
 wire [4:0] reason;
 wire [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] feature_bus;
 wire [7:0] dbg_id;
 wire signed [63:0] dbg_val;

 ml_num_core dut(.clk(clk), .rst_n(rst_n), .host_we(host_we),
                 .host_addr(host_addr), .host_wdata(host_wdata),
                 .start(start), .n_points(n_points), .busy(busy), .done(done),
                 .valid(valid), .reason(reason), .feature_bus(feature_bus),
                 .dbg_valid(dbg_valid), .dbg_id(dbg_id), .dbg_val(dbg_val));

 // ------------------------------------------------ frozen classifier (RTL) --
 reg req = 1'b0;
 wire clf_ready, clf_valid;
 wire [1:0] clf_class;
 wire signed [`ML_ACC_W-1:0] clf_acc;
 wire [3:0] clf_reason, clf_reason_feature;
 ml_int13_classifier u_clf(
  .clk(clk), .rst_n(rst_n), .request_valid(req), .request_ready(clf_ready),
  .feature_bus(feature_bus), .feature_valid(valid), .frame_id(12'd7),
  .config_version(8'h01), .cancel(1'b0), .result_valid(clf_valid),
  .result_frame_id(), .result_config(), .result_class(clf_class),
  .result_accumulator(clf_acc), .result_reason(clf_reason),
  .result_reason_feature(clf_reason_feature), .busy(), .dropped_requests());

 // ------------------------------------------------------------- vectors ----
 reg [63:0] pw [0:NPTS-1];
 reg [67:0] em [0:255];
 reg [1023:0] pts_file, exp_file;
 integer n, errs, seen, missing, first_bad, clf_errs, cyc_cap;
 reg [63:0] expv;
 reg exps;
 reg [255:0] seenmap;

 task note_bad(input [7:0] id, input [63:0] got, input [63:0] want, input [8*24-1:0] why);
  begin
   errs = errs + 1;
   if (first_bad == 0) begin
    first_bad = 1;
    $display("FAIL ck=%0d got=%0d want=%0d (%0s)", id, $signed(got), $signed(want), why);
   end
  end
 endtask

 reg trace = 1'b0;
 reg dbgc = 1'b0;

 // last sequencer position that was not the failure/idle state, for the dump
 reg [7:0] last_at = 8'd0;
 reg [4:0] last_stage = 5'd0;
 reg signed [103:0] snap_aur = 0;
 reg [63:0] snap_rv = 0, snap_ms = 0;
 reg signed [8:0] snap_shsum = 0;
 reg [7:0] snap_k = 0;
 reg [2:0] snap_a4 = 0, snap_b4 = 0, snap_k4 = 0;
 reg [5:0] snap_j6 = 0;
 reg [9:0] snap_i = 0;
 always @(posedge clk)
  if (rst_n && (dut.stage != 5'd0) && (dut.stage != 5'd17)) begin
   last_at <= {2'd0, dut.sub};
   last_stage <= dut.stage;
   snap_aur <= dut.aur; snap_rv <= dut.rv; snap_ms <= dut.mem_q;
   snap_shsum <= dut.shsum; snap_k <= dut.au_k;
   snap_a4 <= dut.a4; snap_b4 <= dut.b4; snap_k4 <= dut.k4;
   snap_j6 <= dut.j6; snap_i <= dut.i;
  end


 always @(posedge clk) begin
  if (rst_n && dbg_valid) begin
   expv = em[dbg_id][63:0];
   exps = em[dbg_id][64];
   if (trace)
    $display("  ck=%0d got=%0d want=%0d %0s", dbg_id, $signed(dbg_val),
             $signed(expv), (exps && (dbg_val === $signed(expv))) ? "ok" : "MISMATCH");
   if (!exps) note_bad(dbg_id, dbg_val, 64'sd0, "unexpected checkpoint");
   else if (dbg_val !== $signed(expv)) note_bad(dbg_id, dbg_val, expv, "value");
   else begin
    seen = seen + 1;
    seenmap[dbg_id] = 1'b1;
   end
  end
 end

 // optional coordinate-median probe
 always @(posedge clk) begin
  if (dbgc && rst_n) begin
   if ((dut.stage == 5'd2) && (dut.sub == 6'd5))
    $display("CMED cnt pass=%0d axis=%0d wsel=%0d i=%0d hv=%0d hbc=%0d", dut.pass, dut.axis,
             dut.wsel, dut.i, dut.hv, dut.hbc);
   if ((dut.stage == 5'd2) && (dut.sub == 6'd6))
    $display("CMED srch pass=%0d wsel=%0d i=%0d nhb=%0d rk=%0d baser=%0d fr=%b", dut.pass,
             dut.wsel, dut.i, dut.nhb[dut.i[3:0]], dut.rk, dut.baser, dut.fr);
  end
 end

 initial begin
  dbgc = $test$plusargs("CMED");
  errs = 0; seen = 0; missing = 0; first_bad = 0; clf_errs = 0;
  seenmap = 0;
  if (!$value$plusargs("PTS=%s", pts_file)) begin
   $display("FAIL no +PTS"); $finish;
  end
  if (!$value$plusargs("EXP=%s", exp_file)) begin
   $display("FAIL no +EXP"); $finish;
  end
  if (!$value$plusargs("N=%d", n_points)) begin
   $display("FAIL no +N"); $finish;
  end
  trace = $test$plusargs("TRACE");
  if (!$value$plusargs("CYC=%d", cyc_cap)) cyc_cap = 40000000;
  $readmemh(pts_file, pw);
  $readmemh(exp_file, em);
  repeat (4) @(negedge clk);
  rst_n = 1'b1;
  repeat (2) @(negedge clk);
  for (n = 0; n < NPTS; n = n + 1) begin
   host_we = 1'b1; host_addr = n[10:0]; host_wdata = pw[n];
   @(negedge clk);
  end
  host_we = 1'b0;
  @(negedge clk);
  start = 1'b1;
  @(negedge clk);
  start = 1'b0;
  n = 0;
  while (!done && n < cyc_cap) begin
   @(negedge clk);
   n = n + 1;
  end
  if (!done) begin
   $display("FAIL timeout after %0d cycles (stage=%0d sub=%0d i=%0d tbase=%0d tl_n=%0d tlvl=%0d it=%0d)",
            n, dut.stage, dut.sub, dut.i, dut.tbase, dut.tl_n, dut.tlvl, dut.it);
   $finish;
  end
  $display("core done after %0d cycles valid=%0b reason=%0d", n, valid, reason);
  // ---- end-to-end: RTL features -> frozen classifier RTL ------------------
  if (valid && em[200][64]) begin
   @(negedge clk);
   req = 1'b1;
   while (!clf_ready) @(negedge clk);
   @(negedge clk);
   req = 1'b0;
   n = 0;
   while (!clf_valid && n < 4000) begin
    @(negedge clk);
    n = n + 1;
   end
   if (!clf_valid) begin
    $display("FAIL classifier never published");
    errs = errs + 1;
   end else if (clf_acc !== $signed(em[200][63:0])) begin
    $display("FAIL classifier acc=%0d want=%0d class=%0d",
             clf_acc, $signed(em[200][63:0]), clf_class);
    errs = errs + 1;
   end else if ({30'd0, clf_class} !== em[201][63:0]) begin
    $display("FAIL classifier class=%0d want=%0d", clf_class, em[201][63:0]);
    errs = errs + 1;
   end else begin
    seen = seen + 1;
    seenmap[200] = 1'b1;
    seenmap[201] = 1'b1;
   end
  end else if (valid) begin
   $display("FAIL valid frame but no expected accumulator");
   errs = errs + 1;
  end else if (em[200][64]) begin
   $display("FAIL core reported INVALID (reason %0d) but a valid result was expected", reason);
   errs = errs + 1;
  end
  // ---- every expected checkpoint must have been produced ----------------
  for (n = 0; n < 256; n = n + 1)
    if (em[n][64] && !seenmap[n]) begin
     if (missing < 6) $display("FAIL checkpoint %0d never reported", n);
     missing = missing + 1;
    end
  errs = errs + missing;
  $display("DUMP last stage=%0d sub=%0d i=%0d j6=%0d a4=%0d b4=%0d k4=%0d",
           last_stage, last_at[5:0], snap_i, snap_j6, snap_a4, snap_b4, snap_k4);
  $display("DUMP aur=%h rv=%h mem=%h ak=%0d shsum=%0d",
           snap_aur, snap_rv, snap_ms, snap_k, snap_shsum);
  $display("DUMP tmed tlvl=%0d wsel=%0d rk=%0d baser=%0d nextcnt=%0d nmedv=%0d",
           dut.tlvl, dut.wsel, dut.rk, dut.baser, dut.nextcnt, dut.nmedv);
  begin : hsum
   integer hb; reg [11:0] acc; reg [11:0] mx;
   acc = 12'd0; mx = 12'd0;
   for (hb = 0; hb < 512; hb = hb + 1) begin
    acc = acc + dut.hmem[hb];
    if (dut.hmem[hb] > mx) mx = dut.hmem[hb];
   end
   $display("DUMP hist1 sum=%0d maxbin=%0d bin267=%0d", acc, mx, dut.hmem[267]);
  end
  $display("DUMP stage=%0d sub=%0d i=%0d j6=%0d a4=%0d b4=%0d k4=%0d it=%0d",
           dut.stage, dut.sub, dut.i, dut.j6, dut.a4, dut.b4, dut.k4, dut.it);
  $display("DUMP p0=%h p1=%h G00=%h G01=%h rhs0=%h t0=%h t1=%h",
           dut.mem[0], dut.mem[1], dut.mem[11'h600], dut.mem[11'h601],
           dut.mem[11'h620], dut.mem[11'h400], dut.mem[11'h401]);
  $display("CK seen=%0d errs=%0d missing=%0d", seen, errs, missing);
  if (errs == 0) $display("TEST:PASS ml_num_core");
  else           $display("TEST:FAIL ml_num_core");
  $finish;
 end
endmodule
