`ifndef ML_NUM_CORE_V
`define ML_NUM_CORE_V
`include "src/ml_int13_params.vh"

// ---------------------------------------------------------------------------
// ml_num_core : the whole finite-width outer-contour chain, one operation at a
// time, on one sequential arithmetic unit.
//
//   point list -> coordinate median (3 x 16-bin passes, per axis and per rank)
//              -> conditioning u = 2x-2med(x), U = u * 2^(13-m)
//              -> [ gram 5x5 -> 5x5 Gauss-Jordan -> coefficients -> geometry
//                   -> Q24 -> residuals t -> next admission mask ] x 3
//              -> robust median of t (3-level histogram, per rank)
//              -> rounding -> support / admission -> 13 features
//
// Every multiply / divide / square root / shift goes through ml_num_au, so the
// product, dividend and radicand widths are exactly the ones proved in
// docs/ARITH_SPEC.md.  Add / subtract / compare stay in the sequencer, where
// each declared node width is checked with fits().  There is no floating point
// and no saturation: a node that does not fit, an empty median set, a
// non-ellipse or a too-small pivot aborts the frame with a reason code and
// valid = 0.  Nothing is inherited from a previous frame.
//
// Memory map (64-bit words, 2048 deep) -- written by the scanner front end:
//   0x000+2i  point record  [9:0] x  [19:10] y  [21:20] side  [28:22] slot
//                           [36:29] step  [37] protect  [38] gram mask
//                           [39] admit  [40] support
//   0x001+2i  [13:0] U (signed)  [27:14] V (signed)      (filled by COND)
//   0x400+i   t (Q16 while fitting, per mille after rounding)
//   0x600+a*5+b  Gram entry (a<=b)     0x620+a  right-hand side
//   0x630+i*6+j  augmented matrix row i
// Histogram memory (10-bit counts, 1024 deep):
//   0..511 t level 1, 512..767 t level 2, 768..831 t level 3.
//
// The debug port is left unconnected by example_top and is therefore pruned in
// the board build; the bench uses it to compare one named checkpoint per stage.
// ---------------------------------------------------------------------------

module ml_num_core (
 input clk,
 input rst_n,
 input host_we,
 input [10:0] host_addr,
 input [63:0] host_wdata,
 input start,
 input [9:0] n_points,
 output reg busy,
 output reg done,
 output reg valid,
 output reg [4:0] reason,
 output [`ML_FEATURE_COUNT*`ML_INPUT_W-1:0] feature_bus,
 output reg dbg_valid,
 output reg [7:0] dbg_id,
 output reg signed [63:0] dbg_val
);
 localparam [9:0] MIN_ADMIT = 10'd24, MIN_FIT = 10'd40;
 localparam signed [31:0] SEL_BAND = 32'sd3932160;      // 60 << 16

 localparam [4:0] R_OK = 5'd0, R_TOO_FEW = 5'd1, R_MED_EMPTY = 5'd2,
                  R_DEGENERATE = 5'd3, R_COORD_RANGE = 5'd4, R_OVERFLOW = 5'd5,
                  R_NOT_POS = 5'd6, R_SINGULAR = 5'd7, R_PIVOT = 5'd8,
                  R_ILL_COND = 5'd9, R_NOT_ELLIPSE = 5'd10, R_CENTER = 5'd11,
                  R_PRECISION = 5'd12, R_ZERO_DEN = 5'd13, R_FEW_ADMIT = 5'd14,
                  R_MED_RANK = 5'd15, R_TOO_MANY = 5'd18, R_SQRT_NEG = 5'd17;

 localparam [10:0] T_BASE = 11'h400, G_BASE = 11'h600,
                   RH_BASE = 11'h620, A_BASE = 11'h630;

 localparam [4:0] S_IDLE = 5'd0, S_INIT = 5'd1, S_CMED = 5'd2, S_COND = 5'd3,
                  S_COND2 = 5'd4, S_GRAM = 5'd5, S_GDBG = 5'd6, S_SOLVE = 5'd7,
                  S_GEOM = 5'd8, S_RESID = 5'd9, S_TMED = 5'd10,
                  S_TROUND = 5'd11, S_SUP = 5'd12, S_ADMIT = 5'd13,
                  S_STAT = 5'd14, S_FINAL = 5'd15, S_DONE = 5'd16,
                  S_FAIL = 5'd17;
 localparam [5:0] SU_WAIT = 6'd63;
 localparam [2:0] O_MUL = 3'd1, O_DIV = 3'd2, O_SQ = 3'd3, O_SQR = 3'd4,
                  O_RSHR = 3'd5, O_SHL = 3'd6, O_DIVT = 3'd7;

 // ---------------------------------------------------------------- storage --
 reg [63:0] mem [0:2047];
 reg [63:0] mem_q;
 reg [9:0] hmem [0:1023];
 reg [11:0] h_q;

 reg [10:0] mem_raddr, mem_waddr;
 reg mem_we;
 reg [63:0] mem_wdata;
 reg [9:0] h_raddr, h_waddr;
 reg h_we;
 reg [11:0] h_wdata;



 // -------------------------------------------------------------------- AU ---
 reg au_go;
 reg [2:0] au_op;
 reg signed [103:0] au_a, au_b;
 reg [7:0] au_k, au_sig;
 wire signed [103:0] au_q;
 wire au_done, au_fail;
 wire [3:0] au_fc;
 ml_num_au u_au(.clk(clk), .rst_n(rst_n), .go(au_go), .op(au_op),
               .a_in(au_a), .b_in(au_b), .k_in(au_k), .sig_in(au_sig),
               .q(au_q), .done(au_done), .fail(au_fail), .fail_code(au_fc));

 // --------------------------------------------------------------- helpers ---
 function [6:0] blen;
  input [63:0] v;
  integer j;
  begin
   blen = 7'd0;
   for (j = 0; j < 64; j = j + 1) if (v[j]) blen = j[6:0] + 7'd1;
  end
 endfunction

 function fits;
  input signed [103:0] v;
  input [7:0] bits;
  reg signed [103:0] t;
  begin
   t = v >>> (bits - 8'd1);
   fits = (t == 104'sd0) || (t == -104'sd1);
  end
 endfunction

 function [63:0] abso;
  input signed [63:0] v;
  begin abso = v[63] ? (~v + 64'd1) : v; end
 endfunction

 // Every 64-bit word in the scratch memory holds a *signed* quantity, so a word
 // handed to the 104-bit arithmetic unit must be sign-extended first; a plain
 // zero-extended copy silently turns a small negative into a huge positive.
 function signed [103:0] sx;
  input [63:0] v;
  begin sx = {{40{v[63]}}, v}; end
 endfunction

 function sup_of;
  input [63:0] pm1, p0, pp1;
  input signed [15:0] tp, tn;
  begin
   sup_of = (pm1[21:20] == p0[21:20]) && (pp1[21:20] == p0[21:20]) &&
            (pm1[28:22] == p0[28:22] - 7'd1) && (pp1[28:22] == p0[28:22] + 7'd1) &&
            (tp > 16'sd6) && (tp <= 16'sd60) && (tn > 16'sd6) && (tn <= 16'sd60);
  end
 endfunction

 function admit_of;
  input signed [15:0] tv;
  input sp;
  begin
   if (tv < -16'sd15) admit_of = 1'b0;
   else if (tv <= 16'sd15) admit_of = 1'b1;
   else if (tv <= 16'sd60) admit_of = sp;
   else admit_of = 1'b0;
  end
 endfunction

 wire signed [63:0] ms = mem_q;

 // --------------------------------------------------------- FSM registers ---
 reg [4:0] stage;
 reg [5:0] sub, ret;
 reg signed [103:0] aur;
 reg [9:0] i, npts;
 reg [2:0] a4, b4, k4;
 reg [5:0] j6;
 reg [1:0] it, pass, axis, wsel, tlvl;

 reg signed [11:0] cx2, cy2;
 reg signed [103:0] uu, vv, wc;
 reg [12:0] rmax;
 reg [63:0] mx64;
 reg [4:0] mval, t1sh;
 // |u|,|v| of the point just consumed, folded into the running maximum in the
 // same cycle so the last point of the frame is part of R as well.
 wire [12:0] rmax_nx = (wc > $signed({91'd0, rmax})) ? wc[12:0] : rmax;

 reg signed [41:0] cf [0:4];
 reg signed [29:0] c20 [0:4];
 reg signed [31:0] c24 [0:4];
 reg signed [59:0] det40;
 reg signed [15:0] u0, v0;
 reg signed [61:0] fc40;
 reg signed [33:0] fc31;
 reg signed [19:0] a16, b16;
 reg signed [51:0] q0_50;
 reg signed [33:0] inv33;
 reg [9:0] fitcnt, nextcnt, iters, nmedv;
 reg signed [7:0] shv [0:4];
 reg signed [8:0] shsum, pscale, amt;

 reg [63:0] p4ac, pbe, pbd, numu, numv, au1, bu1, cv1, auu, buv, cvv;
 reg [63:0] qquad, qdu, qev, qlin, tdu0, tev0, tac, tac2, td2, ts1;
 reg [63:0] tnuma, ta2, tb2, tq45, tfc20;

 reg [10:0] lo1r [0:1];
 reg [10:0] lo2r [0:1];
 reg [10:0] medr [0:1];
 reg [10:0] lo_lo;
 reg [8:0] rk;
 reg [10:0] baser;
 reg fr, fr2;
 reg [9:0] nhb [0:15];
 reg [11:0] hv, hbc;

 reg signed [31:0] med2;
 reg signed [31:0] tlo1 [0:1];
 reg signed [31:0] tlo2 [0:1];
 reg signed [31:0] tmedv [0:1];
 reg signed [31:0] tlores;
 reg [11:0] tbase, tbin, tcnt;

 reg [63:0] r_a1, r_a2, r_b1, r_b2, r_c1, r_c2, r_d1, r_n;
 // creg[0..2] hold the monomials U*U, U*V, V*V (|U|,|V| <= 2^13-1, so a
 // monomial needs 27 signed bits); creg[3..4] hold U and V themselves.
 reg signed [26:0] creg [0:4];

 reg signed [15:0] out_max, in_max;
 reg [9:0] cnt_out, cnt_in, pcount, n_admit;
 reg [23:0] area, std2, ssum;
 reg [9:0] run, cur, newrun;
 reg signed [7:0] last_slot;
 reg [1:0] last_side;
 reg [7:0] gw, nwin;
 reg [1:0] wsd [0:7];
 reg [6:0] wsl [0:7]; reg [7:0] wst [0:7];
 reg [3:0] wcnt;
 reg [10:0] wsum;
 // `hit` is combinational on purpose: the bin that a stage just decided must
 // take part in the very same cycle's branch, otherwise the last bin of a rank
 // search silently uses the previous decision and reports MED_RANK.
 wire [10:0] cm_bsum = baser + {1'd0, nhb[i[3:0]]};
 wire cm_hit = !fr && (cm_bsum > {2'd0, rk});
 reg signed [15:0] fv [0:12];
 reg signed [15:0] tval, tprev;
 reg [63:0] pcur, keep1, keep2, gval, rv;
 reg [7:0] step_cur; reg [6:0] slot_cur;
 reg [1:0] side_cur;
 reg prot_cur, supb, admitb;
 // combinational run candidate: same reason as cm_hit above.
 wire [9:0] run_nx = ((side_cur == last_side) && (last_slot == (slot_cur - 7'd1)) &&
                      (cur != 10'd0)) ? (cur + 10'd1) : 10'd1;

 integer wi;
 genvar gi;
 generate
  for (gi = 0; gi < `ML_FEATURE_COUNT; gi = gi + 1) begin : gbus
   assign feature_bus[gi*`ML_INPUT_W +: `ML_INPUT_W] = fv[gi];
  end
 endgenerate

 reg wall;
 always @* begin
  wall = 1'b1;
  for (wi = 0; wi < 8; wi = wi + 1)
    if (wsd[wi] != wsd[7]) wall = 1'b0;
 end
 wire wslot_ok = ((wsl[0] - wsl[7]) == 7'd7);
 wire [10:0] wcand = wsum >> 3;

 wire [10:0] ad_p0 = {i, 1'b0};
 wire [10:0] ad_p1 = {i, 1'b0} + 11'd1;
 wire [10:0] ad_t = T_BASE + i;
 wire [10:0] ad_g = G_BASE + (a4 * 5 + b4);
 wire [10:0] ad_rh = RH_BASE + a4;

 // level selector of the t histogram
 wire signed [31:0] tl_lo = (tlvl == 2'd0) ? -32'sd4194304 :
                            ((tlvl == 2'd1) ? tlo1[wsel] : tlo2[wsel]);
 wire signed [31:0] tl_w = (tlvl == 2'd0) ? 32'sd16384 :
                         ((tlvl == 2'd1) ? 32'sd64 : 32'sd1);
 wire [4:0] tl_sh = (tlvl == 2'd0) ? 5'd14 : ((tlvl == 2'd1) ? 5'd6 : 5'd0);
 wire [11:0] tl_hb = (tlvl == 2'd0) ? 12'd0 : ((tlvl == 2'd1) ? 12'd512 : 12'd768);
// level 0 has 512 bins, which does not fit in 10 bits; the counter and its
// loop bound are 11 bits so the "last bin" test can actually fire.
 wire [10:0] tl_n = (tlvl == 2'd0) ? 11'd512 : ((tlvl == 2'd1) ? 11'd256 : 11'd64);
 // level 2 counts the whole level-1 bin (512 * 16k wide) into 256 bins of 64,
 // level 3 counts the whole level-2 bin into 64 unit bins, so the gate width is
 // the *parent* bin width, not the child one.
 wire signed [31:0] tl_hi = tl_lo + ((tlvl == 2'd1) ? 32'sd16384 : 32'sd64);
 wire tl_in = (tlvl == 2'd0) ? ((ms >= -SEL_BAND) && (ms <= SEL_BAND)) :
              ((ms >= tl_lo) && (ms < tl_hi));

 // RN dividend: 1024*(a16+b16) << (m-1)
 wire signed [103:0] rn_num =
   ({{84{1'b0}}, a16} <<< 10) + ({{84{1'b0}}, b16} <<< 10);
 wire signed [103:0] rn_num2 = rn_num <<< (mval - 5'd1);

 wire signed [103:0] tfcs = {{42{fc40[61]}}, fc40} <<< 5;   // fc << 5
 wire signed [103:0] m2fc20 = -({{62{tfc20[41]}}, tfc20[41:0]} <<< 1);
 wire signed [103:0] rn_hi = {{40{r_n[63]}}, r_n[63:0]} >>> 25;
 // 2*t_raw - med2: both terms are signed, so the subtraction must be signed too
 wire signed [63:0] d2v = $signed({{32{mem_q[31]}}, mem_q[31:0]}) * 64'sd2 - med2;
 wire inband = (aur[31] ? (-aur[31:0] <= 32'sd1638400) : (aur[31:0] <= 32'sd1638400));
 wire [63:0] absms = abso(ms);
 // t of the point currently on the memory bus (per mille, Q16-stored)
 wire signed [15:0] tq16 = mem_q[15:0];
 wire signed [103:0] detval = {{40{p4ac[63]}}, p4ac[63:0]} - aur;
 wire signed [103:0] fcval = aur + {{40{qlin[63]}}, qlin[63:0]} - 104'sd1099511627776;
 wire signed [103:0] q50v = {{40{tq45[63]}}, tq45[63:0]} <<< 5;

 reg [10:0] raddr_c;
 reg [9:0] haddr_c;

 always @(posedge clk) begin
  if (mem_we || host_we) mem[mem_we ? mem_waddr : host_addr] <= mem_we ? mem_wdata : host_wdata;
  mem_q <= mem[raddr_c];
  if (h_we) hmem[h_waddr] <= h_wdata[9:0];
  h_q <= {2'b00, hmem[haddr_c]};
 end

 // Read-address presentation.  The sequencer names the address in the setup
 // state and consumes the data in the next state, so the address must reach the
 // block RAM in the setup state: one synchronous read, no asynchronous path
 // through a 2048 x 64 array.
 always @* begin
  raddr_c = mem_raddr;
  haddr_c = h_raddr;
  case (stage)
   S_INIT:   if (sub == 6'd0) raddr_c = ad_p0;
   S_CMED:   if (sub == 6'd2) raddr_c = ad_p0;
   S_COND:   if (sub == 6'd1) raddr_c = ad_p0;
   S_COND2:  if (sub == 6'd4) raddr_c = ad_p0;
   S_GRAM: begin
    if (sub == 6'd1) raddr_c = ad_p0;
    else if (sub == 6'd2) raddr_c = ad_p1;
    else if (sub == 6'd7) raddr_c = ad_rh;
    else if (sub == 6'd11) raddr_c = ad_g;
   end
   S_GDBG: if (sub == 6'd1) begin
    case (k4)
     3'd0: raddr_c = G_BASE + 11'd0;
     3'd1: raddr_c = G_BASE + 11'd1;
     3'd2: raddr_c = G_BASE + 11'd6;
     3'd3: raddr_c = G_BASE + 11'd12;
     3'd4: raddr_c = G_BASE + 11'd18;
     3'd5: raddr_c = G_BASE + 11'd24;
     3'd6: raddr_c = RH_BASE + 11'd0;
     default: raddr_c = RH_BASE + 11'd4;
    endcase
   end
   S_SOLVE: begin
    case (sub)
     6'd1:  raddr_c = G_BASE + (j6[2:0] * 6);
     6'd10: raddr_c = G_BASE + ((i[2:0] <= j6[2:0] ? i[2:0] : j6[2:0]) * 5
                                + (i[2:0] <= j6[2:0] ? j6[2:0] : i[2:0]));
     6'd20: raddr_c = RH_BASE + i[2:0];
     6'd31: raddr_c = A_BASE + (i[2:0] * 6 + 6'd5);
     6'd34: raddr_c = A_BASE + (i[2:0] * 6 + 6'd5);
     6'd41: raddr_c = A_BASE + (i[2:0] * 6 + k4);
     6'd43: raddr_c = A_BASE + (b4 * 6 + k4);
     6'd45: raddr_c = A_BASE + (k4 * 6 + j6);
     6'd46: raddr_c = A_BASE + (b4 * 6 + j6);
     6'd50: raddr_c = A_BASE + (k4 * 6 + j6);
     6'd54: raddr_c = A_BASE + (i[2:0] * 6 + k4);
     6'd56: raddr_c = A_BASE + (k4 * 6 + j6);
     6'd59: raddr_c = A_BASE + (i[2:0] * 6 + j6);
     default: ;
    endcase
   end
   S_GEOM:  if (sub == 6'd1) raddr_c = A_BASE + (k4 * 6 + 6'd5);
   S_RESID: begin
    if (sub == 6'd2) raddr_c = ad_p1;
    else if (sub == 6'd18) raddr_c = ad_p0;
   end
   S_TMED: begin
    if (sub == 6'd3) raddr_c = ad_t;
    if (sub == 6'd4) haddr_c = tl_hb + ((ms - tl_lo) >>> tl_sh);
    if (sub == 6'd8) haddr_c = tbase + i[9:0];
   end
   S_TROUND: begin
    case (sub)
     6'd0: raddr_c = ad_t;
     6'd3: raddr_c = T_BASE + 11'd0;
     6'd4: raddr_c = T_BASE + 11'd1;
     6'd5: raddr_c = T_BASE + {1'b0, (npts >> 1)};
     6'd6: raddr_c = T_BASE + npts - 11'd1;
     default: ;
    endcase
   end
   S_SUP: begin
    case (sub)
     6'd0: raddr_c = ad_p0 - 11'd2;
     6'd1: raddr_c = ad_p0;
     6'd2: raddr_c = ad_p0 + 11'd2;
     6'd3: raddr_c = ad_t - 11'd1;
     6'd4: raddr_c = ad_t + 11'd1;
     default: ;
    endcase
   end
   S_ADMIT: begin
    if (sub == 6'd0) raddr_c = ad_p0;
    else if (sub == 6'd1) raddr_c = ad_t;
   end
   S_STAT: begin
    if (sub == 6'd0) raddr_c = ad_p0;
    else if (sub == 6'd1) raddr_c = ad_t;
   end
   default: ;
  endcase
 end

 // ------------------------------------------------------------------- FSM ---
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   stage <= S_IDLE; sub <= 6'd0; ret <= 6'd0; aur <= 0;
   busy <= 1'b0; done <= 1'b0; valid <= 1'b0; reason <= 5'd0;
   mem_we <= 1'b0; mem_raddr <= 11'd0; mem_waddr <= 11'd0; mem_wdata <= 64'd0;
   h_we <= 1'b0; h_raddr <= 10'd0; h_waddr <= 10'd0; h_wdata <= 12'd0;
   au_go <= 1'b0; au_op <= 3'd0; au_a <= 0; au_b <= 0; au_k <= 8'd0; au_sig <= 8'd0;
   dbg_valid <= 1'b0; dbg_id <= 8'd0; dbg_val <= 64'sd0;
   i <= 10'd0; npts <= 10'd0; a4 <= 3'd0; b4 <= 3'd0; k4 <= 3'd0; j6 <= 6'd0;
   it <= 2'd0; pass <= 2'd0; axis <= 2'd0; wsel <= 2'd0; tlvl <= 2'd0;
   cx2 <= 0; cy2 <= 0; rmax <= 13'd0; mx64 <= 64'd0; mval <= 5'd0; t1sh <= 5'd0;
   uu <= 0; vv <= 0; wc <= 0;
   det40 <= 0; u0 <= 0; v0 <= 0; fc40 <= 0; fc31 <= 0; a16 <= 0; b16 <= 0;
   q0_50 <= 0; inv33 <= 0; fitcnt <= 10'd0; nextcnt <= 10'd0; nmedv <= 10'd0;
   iters <= 10'd0; pscale <= 9'sd0; amt <= 9'sd0; shsum <= 9'sd0;
   lo_lo <= 11'd0; rk <= 9'd0; baser <= 11'd0; fr <= 1'b0; fr2 <= 1'b0;
   hv <= 12'd0; hbc <= 12'd0; med2 <= 32'sd0; tlores <= 32'sd0;
   tbase <= 12'd0; tbin <= 12'd0; tcnt <= 12'd0;
   out_max <= -16'sd32768; in_max <= -16'sd32768;
   cnt_out <= 10'd0; cnt_in <= 10'd0; pcount <= 10'd0; n_admit <= 10'd0;
   area <= 24'd0; std2 <= 24'd0; ssum <= 24'd0;
   run <= 10'd0; cur <= 10'd0; newrun <= 10'd0;
   last_slot <= -8'sd2; last_side <= 2'd0;
   gw <= 8'd255; nwin <= 8'd0; wcnt <= 4'd0; wsum <= 11'd0;
   tval <= 0; tprev <= 0; pcur <= 64'd0; keep1 <= 64'd0; keep2 <= 64'd0;
   gval <= 64'd0; rv <= 64'd0; step_cur <= 7'd0; slot_cur <= 7'd0;
   side_cur <= 2'd0; prot_cur <= 1'b0; supb <= 1'b0; admitb <= 1'b0;
   p4ac <= 0; pbe <= 0; pbd <= 0; numu <= 0; numv <= 0; au1 <= 0; bu1 <= 0;
   cv1 <= 0; auu <= 0; buv <= 0; cvv <= 0; qquad <= 0; qdu <= 0; qev <= 0;
   qlin <= 0; tdu0 <= 0; tev0 <= 0; tac <= 0; tac2 <= 0; td2 <= 0; ts1 <= 0;
   tnuma <= 0; ta2 <= 0; tb2 <= 0; tq45 <= 0; tfc20 <= 0;
   r_a1 <= 0; r_a2 <= 0; r_b1 <= 0; r_b2 <= 0; r_c1 <= 0; r_c2 <= 0;
   r_d1 <= 0; r_n <= 0;
   for (wi = 0; wi < 13; wi = wi + 1) fv[wi] <= 16'sd0;
   for (wi = 0; wi < 8; wi = wi + 1) begin
    wsd[wi] <= 2'd0; wsl[wi] <= 7'd0; wst[wi] <= 7'd0;
   end
   for (wi = 0; wi < 5; wi = wi + 1) begin
    cf[wi] <= 42'sd0; c20[wi] <= 30'sd0; c24[wi] <= 32'sd0; creg[wi] <= 27'sd0;
    shv[wi] <= 8'sd0;
   end
   for (wi = 0; wi < 16; wi = wi + 1) nhb[wi] <= 10'd0;
   for (wi = 0; wi < 2; wi = wi + 1) begin
    lo1r[wi] <= 11'd0; lo2r[wi] <= 11'd0; medr[wi] <= 11'd0;
    tlo1[wi] <= 32'sd0; tlo2[wi] <= 32'sd0; tmedv[wi] <= 32'sd0;
   end
  end else begin
   mem_we <= 1'b0;
   h_we <= 1'b0;
   dbg_valid <= 1'b0;

   if (sub == SU_WAIT) begin
    au_go <= 1'b0;
    if (au_fail) begin
     case (au_fc)
      4'd1: reason <= R_ZERO_DEN;
      4'd2: reason <= R_PRECISION;
      4'd3: reason <= R_OVERFLOW;
      4'd4: reason <= R_SQRT_NEG;
      default: reason <= R_OVERFLOW;
     endcase
     valid <= 1'b0;
     stage <= S_FAIL;
    end else if (au_done) begin
     aur <= au_q;
     sub <= ret;
    end
   end else case (stage)

   // -------------------------------------------------------------- idle ---
   S_IDLE: begin
    if (start && !busy) begin
     busy <= 1'b1; done <= 1'b0; valid <= 1'b0; reason <= R_OK;
     npts <= n_points; it <= 2'd0; fitcnt <= 10'd0; nextcnt <= 10'd0;
     iters <= 10'd0; axis <= 2'd0; wsel <= 2'd0;
     for (wi = 0; wi < 13; wi = wi + 1) fv[wi] <= 16'sd0;
     if (n_points > 10'd472) begin
      reason <= R_TOO_MANY; stage <= S_FAIL;
     end else if (n_points < MIN_FIT) begin
      reason <= R_TOO_FEW; stage <= S_FAIL;
     end else begin
      i <= 10'd0; sub <= 6'd0; stage <= S_INIT;
     end
    end
   end

   // --------------------------------- clear mask / admit / support bits ---
   S_INIT: begin
    case (sub)
     6'd0: begin mem_raddr <= ad_p0; sub <= 6'd1; end
     6'd1: begin pcur <= mem_q; sub <= 6'd2; end
     6'd2: begin
      mem_waddr <= ad_p0;
      // bit40 support = 0, bit39 admit = 0, bit38 gram mask = 1: the first
      // Gram pass sees every point, exactly like `mask = [True] * n` in the
      // reference, and the mask field is the one the Gram gate reads.
      mem_wdata <= {pcur[63:41], 1'b0, 1'b0, 1'b1, pcur[37:0]};
      mem_we <= 1'b1; sub <= 6'd3;
     end
     default: begin
      if (i == npts - 10'd1) begin
       i <= 10'd0; sub <= 6'd0; stage <= S_CMED; axis <= 2'd0; wsel <= 2'd0;
       pass <= 2'd0;
      end else begin i <= i + 10'd1; sub <= 6'd0; end
     end
    endcase
   end

   // ------------------------------- coordinate median: 2 axes x 2 ranks ---
   S_CMED: begin
    case (sub)
     6'd0: begin
      pass <= 2'd0; fr <= 1'b0; i <= 10'd0;
      rk <= (wsel == 2'd0) ? ((npts[9:0] - 10'd1) >> 1) : (npts >> 1);
      sub <= 6'd1;
     end
     6'd1: begin
      nhb[i[3:0]] <= 10'd0;
      if (i == 10'd15) begin i <= 10'd0; sub <= 6'd2; end
      else i <= i + 10'd1;
     end
     6'd2: begin mem_raddr <= ad_p0; sub <= 6'd3; end
     6'd3: begin
      hv <= (axis == 2'd0) ? {2'd0, mem_q[9:0]} : {2'd0, mem_q[19:10]};
      sub <= 6'd4;
     end
     6'd4: begin
      if (pass == 2'd0) hbc <= hv >> 6;
      else if (pass == 2'd1) hbc <= (hv - {2'd0, lo1r[wsel]}) >> 2;
      else hbc <= hv - {2'd0, lo2r[wsel]};
      sub <= 6'd5;
     end
     6'd5: begin
      if ((pass == 2'd0) ||
          ((pass == 2'd1) && (hv >= {2'd0, lo1r[wsel]}) &&
           (hv < {2'd0, lo1r[wsel]} + 12'd64)) ||
          ((pass == 2'd2) && (hv >= {2'd0, lo2r[wsel]}) &&
           (hv < {2'd0, lo2r[wsel]} + 12'd4)))
       nhb[hbc[3:0]] <= nhb[hbc[3:0]] + 10'd1;
      if (i == npts - 10'd1) begin
       i <= 10'd0; baser <= 11'd0; fr <= 1'b0; sub <= 6'd6;
      end else begin i <= i + 10'd1; sub <= 6'd2; end
     end
     6'd6: begin
      if (cm_hit) begin
       fr <= 1'b1;
       lo_lo <= (pass == 2'd0) ? (i << 6) :
                (pass == 2'd1) ? (lo1r[wsel] + (i << 2)) : (lo2r[wsel] + i);
       rk <= rk - baser[8:0];
      end else if (!fr) baser <= baser + {1'd0, nhb[i[3:0]]};
      if (i == 10'd15) begin
       if (!fr && !cm_hit) begin reason <= R_MED_RANK; stage <= S_FAIL; end
       else begin sub <= (pass == 2'd2) ? 6'd7 : 6'd8; i <= 10'd0; end
      end else i <= i + 10'd1;
     end
     6'd7: begin
      medr[wsel] <= lo_lo; sub <= 6'd9;
     end
     6'd8: begin
      if (pass == 2'd0) begin lo1r[wsel] <= lo_lo; pass <= 2'd1; end
      else begin lo2r[wsel] <= lo_lo; pass <= 2'd2; end
      baser <= 11'd0; fr <= 1'b0; sub <= 6'd1;
     end
     6'd9: begin
      if (wsel == 2'd0) begin wsel <= 2'd1; i <= 10'd0; pass <= 2'd0; sub <= 6'd0; end
      else if (axis == 2'd0) begin
       cx2 <= medr[0] + medr[1];
       dbg_valid <= 1'b1; dbg_id <= 8'd1;
       dbg_val <= {{52{medr[0][10]}}, medr[0]} + {{52{medr[1][10]}}, medr[1]};
       axis <= 2'd1; wsel <= 2'd0; i <= 10'd0; pass <= 2'd0; sub <= 6'd0;
      end else begin
       cy2 <= medr[0] + medr[1];
       med2 <= {9'd0, medr[0]} + {9'd0, medr[1]};
       dbg_valid <= 1'b1; dbg_id <= 8'd2;
       dbg_val <= {{52{medr[0][10]}}, medr[0]} + {{52{medr[1][10]}}, medr[1]};
       i <= 10'd0; sub <= 6'd0; stage <= S_COND;
      end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------- conditioning, pass 1 of 2 --
   S_COND: begin
    case (sub)
     6'd0: begin i <= 10'd0; rmax <= 13'd0; sub <= 6'd1; end
     6'd1: begin mem_raddr <= ad_p0; sub <= 6'd2; end
     6'd2: begin
      uu <= 2 * $signed({2'd0, mem_q[9:0]}) - {{92{cx2[11]}}, cx2};
      vv <= 2 * $signed({2'd0, mem_q[19:10]}) - {{92{cy2[11]}}, cy2};
      sub <= 6'd3;
     end
     6'd3: begin
      wc <= (uu[13] ? -uu : uu);
      if ((vv[13] ? -vv : vv) > (uu[13] ? -uu : uu)) wc <= (vv[13] ? -vv : vv);
      sub <= 6'd4;
     end
     default: begin
      // |u|,|v| that need more than 13 bits are the model's
      // "coordinate_range" failure, reported on the first offending point.
      if (wc > 104'sd8191) begin
       reason <= R_COORD_RANGE; stage <= S_FAIL;
      end else begin
       rmax <= rmax_nx;
       if (i == npts - 10'd1) begin
        if (rmax_nx == 13'd0) begin
         reason <= R_DEGENERATE; stage <= S_FAIL;
        end else begin
         mval <= blen({51'd0, rmax_nx});
         t1sh <= 5'd13 - blen({51'd0, rmax_nx});
         i <= 10'd0; sub <= 6'd0; stage <= S_COND2;
        end
       end else begin i <= i + 10'd1; sub <= 6'd1; end
      end
     end
    endcase
   end

   // ------------------------------------------- conditioning, pass 2 of 2 --
   S_COND2: begin
    case (sub)
     6'd0: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd3; dbg_val <= {59'd0, mval}; sub <= 6'd1;
     end
     6'd1: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd4; dbg_val <= 64'sd1 << t1sh; sub <= 6'd2;
     end
     6'd2: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd5; dbg_val <= {51'd0, rmax}; sub <= 6'd3;
     end
     6'd3: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd6; dbg_val <= {54'd0, npts};
      i <= 10'd0; sub <= 6'd4;
     end
     6'd4: begin mem_raddr <= ad_p0; sub <= 6'd5; end
     6'd5: begin
      uu <= 2 * $signed({2'd0, mem_q[9:0]}) - {{92{cx2[11]}}, cx2};
      vv <= 2 * $signed({2'd0, mem_q[19:10]}) - {{92{cy2[11]}}, cy2};
      au_op <= O_SHL; au_a <= 2 * $signed({2'd0, mem_q[9:0]}) - {{92{cx2[11]}}, cx2};
      au_b <= 0; au_k <= {3'd0, t1sh}; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd6; sub <= SU_WAIT;
     end
     6'd6: begin
      if (!fits(aur, 8'd14)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       uu <= aur;
       au_op <= O_SHL; au_a <= vv; au_b <= 0; au_k <= {3'd0, t1sh};
       au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd7; sub <= SU_WAIT;
      end
     end
     6'd7: begin
      if (!fits(aur, 8'd14)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= ad_p1;
       mem_wdata <= {36'd0, aur[13:0], uu[13:0]};
       mem_we <= 1'b1; sub <= 6'd8;
      end
     end
     default: begin
      if (i == npts - 10'd1) begin
       i <= 10'd0; it <= 2'd0; sub <= 6'd0; stage <= S_GRAM;
      end else begin i <= i + 10'd1; sub <= 6'd4; end
     end
    endcase
   end

   // --------------------------------------------------------------- gram ---
   S_GRAM: begin
    case (sub)
     6'd0: begin i <= 10'd0; fitcnt <= 10'd0; sub <= 6'd14; end
     6'd14: begin
      mem_waddr <= (i < 10'd25) ? (G_BASE + i) : (RH_BASE + i - 10'd25);
      mem_wdata <= 64'd0; mem_we <= 1'b1;
      if (i == 10'd29) begin i <= 10'd0; sub <= 6'd1; end
      else begin i <= i + 10'd1; sub <= 6'd14; end
     end
     6'd1: begin mem_raddr <= ad_p0; sub <= 6'd2; end
     6'd2: begin pcur <= mem_q; mem_raddr <= ad_p1; sub <= 6'd3; end
     6'd3: begin
      uu <= {{90{mem_q[13]}}, mem_q[13:0]};
      vv <= {{90{mem_q[27]}}, mem_q[27:14]};
      creg[3] <= {{13{mem_q[13]}}, mem_q[13:0]};
      creg[4] <= {{13{mem_q[27]}}, mem_q[27:14]};
      if (!pcur[38]) sub <= 6'd10;
      else begin
       fitcnt <= fitcnt + 10'd1;
       au_op <= O_MUL; au_a <= {{90{mem_q[13]}}, mem_q[13:0]};
       au_b <= {{90{mem_q[13]}}, mem_q[13:0]}; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd4; sub <= SU_WAIT;
      end
     end
     6'd4: begin
      if (!fits(aur, 8'd27)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       creg[0] <= aur[26:0];
       au_op <= O_MUL; au_a <= uu; au_b <= vv; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd5; sub <= SU_WAIT;
      end
     end
     6'd5: begin
      if (!fits(aur, 8'd27)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       creg[1] <= aur[26:0];
       au_op <= O_MUL; au_a <= vv; au_b <= vv; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd6; sub <= SU_WAIT;
      end
     end
     6'd6: begin
      if (!fits(aur, 8'd27)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin creg[2] <= aur[26:0]; a4 <= 3'd0; sub <= 6'd7; end
     end
     6'd7: begin mem_raddr <= ad_rh; sub <= 6'd8; end
     6'd8: begin gval <= mem_q; sub <= 6'd9; end
     6'd9: begin
      if (!fits({{40{gval[63]}}, gval[63:0]} + {{77{creg[a4][26]}}, creg[a4]},
                8'd36)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       mem_waddr <= ad_rh;
       mem_wdata <= gval + {{37{creg[a4][26]}}, creg[a4]};
       mem_we <= 1'b1;
       if (a4 == 3'd4) begin a4 <= 3'd0; b4 <= 3'd0; sub <= 6'd11; end
       else begin a4 <= a4 + 3'd1; sub <= 6'd7; end
      end
     end
     6'd10: begin
      if (i == npts - 10'd1) begin i <= 10'd0; sub <= 6'd0; stage <= S_GDBG; end
      else begin i <= i + 10'd1; sub <= 6'd1; end
     end
     6'd11: begin mem_raddr <= ad_g; sub <= 6'd12; end
     6'd12: begin
      gval <= mem_q;
      au_op <= O_MUL; au_a <= {{77{creg[a4][26]}}, creg[a4]};
      au_b <= {{77{creg[b4][26]}}, creg[b4]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd13; sub <= SU_WAIT;
     end
     6'd13: begin
      if (!fits({{40{gval[63]}}, gval[63:0]} + aur, 8'd62)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       mem_waddr <= ad_g; mem_wdata <= gval + aur[63:0]; mem_we <= 1'b1;
       if (b4 == 3'd4) begin
        if (a4 == 3'd4) sub <= 6'd10;
        else begin a4 <= a4 + 3'd1; b4 <= a4 + 3'd1; sub <= 6'd11; end
       end else begin b4 <= b4 + 3'd1; sub <= 6'd11; end
      end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------ gram read-back (dbg) --
   S_GDBG: begin
    case (sub)
     6'd0: begin k4 <= 3'd0; sub <= 6'd1; end
     6'd1: begin
      case (k4)
       3'd0: mem_raddr <= G_BASE + 11'd0;
       3'd1: mem_raddr <= G_BASE + 11'd1;
       3'd2: mem_raddr <= G_BASE + 11'd6;
       3'd3: mem_raddr <= G_BASE + 11'd12;
       3'd4: mem_raddr <= G_BASE + 11'd18;
       3'd5: mem_raddr <= G_BASE + 11'd24;
       3'd6: mem_raddr <= RH_BASE + 11'd0;
       default: mem_raddr <= RH_BASE + 11'd4;
      endcase
      sub <= 6'd2;
     end
     default: begin
      dbg_valid <= 1'b1;
      dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + {5'd0, k4};
      dbg_val <= ms;
      if (k4 == 3'd7) begin
       k4 <= 3'd0; sub <= 6'd0; i <= 10'd0; j6 <= 6'd0; stage <= S_SOLVE;
      end else begin k4 <= k4 + 3'd1; sub <= 6'd1; end
     end
    endcase
   end

   // -------------------------------------------------------------- solve ---
   S_SOLVE: begin
    case (sub)
     6'd0: begin j6 <= 6'd0; sub <= 6'd1; end
     6'd1: begin mem_raddr <= G_BASE + (j6[2:0] * 6); sub <= 6'd2; end
     6'd2: begin
      if (ms <= 64'sd0) begin reason <= R_NOT_POS; stage <= S_FAIL; end
      else begin amt <= $signed({1'b0, blen(abso(ms))}) - 9'sd28; sub <= 6'd3; end
     end
     6'd3: begin
      shv[j6[2:0]] <= amt >>> 1;
      dbg_valid <= 1'b1;
      dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd8 + {5'd0, j6[2:0]};
      dbg_val <= {{56{amt[8]}}, amt >>> 1};
      if (j6 == 6'd4) begin i <= 10'd0; j6 <= 6'd0; sub <= 6'd10; end
      else begin j6 <= j6 + 6'd1; sub <= 6'd1; end
     end
     6'd10: begin
      mem_raddr <= G_BASE + ((i[2:0] <= j6[2:0] ? i[2:0] : j6[2:0]) * 5
                             + (i[2:0] <= j6[2:0] ? j6[2:0] : i[2:0]));
      sub <= 6'd11;
     end
     6'd11: begin
      rv <= mem_q;
      shsum <= {{1{shv[i[2:0]][7]}}, shv[i[2:0]]}
             + {{1{shv[j6[2:0]][7]}}, shv[j6[2:0]]};
      sub <= 6'd12;
     end
     6'd12: begin
      if (shsum[8]) begin au_op <= O_SHL; au_k <= -shsum[7:0]; end
      else begin au_op <= O_RSHR; au_k <= shsum[7:0]; end
      au_a <= sx(rv); au_b <= 0; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd13; sub <= SU_WAIT;
     end
     6'd13: begin
      if (!fits(aur, 8'd31)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= A_BASE + (i[2:0] * 6 + j6);
       mem_wdata <= aur[63:0]; mem_we <= 1'b1;
       if (j6 == 6'd4) begin
        j6 <= 6'd0;
        if (i == 10'd4) begin i <= 10'd0; sub <= 6'd20; end
        else begin i <= i + 10'd1; sub <= 6'd10; end
       end else begin j6 <= j6 + 6'd1; sub <= 6'd10; end
      end
     end
     6'd20: begin mem_raddr <= RH_BASE + i[2:0]; sub <= 6'd21; end
     6'd21: begin
      rv <= mem_q;
      if (shv[i[2:0]][7]) begin au_op <= O_SHL; au_k <= -shv[i[2:0]]; end
      else begin au_op <= O_RSHR; au_k <= shv[i[2:0]]; end
      au_a <= sx(mem_q); au_b <= 0; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd22; sub <= SU_WAIT;
     end
     6'd22: begin
      if (!fits(aur, 8'd29)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= A_BASE + (i[2:0] * 6 + 6'd5);
       mem_wdata <= aur[63:0]; mem_we <= 1'b1;
       if (i == 10'd4) begin i <= 10'd0; sub <= 6'd30; end
       else begin i <= i + 10'd1; sub <= 6'd20; end
      end
     end
     6'd30: begin i <= 10'd0; mx64 <= 64'd0; sub <= 6'd31; end
     6'd31: begin mem_raddr <= A_BASE + (i[2:0] * 6 + 6'd5); sub <= 6'd32; end
     6'd32: begin
      if (abso(ms) > mx64) mx64 <= absms;
      if (i == 10'd4) begin i <= 10'd0; sub <= 6'd33; end
      else begin i <= i + 10'd1; sub <= 6'd31; end
     end
     6'd33: begin
      if (mx64 == 64'd0) begin reason <= R_SINGULAR; stage <= S_FAIL; end
      else begin
       pscale <= 9'sd27 - $signed({2'd0, blen(mx64)});
       i <= 10'd0; sub <= 6'd34;
      end
     end
     6'd34: begin mem_raddr <= A_BASE + (i[2:0] * 6 + 6'd5); sub <= 6'd35; end
     6'd35: begin
      dbg_valid <= 1'b1;
      dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd13;
      dbg_val <= {{55{pscale[8]}}, pscale};
      rv <= mem_q; amt <= -pscale; sub <= 6'd36;
     end
     6'd36: begin
      if (amt[8]) begin au_op <= O_SHL; au_k <= -amt[7:0]; end
      else begin au_op <= O_RSHR; au_k <= amt[7:0]; end
      au_a <= sx(rv); au_b <= 0; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd37; sub <= SU_WAIT;
     end
     6'd37: begin
      if (!fits(aur, 8'd29)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= A_BASE + (i[2:0] * 6 + 6'd5);
       mem_wdata <= aur[63:0]; mem_we <= 1'b1;
       if (i == 10'd4) begin i <= 10'd0; k4 <= 3'd0; sub <= 6'd40; end
       else begin i <= i + 10'd1; sub <= 6'd34; end
      end
     end
     6'd40: begin i <= {7'd0, k4}; mx64 <= 64'd0; b4 <= k4; sub <= 6'd41; end
     6'd41: begin mem_raddr <= A_BASE + (i[2:0] * 6 + k4); sub <= 6'd42; end
     6'd42: begin
      if (abso(ms) > mx64) begin
       mx64 <= absms; b4 <= i[2:0];
      end
      if (i[2:0] == 3'd4) begin i <= 10'd0; sub <= 6'd43; end
      else begin i <= i + 10'd1; sub <= 6'd41; end
     end
     6'd43: begin mem_raddr <= A_BASE + (b4 * 6 + k4); sub <= 6'd44; end
     6'd44: begin
      if (abso(ms) < 64'sd65536) begin reason <= R_PIVOT; stage <= S_FAIL; end
      else begin
       gval <= mem_q; j6 <= 6'd0;
       if (b4 != k4) sub <= 6'd45;
       else begin j6 <= {3'd0, k4} + 6'd1; sub <= 6'd50; end
      end
     end
     6'd45: begin mem_raddr <= A_BASE + (k4 * 6 + j6); sub <= 6'd46; end
     6'd46: begin
      keep1 <= mem_q; mem_raddr <= A_BASE + (b4 * 6 + j6); sub <= 6'd47;
     end
     6'd47: begin
      mem_waddr <= A_BASE + (k4 * 6 + j6);
      mem_wdata <= mem_q; mem_we <= 1'b1; sub <= 6'd48;
     end
     6'd48: begin
      mem_waddr <= A_BASE + (b4 * 6 + j6);
      mem_wdata <= keep1; mem_we <= 1'b1;
      if (j6 == 6'd5) begin j6 <= {3'd0, k4} + 6'd1; sub <= 6'd50; end
      else begin j6 <= j6 + 6'd1; sub <= 6'd45; end
     end
     6'd50: begin mem_raddr <= A_BASE + (k4 * 6 + j6); sub <= 6'd51; end
     6'd51: begin
      rv <= mem_q;
      au_op <= O_DIV; au_a <= sx(mem_q); au_b <= sx(gval);
      au_k <= 8'd28; au_sig <= 8'd20; au_go <= 1'b1;
      ret <= 6'd52; sub <= SU_WAIT;
     end
     6'd52: begin
      if (!fits(aur, 8'd36)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= A_BASE + (k4 * 6 + j6);
       mem_wdata <= aur[63:0]; mem_we <= 1'b1;
       if (j6 == 6'd5) begin i <= 10'd0; sub <= 6'd53; end
       else begin j6 <= j6 + 6'd1; sub <= 6'd50; end
      end
     end
     6'd53: begin
      mem_waddr <= A_BASE + (k4 * 6 + k4);
      mem_wdata <= 64'd268435456; mem_we <= 1'b1;
      i <= 10'd0; sub <= 6'd54;
     end
     6'd54: begin
      if (i[2:0] == 3'd5) begin
       if (k4 == 3'd4) begin i <= 10'd0; sub <= 6'd0; stage <= S_GEOM; end
       else begin k4 <= k4 + 3'd1; sub <= 6'd40; end
      end else if (i[2:0] == k4) begin
       i <= i + 10'd1;
      end else begin
       mem_raddr <= A_BASE + (i[2:0] * 6 + k4); sub <= 6'd55;
      end
     end
     6'd55: begin
      keep1 <= mem_q;
      if (ms == 64'sd0) begin
       mem_waddr <= A_BASE + (i[2:0] * 6 + k4);
       mem_wdata <= 64'd0; mem_we <= 1'b1;
       i <= i + 10'd1; sub <= 6'd54;
      end else if (abso(ms) >= 64'sd1073741824) begin
       reason <= R_ILL_COND; stage <= S_FAIL;
      end else begin
       j6 <= {3'd0, k4} + 6'd1; sub <= 6'd56;
      end
     end
     6'd56: begin mem_raddr <= A_BASE + (k4 * 6 + j6); sub <= 6'd57; end
     6'd57: begin
      rv <= mem_q;
      if (abso(ms) >= 64'sd1073741824) begin
       reason <= R_ILL_COND; stage <= S_FAIL;
      end else begin
       au_op <= O_MUL; au_a <= sx(keep1); au_b <= sx(mem_q); au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd58; sub <= SU_WAIT;
      end
     end
     6'd58: begin
      au_op <= O_RSHR; au_a <= aur; au_b <= 0; au_k <= 8'd28; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd59; sub <= SU_WAIT;
     end
     6'd59: begin mem_raddr <= A_BASE + (i[2:0] * 6 + j6); sub <= 6'd60; end
     6'd60: begin
      if (!fits({{40{mem_q[63]}}, mem_q[63:0]} - aur, 8'd62)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       mem_waddr <= A_BASE + (i[2:0] * 6 + j6);
       mem_wdata <= mem_q - aur[63:0]; mem_we <= 1'b1;
       if (j6 == 6'd5) sub <= 6'd61;
       else begin j6 <= j6 + 6'd1; sub <= 6'd56; end
      end
     end
     6'd61: begin
      mem_waddr <= A_BASE + (i[2:0] * 6 + k4);
      mem_wdata <= 64'd0; mem_we <= 1'b1;
      i <= i + 10'd1; sub <= 6'd54;
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------------ geometry --
   S_GEOM: begin
    case (sub)
     6'd0: begin k4 <= 3'd0; sub <= 6'd1; end
     6'd1: begin mem_raddr <= A_BASE + (k4 * 6 + 6'd5); sub <= 6'd2; end
     6'd2: begin
      rv <= mem_q;
      amt <= shv[k4] + pscale - ((k4 <= 3'd2) ? 9'sd30 : 9'sd17);
      sub <= 6'd3;
     end
     6'd3: begin
      if (amt[8]) begin au_op <= O_SHL; au_k <= -amt[7:0]; end
      else begin au_op <= O_RSHR; au_k <= amt[7:0]; end
      au_a <= sx(rv); au_b <= 0; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd4; sub <= SU_WAIT;
     end
     6'd4: begin
      if (!fits(aur, 8'd42)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       cf[k4] <= aur[41:0];
       dbg_valid <= 1'b1;
       dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd14 + {5'd0, k4};
       dbg_val <= {{22{aur[41]}}, aur[41:0]};
       if (k4 == 3'd4) begin k4 <= 3'd0; sub <= 6'd5; end
       else begin k4 <= k4 + 3'd1; sub <= 6'd1; end
      end
     end
     6'd5: begin
      au_op <= O_RSHR; au_a <= {{62{cf[k4][41]}}, cf[k4]}; au_b <= 0;
      au_k <= 8'd12; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd6; sub <= SU_WAIT;
     end
     6'd6: begin
      if (!fits(aur, 8'd30)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       c20[k4] <= aur[29:0];
       if (k4 == 3'd4) begin k4 <= 3'd0; sub <= 6'd7; end
       else begin k4 <= k4 + 3'd1; sub <= 6'd5; end
      end
     end
     6'd7: begin
      au_op <= O_MUL; au_a <= {{74{1'b0}}, c20[0]} <<< 2;
      au_b <= {{74{c20[2][29]}}, c20[2]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd8; sub <= SU_WAIT;
     end
     6'd8: begin
      p4ac <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[1][29]}}, c20[1]};
      au_b <= {{74{c20[1][29]}}, c20[1]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd9; sub <= SU_WAIT;
     end
     6'd9: begin
      if (!fits({{40{p4ac[63]}}, p4ac[63:0]} - aur, 8'd60)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (detval <= 104'sd0) begin
       reason <= R_NOT_ELLIPSE; stage <= S_FAIL;
      end else if (c20[0] <= 30'sd0) begin
       reason <= R_NOT_ELLIPSE; stage <= S_FAIL;
      end else begin
       det40 <= detval[59:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd19;
       dbg_val <= p4ac - aur[63:0];
       au_op <= O_MUL; au_a <= {{74{c20[1][29]}}, c20[1]};
       au_b <= {{74{c20[4][29]}}, c20[4]}; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd10; sub <= SU_WAIT;
      end
     end
     6'd10: begin
      pbe <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[2][29]}}, c20[2]} <<< 1;
      au_b <= {{74{c20[3][29]}}, c20[3]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd11; sub <= SU_WAIT;
     end
     6'd11: begin
      if (!fits({{40{pbe[63]}}, pbe[63:0]} - aur, 8'd60)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       numu <= pbe - aur[63:0];
       au_op <= O_MUL; au_a <= {{74{c20[1][29]}}, c20[1]};
       au_b <= {{74{c20[3][29]}}, c20[3]}; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd12; sub <= SU_WAIT;
      end
     end
     6'd12: begin
      pbd <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[0][29]}}, c20[0]} <<< 1;
      au_b <= {{74{c20[4][29]}}, c20[4]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd13; sub <= SU_WAIT;
     end
     6'd13: begin
      if (!fits({{40{pbd[63]}}, pbd[63:0]} - aur, 8'd60)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       numv <= pbd - aur[63:0];
       au_op <= O_DIV; au_a <= sx(numu); au_b <= {{44{det40[59]}}, det40};
       au_k <= 8'd13; au_sig <= 8'd22; au_go <= 1'b1;
       ret <= 6'd14; sub <= SU_WAIT;
      end
     end
     6'd14: begin
      if (!fits(aur, 8'd16)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       u0 <= aur[15:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd20;
       dbg_val <= {{48{aur[15]}}, aur[15:0]};
       au_op <= O_DIV; au_a <= sx(numv); au_b <= {{44{det40[59]}}, det40};
       au_k <= 8'd13; au_sig <= 8'd22; au_go <= 1'b1;
       ret <= 6'd15; sub <= SU_WAIT;
      end
     end
     6'd15: begin
      if (!fits(aur, 8'd16)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else if ((aur[15:0] == 16'sh8000) || (u0 == 16'sh8000)) begin
       reason <= R_CENTER; stage <= S_FAIL;
      end else begin
       v0 <= aur[15:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd21;
       dbg_val <= {{48{aur[15]}}, aur[15:0]};
       au_op <= O_MUL; au_a <= {{74{c20[0][29]}}, c20[0]}; au_b <= {{88{u0[15]}}, u0};
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd16; sub <= SU_WAIT;
      end
     end
     6'd16: begin
      au1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= {{88{u0[15]}}, u0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd17; sub <= SU_WAIT;
     end
     6'd17: begin
      auu <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[1][29]}}, c20[1]}; au_b <= {{88{u0[15]}}, u0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd18; sub <= SU_WAIT;
     end
     6'd18: begin
      bu1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= {{88{v0[15]}}, v0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd19; sub <= SU_WAIT;
     end
     6'd19: begin
      buv <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[2][29]}}, c20[2]}; au_b <= {{88{v0[15]}}, v0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd20; sub <= SU_WAIT;
     end
     6'd20: begin
      cv1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= {{88{v0[15]}}, v0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd21; sub <= SU_WAIT;
     end
     6'd21: begin
      cvv <= aur[63:0];
      if (!fits({{40{auu[63]}}, auu[63:0]} + {{40{buv[63]}}, buv[63:0]}, 8'd65)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (!fits({{40{auu[63]}}, auu[63:0]} + {{40{buv[63]}}, buv[63:0]}
                         + {{40{aur[63]}}, aur[63:0]}, 8'd65)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       qquad <= auu + buv + aur[63:0];
       au_op <= O_MUL; au_a <= {{74{c20[3][29]}}, c20[3]}; au_b <= {{88{u0[15]}}, u0};
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd22; sub <= SU_WAIT;
      end
     end
     6'd22: begin
      qdu <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[4][29]}}, c20[4]}; au_b <= {{88{v0[15]}}, v0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd23; sub <= SU_WAIT;
     end
     6'd23: begin
      qev <= aur[63:0];
      if (!fits({{40{qdu[63]}}, qdu[63:0]} + {{40{aur[63]}}, aur[63:0]}, 8'd48)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       qlin <= (qdu + aur[63:0]) << 7;
       au_op <= O_RSHR; au_a <= sx(qquad); au_b <= 0; au_k <= 8'd6; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd24; sub <= SU_WAIT;
      end
     end
     6'd24: begin
      if (!fits(fcval, 8'd63)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (fcval >= 0) begin
       reason <= R_NOT_ELLIPSE; stage <= S_FAIL;
      end else begin
       fc40 <= fcval[61:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd22;
       dbg_val <= fcval[63:0];
       au_op <= O_RSHR; au_a <= fcval;
       au_b <= 0; au_k <= 8'd9; au_sig <= 8'd0; au_go <= 1'b1;
       ret <= 6'd25; sub <= SU_WAIT;
      end
     end
     6'd25: begin
      if (!fits(aur, 8'd40)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else if (aur == 0) begin reason <= R_PRECISION; stage <= S_FAIL; end
      else begin
       fc31 <= aur[33:0];
       au_op <= O_RSHR; au_a <= {{42{fc40[61]}}, fc40}; au_b <= 0;
       au_k <= 8'd20; au_sig <= 8'd0; au_go <= 1'b1;
       ret <= 6'd26; sub <= SU_WAIT;
      end
     end
     6'd26: begin
      tfc20 <= aur[63:0]; tac <= c20[0] - c20[2]; sub <= 6'd27;
     end
     6'd27: begin
      if (!fits({{40{tac[63]}}, tac[63:0]}, 8'd31)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       au_op <= O_MUL; au_a <= {{40{tac[63]}}, tac[63:0]};
       au_b <= {{40{tac[63]}}, tac[63:0]}; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd28; sub <= SU_WAIT;
      end
     end
     6'd28: begin
      tac2 <= aur[63:0];
      au_op <= O_MUL; au_a <= {{74{c20[1][29]}}, c20[1]};
      au_b <= {{74{c20[1][29]}}, c20[1]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd29; sub <= SU_WAIT;
     end
     6'd29: begin
      if (!fits({{40{tac2[63]}}, tac2[63:0]} + {{40{aur[63]}}, aur[63:0]}, 8'd58)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       td2 <= tac2 + aur[63:0];
       au_op <= O_SQR; au_a <= {{40{tac2[63]}}, tac2[63:0]} + {{40{aur[63]}}, aur[63:0]};
       au_b <= 0; au_k <= 8'd0;
       au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd30; sub <= SU_WAIT;
      end
     end
     6'd30: begin
      ts1 <= {{74{c20[0][29]}}, c20[0]} + {{74{c20[2][29]}}, c20[2]} + aur;
      if (!fits({{74{c20[0][29]}}, c20[0]} + {{74{c20[2][29]}}, c20[2]} + aur, 8'd28)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (({{74{c20[0][29]}}, c20[0]} + {{74{c20[2][29]}}, c20[2]} + aur) <= 0) begin
       reason <= R_NOT_ELLIPSE; stage <= S_FAIL;
      end else begin
       au_op <= O_MUL; au_a <= m2fc20;
       au_b <= {{74{c20[0][29]}}, c20[0]} + {{74{c20[2][29]}}, c20[2]} + aur;
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd31; sub <= SU_WAIT;
      end
     end
     6'd31: begin
      tnuma <= aur[63:0];
      au_op <= O_DIV; au_a <= aur; au_b <= {{44{det40[59]}}, det40};
      au_k <= 8'd32; au_sig <= 8'd22; au_go <= 1'b1; ret <= 6'd32; sub <= SU_WAIT;
     end
     6'd32: begin
      if (!fits(aur, 8'd36)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else if (aur <= 0) begin reason <= R_NOT_ELLIPSE; stage <= S_FAIL; end
      else begin
       ta2 <= aur[63:0];
       au_op <= O_DIV; au_a <= m2fc20;
       au_b <= {{74{ts1[29]}}, ts1[29:0]}; au_k <= 8'd32; au_sig <= 8'd20;
       au_go <= 1'b1; ret <= 6'd33; sub <= SU_WAIT;
      end
     end
     6'd33: begin
      if (!fits(aur, 8'd36)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else if (aur <= 0) begin reason <= R_NOT_ELLIPSE; stage <= S_FAIL; end
      else begin
       tb2 <= aur[63:0];
       au_op <= O_SQR; au_a <= sx(ta2); au_b <= 0; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd34; sub <= SU_WAIT;
      end
     end
     6'd34: begin
      if (!fits(aur, 8'd20)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       a16 <= aur[19:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd23;
       dbg_val <= {{44{aur[19]}}, aur[19:0]};
       au_op <= O_SQR; au_a <= sx(tb2); au_b <= 0; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd35; sub <= SU_WAIT;
      end
     end
     6'd35: begin
      if (!fits(aur, 8'd20)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       if (aur[19:0] > a16) begin b16 <= a16; a16 <= aur[19:0]; end
       else b16 <= aur[19:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd24;
       dbg_val <= {{44{aur[19]}}, aur[19:0]};
       au_op <= O_MUL; au_a <= {{62{cf[3][41]}}, cf[3]}; au_b <= {{88{u0[15]}}, u0};
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd36; sub <= SU_WAIT;
      end
     end
     6'd36: begin
      tdu0 <= aur[63:0];
      au_op <= O_MUL; au_a <= {{62{cf[4][41]}}, cf[4]}; au_b <= {{88{v0[15]}}, v0};
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd37; sub <= SU_WAIT;
     end
     6'd37: begin
      tev0 <= aur[63:0];
      sub <= 6'd38;
     end
     6'd38: begin
      if (!fits(tfcs, 8'd67)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       tq45 <= tfcs + 104'sd35184372088832 - {{40{tdu0[63]}}, tdu0[63:0]}
               - {{40{tev0[63]}}, tev0[63:0]};
       sub <= 6'd39;
      end
     end
     6'd39: begin
      if (!fits({{40{tq45[63]}}, tq45[63:0]}, 8'd48)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (!fits(q50v, 8'd52)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       q0_50 <= q50v[51:0];
       dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd25;
       dbg_val <= q50v[63:0];
       k4 <= 3'd0;
       sub <= 6'd40;
      end
     end
     6'd40: begin
      au_op <= O_RSHR; au_a <= {{62{cf[k4][41]}}, cf[k4]}; au_b <= 0;
      au_k <= 8'd8; au_sig <= 8'd0; au_go <= 1'b1;
      ret <= 6'd41; sub <= SU_WAIT;
     end
     6'd41: begin
      if (!fits(aur, 8'd32)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       c24[k4] <= aur[31:0];
       if (k4 == 3'd4) begin i <= 10'd0; sub <= 6'd0; stage <= S_RESID; end
       else begin k4 <= k4 + 3'd1; sub <= 6'd40; end
      end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ----------------------------------------------------------- residuals --
   S_RESID: begin
    case (sub)
     6'd0: begin
      au_op <= O_DIV; au_a <= 104'sd4611686018427387904;
      au_b <= ~{{70{fc31[33]}}, fc31} + 104'sd1; au_k <= 8'd0; au_sig <= 8'd28;
      au_go <= 1'b1; ret <= 6'd1; sub <= SU_WAIT;
     end
     6'd1: begin
      if (!fits(aur, 8'd34)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin inv33 <= aur[33:0]; i <= 10'd0; nextcnt <= 10'd0; sub <= 6'd2; end
     end
     6'd2: begin mem_raddr <= ad_p1; sub <= 6'd3; end
     6'd3: begin
      uu <= {{90{mem_q[13]}}, mem_q[13:0]};
      vv <= {{90{mem_q[27]}}, mem_q[27:14]};
      au_op <= O_MUL; au_a <= {{72{c24[0][31]}}, c24[0]};
      au_b <= {{90{mem_q[13]}}, mem_q[13:0]}; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd4; sub <= SU_WAIT;
     end
     6'd4: begin
      r_a1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= uu; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd5; sub <= SU_WAIT;
     end
     6'd5: begin
      r_a2 <= aur[63:0];
      au_op <= O_MUL; au_a <= {{72{c24[1][31]}}, c24[1]}; au_b <= uu;
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd6; sub <= SU_WAIT;
     end
     6'd6: begin
      r_b1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= vv; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd7; sub <= SU_WAIT;
     end
     6'd7: begin
      r_b2 <= aur[63:0];
      au_op <= O_MUL; au_a <= {{72{c24[2][31]}}, c24[2]}; au_b <= vv;
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd8; sub <= SU_WAIT;
     end
     6'd8: begin
      r_c1 <= aur[63:0];
      au_op <= O_MUL; au_a <= aur; au_b <= vv; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd9; sub <= SU_WAIT;
     end
     6'd9: begin
      r_c2 <= aur[63:0];
      if (!fits({{40{r_a2[63]}}, r_a2[63:0]} + {{40{r_b2[63]}}, r_b2[63:0]}, 8'd63)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (!fits({{40{r_a2[63]}}, r_a2[63:0]} + {{40{r_b2[63]}}, r_b2[63:0]}
                         + {{40{aur[63]}}, aur[63:0]}, 8'd63)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       r_n <= r_a2 + r_b2 + aur[63:0];
       au_op <= O_MUL; au_a <= {{72{c24[3][31]}}, c24[3]}; au_b <= uu;
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd10; sub <= SU_WAIT;
      end
     end
     6'd10: begin
      r_d1 <= aur[63:0];
      au_op <= O_MUL; au_a <= {{72{c24[4][31]}}, c24[4]}; au_b <= vv;
      au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd11; sub <= SU_WAIT;
     end
     6'd11: begin
      if (!fits({{40{r_d1[63]}}, r_d1[63:0]} + {{40{aur[63]}}, aur[63:0]}, 8'd60)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (!fits(({{40{r_d1[63]}}, r_d1[63:0]} + {{40{aur[63]}}, aur[63:0]}) <<< 13,
                         8'd60)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       rv <= (r_d1 + aur[63:0]) << 13;
       sub <= 6'd12;
      end
     end
     6'd12: begin
      if (!fits({{40{r_n[63]}}, r_n[63:0]} + {{40{rv[63]}}, rv[63:0]}, 8'd62)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else if (!fits({{40{r_n[63]}}, r_n[63:0]} + {{40{rv[63]}}, rv[63:0]}
                         + {{52{q0_50[51]}}, q0_50}, 8'd62)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       r_n <= r_n + rv + {{52{q0_50[51]}}, q0_50};
       sub <= 6'd13;
      end
     end
     6'd13: begin
      if (!fits(rn_hi, 8'd40)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       au_op <= O_MUL; au_a <= rn_hi; au_b <= {{70{inv33[33]}}, inv33};
       au_k <= 8'd0; au_sig <= 8'd0; au_go <= 1'b1; ret <= 6'd14; sub <= SU_WAIT;
      end
     end
     6'd14: begin
      keep1 <= aur >>> 16; sub <= 6'd15;
     end
     6'd15: begin
      au_op <= O_MUL; au_a <= 104'sd500;
      au_b <= sx(keep1) - 104'sd1099511627776; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd16; sub <= SU_WAIT;
     end
     6'd16: begin
      if (!fits(aur, 8'd64)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       au_op <= O_RSHR; au_a <= aur; au_b <= 0; au_k <= 8'd24; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd17; sub <= SU_WAIT;
      end
     end
     6'd17: begin
      if (!fits(aur, 8'd32)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= ad_t; mem_wdata <= {{32{aur[31]}}, aur[31:0]}; mem_we <= 1'b1;
       if (aur[31] ? (-aur[31:0] <= 32'sd1638400) : (aur[31:0] <= 32'sd1638400))
        nextcnt <= nextcnt + 10'd1;
       sub <= 6'd18;
      end
     end
     6'd18: begin mem_raddr <= ad_p0; sub <= 6'd19; end
     6'd19: begin
      mem_waddr <= ad_p0;
      // bit38 carries the next Gram mask: `abs(t) <= band` is exactly the
      // reference's `newmask`, which the following iteration feeds to
      // `gram(rows, mask)`.  bit39 keeps the same value as the provisional
      // admit so nothing downstream can observe an undefined field.
      mem_wdata <= {mem_q[63:40], inband, inband, mem_q[37:0]};
      mem_we <= 1'b1;
      if (i == npts - 10'd1) sub <= 6'd20;
      else begin i <= i + 10'd1; sub <= 6'd2; end
     end
     // fit_count / next_count are per-iteration results, so they are published
     // once, after the last point, not on every point of the pass.
     6'd20: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd26;
      dbg_val <= {54'd0, fitcnt};
      sub <= 6'd21;
     end
     6'd21: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd16 + {3'd0, it} * 8'd28 + 8'd27;
      dbg_val <= {54'd0, nextcnt};
      iters <= {8'd0, it} + 10'd1;
      if ((nextcnt < MIN_ADMIT) || (it == 2'd2))
       begin i <= 10'd0; sub <= 6'd0; wsel <= 2'd0; tlvl <= 2'd0;
             stage <= S_TMED; end
      else begin it <= it + 2'd1; i <= 10'd0; sub <= 6'd0; stage <= S_GRAM; end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------- median of t ----
   S_TMED: begin
    case (sub)
     // wsel is *not* reset here: sub 0 is also the restart point for the second
     // median, so resetting it would redo the first one forever.
     6'd0: begin
      tlvl <= 2'd0; i <= 10'd0; nextcnt <= 10'd0;
      sub <= 6'd1;
     end
     6'd1: begin
      i <= 10'd0; tbase <= tl_hb; sub <= 6'd2;
     end
     6'd2: begin
      h_waddr <= tbase + i[9:0]; h_wdata <= 12'd0; h_we <= 1'b1;
      if (i == tl_n - 10'd1) begin i <= 10'd0; sub <= 6'd3; end
      else i <= i + 10'd1;
     end
     6'd3: begin mem_raddr <= ad_t; sub <= 6'd4; end
     6'd4: begin
      if (tl_in) begin h_raddr <= tl_hb + ((ms - tl_lo) >>> tl_sh); sub <= 6'd5; end
      else sub <= 6'd7;
     end
     6'd5: begin tcnt <= h_q; sub <= 6'd6; end
     6'd6: begin
      h_waddr <= tl_hb + ((ms - tl_lo) >>> tl_sh);
      h_wdata <= tcnt + 12'd1; h_we <= 1'b1;
      if (tlvl == 2'd0) nextcnt <= nextcnt + 10'd1;
      sub <= 6'd7;
     end
     6'd7: begin
      if (i == npts - 10'd1) begin
       if (tlvl == 2'd0) begin
        if (nextcnt == 10'd0) begin reason <= R_MED_EMPTY; stage <= S_FAIL; end
        else begin
         rk <= (wsel == 2'd0) ? ((nextcnt - 10'd1) >> 1) : (nextcnt >> 1);
         if (wsel == 2'd0) nmedv <= nextcnt;
         i <= 10'd0; baser <= 11'd0; fr <= 1'b0; sub <= 6'd8;
        end
       end else begin
        i <= 10'd0; baser <= 11'd0; fr <= 1'b0; sub <= 6'd8;
       end
      end else begin i <= i + 10'd1; sub <= 6'd3; end
     end
     6'd8: begin h_raddr <= tbase + i[9:0]; sub <= 6'd9; end
     6'd9: begin tcnt <= h_q; sub <= 6'd10; end
     6'd10: begin
      if (baser + tcnt > {2'd0, rk}) begin
       tlores <= tl_lo + $signed({22'd0, i[9:0]}) * tl_w;
       rk <= rk - baser[8:0];
       sub <= 6'd11;
      end else begin
       baser <= baser + tcnt;
       if (i == tl_n - 10'd1) begin reason <= R_MED_RANK; stage <= S_FAIL; end
       else begin i <= i + 10'd1; sub <= 6'd8; end
      end
     end
     6'd11: begin
      if (tlvl == 2'd0) begin tlo1[wsel] <= tlores; tlvl <= 2'd1; sub <= 6'd1; end
      else if (tlvl == 2'd1) begin tlo2[wsel] <= tlores; tlvl <= 2'd2; sub <= 6'd1; end
      else begin
       tmedv[wsel] <= tlores;
       if (wsel == 2'd0) begin wsel <= 2'd1; tlvl <= 2'd0; sub <= 6'd0; end
       else begin med2 <= tmedv[0] + tlores; i <= 10'd0; sub <= 6'd12; end
      end
     end
     6'd12: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd100; dbg_val <= {{32{med2[31]}}, med2};
      sub <= 6'd13;
     end
     6'd13: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd101; dbg_val <= {56'd0, nmedv};
      i <= 10'd0; sub <= 6'd0; stage <= S_TROUND;
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------------ rounding --
   S_TROUND: begin
    case (sub)
     6'd0: begin mem_raddr <= ad_t; sub <= 6'd1; end
     6'd1: begin
      if (!fits(sx(d2v), 8'd34)) begin
       reason <= R_OVERFLOW; stage <= S_FAIL;
      end else begin
       au_op <= O_RSHR;
       au_a <= sx(d2v);
       au_b <= 0; au_k <= 8'd17; au_sig <= 8'd0; au_go <= 1'b1;
       ret <= 6'd2; sub <= SU_WAIT;
      end
     end
     6'd2: begin
      if (!fits(aur, 8'd16)) begin reason <= R_OVERFLOW; stage <= S_FAIL; end
      else begin
       mem_waddr <= ad_t; mem_wdata <= {{48{aur[15]}}, aur[15:0]}; mem_we <= 1'b1;
       if (i == npts - 10'd1) begin i <= 10'd0; sub <= 6'd3; end
       else begin i <= i + 10'd1; sub <= 6'd0; end
      end
     end
     6'd3: begin mem_raddr <= T_BASE + 11'd0; sub <= 6'd4; end
     6'd4: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd102; dbg_val <= {{48{mem_q[15]}}, mem_q[15:0]};
      mem_raddr <= T_BASE + 11'd1; sub <= 6'd5;
     end
     6'd5: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd103; dbg_val <= {{48{mem_q[15]}}, mem_q[15:0]};
      mem_raddr <= T_BASE + {1'b0, (npts >> 1)}; sub <= 6'd6;
     end
     6'd6: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd104; dbg_val <= {{48{mem_q[15]}}, mem_q[15:0]};
      mem_raddr <= T_BASE + npts - 11'd1; sub <= 6'd7;
     end
     6'd7: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd105; dbg_val <= {{48{mem_q[15]}}, mem_q[15:0]};
      i <= 10'd1; sub <= 6'd0; stage <= S_SUP;
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------ support points --
   S_SUP: begin
    case (sub)
     6'd0: begin mem_raddr <= ad_p0 - 11'd2; sub <= 6'd1; end
     6'd1: begin keep1 <= mem_q; mem_raddr <= ad_p0; sub <= 6'd2; end
     6'd2: begin pcur <= mem_q; mem_raddr <= ad_p0 + 11'd2; sub <= 6'd3; end
     6'd3: begin keep2 <= mem_q; mem_raddr <= ad_t - 11'd1; sub <= 6'd4; end
     6'd4: begin tprev <= mem_q[15:0]; mem_raddr <= ad_t + 11'd1; sub <= 6'd5; end
     6'd5: begin
      supb <= sup_of(keep1, pcur, keep2, tprev, mem_q[15:0]);
      sub <= 6'd6;
     end
     6'd6: begin
      mem_waddr <= ad_p0;
      mem_wdata <= {pcur[63:41], supb, pcur[39:0]}; mem_we <= 1'b1;
      if (i == npts - 10'd2) begin
       i <= 10'd0; n_admit <= 10'd0; sub <= 6'd0; stage <= S_ADMIT;
      end else begin i <= i + 10'd1; sub <= 6'd0; end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------------ admission -
   S_ADMIT: begin
    case (sub)
     6'd0: begin mem_raddr <= ad_p0; sub <= 6'd1; end
     6'd1: begin pcur <= mem_q; mem_raddr <= ad_t; sub <= 6'd2; end
     6'd2: begin
      admitb <= admit_of(mem_q[15:0], pcur[40]); sub <= 6'd3;
     end
     6'd3: begin
      mem_waddr <= ad_p0;
      mem_wdata <= {pcur[63:40], admitb, pcur[38:0]}; mem_we <= 1'b1;
      if (admitb) n_admit <= n_admit + 10'd1;
      if (i == npts - 10'd1) begin
       if ((n_admit + (admitb ? 10'd1 : 10'd0)) < MIN_ADMIT) begin
        reason <= R_FEW_ADMIT; stage <= S_FAIL;
       end else begin
        i <= 10'd0; sub <= 6'd0; stage <= S_STAT;
        out_max <= -16'sd32768; in_max <= -16'sd32768;
        cnt_out <= 10'd0; cnt_in <= 10'd0; area <= 24'd0; std2 <= 24'd0;
        ssum <= 24'd0; pcount <= 10'd0; run <= 10'd0; cur <= 10'd0;
        last_slot <= -8'sd2; last_side <= 2'd0;
        gw <= 8'd255; nwin <= 8'd0; wcnt <= 4'd0; wsum <= 11'd0;
       end
      end else begin i <= i + 10'd1; sub <= 6'd0; end
     end
     default: sub <= 6'd0;
    endcase
   end

   // ---------------------------------------------------------- statistics --
   S_STAT: begin
    case (sub)
     6'd0: begin mem_raddr <= ad_p0; sub <= 6'd1; end
     6'd1: begin
      pcur <= mem_q; mem_raddr <= ad_t;
      side_cur <= mem_q[21:20]; slot_cur <= mem_q[28:22];
      step_cur <= mem_q[36:29]; prot_cur <= mem_q[37]; admitb <= mem_q[39];
      sub <= 6'd2;
     end
     6'd2: begin
      tval <= tq16;
      if (!admitb) sub <= 6'd6;
      else begin
       if (tq16 > out_max) out_max <= tq16;
       if (-tq16 > in_max) in_max <= -tq16;
       if (tq16 >= 16'sd8) begin
        cnt_out <= cnt_out + 10'd1;
        area <= area + {8'd0, tq16} - 24'd8;
       end
       if (tq16 <= -16'sd8) cnt_in <= cnt_in + 10'd1;
       ssum <= ssum + {17'd0, step_cur};
       if (prot_cur) pcount <= pcount + 10'd1;
       au_op <= O_MUL; au_a <= {{88{tq16[15]}}, tq16};
       au_b <= {{88{tq16[15]}}, tq16}; au_k <= 8'd0; au_sig <= 8'd0;
       au_go <= 1'b1; ret <= 6'd3; sub <= SU_WAIT;
      end
     end
     6'd3: begin
      std2 <= std2 + aur[23:0];
      if (tval >= 16'sd8) begin
       if (run_nx > run) run <= run_nx;
       cur <= run_nx;
       last_slot <= slot_cur;
      end else begin
       cur <= 10'd0; last_slot <= -8'sd2;
      end
      last_side <= side_cur;
      for (wi = 7; wi > 0; wi = wi - 1) begin
       wsd[wi] <= wsd[wi-1]; wsl[wi] <= wsl[wi-1]; wst[wi] <= wst[wi-1];
      end
      wsd[0] <= side_cur; wsl[0] <= slot_cur; wst[0] <= step_cur;
      if (wcnt == 4'd8) wsum <= wsum + {4'd0, step_cur} - {4'd0, wst[7]};
      else begin wsum <= wsum + {4'd0, step_cur}; wcnt <= wcnt + 4'd1; end
      sub <= 6'd4;
     end
     6'd4: begin
      if ((wcnt == 4'd8) && wall && wslot_ok) begin
       nwin <= nwin + 8'd1;
       if (wcand < {3'd0, gw}) gw <= wcand[7:0];
      end
      sub <= 6'd5;
     end
     6'd5: begin
      if (i == npts - 10'd1) begin i <= 10'd0; sub <= 6'd0; stage <= S_FINAL; end
      else begin i <= i + 10'd1; sub <= 6'd0; end
     end
     6'd6: begin cur <= 10'd0; last_slot <= -8'sd2; sub <= 6'd5; end
     default: sub <= 6'd0;
    endcase
   end

   // ------------------------------------------------------ final features --
   S_FINAL: begin
    case (sub)
     6'd0: begin
      fv[0] <= out_max; fv[1] <= in_max; fv[6] <= run;
      fv[9] <= (nwin == 8'd0) ? 16'sd0 : {8'd0, gw};
      dbg_valid <= 1'b1; dbg_id <= 8'd110; dbg_val <= {54'd0, n_admit};
      au_op <= O_DIV; au_a <= {{94{1'b0}}, cnt_out} <<< 10;
      au_b <= {{94{1'b0}}, n_admit}; au_k <= 8'd0; au_sig <= 8'd20;
      au_go <= 1'b1; ret <= 6'd1; sub <= SU_WAIT;
     end
     6'd1: begin
      fv[2] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{94{1'b0}}, cnt_in} <<< 10;
      au_b <= {{94{1'b0}}, n_admit}; au_k <= 8'd0; au_sig <= 8'd20;
      au_go <= 1'b1; ret <= 6'd2; sub <= SU_WAIT;
     end
     6'd2: begin
      fv[3] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{80{1'b0}}, area}; au_b <= 104'sd100;
      au_k <= 8'd0; au_sig <= 8'd20; au_go <= 1'b1; ret <= 6'd3; sub <= SU_WAIT;
     end
     6'd3: begin
      fv[4] <= aur[15:0];
      au_op <= O_DIVT; au_a <= {{80{1'b0}}, std2}; au_b <= {{94{1'b0}}, n_admit};
      au_k <= 8'd0; au_sig <= 8'd20; au_go <= 1'b1; ret <= 6'd4; sub <= SU_WAIT;
     end
     6'd4: begin
      // OUT_STD is isqrt_q (floor), not isqrt_r: the reference takes the floor
      // of the mean square root.
      au_op <= O_SQ; au_a <= aur; au_b <= 0; au_k <= 8'd0; au_sig <= 8'd0;
      au_go <= 1'b1; ret <= 6'd5; sub <= SU_WAIT;
     end
     6'd5: begin
      fv[5] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{94{1'b0}}, n_admit} <<< 10; au_b <= 104'sd472;
      au_k <= 8'd0; au_sig <= 8'd20; au_go <= 1'b1; ret <= 6'd6; sub <= SU_WAIT;
     end
     6'd6: begin
      fv[7] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{80{1'b0}}, ssum}; au_b <= {{94{1'b0}}, n_admit};
      au_k <= 8'd0; au_sig <= 8'd20; au_go <= 1'b1; ret <= 6'd7; sub <= SU_WAIT;
     end
     6'd7: begin
      fv[8] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{94{1'b0}}, pcount} <<< 10;
      au_b <= {{94{1'b0}}, n_admit}; au_k <= 8'd0; au_sig <= 8'd20;
      au_go <= 1'b1; ret <= 6'd8; sub <= SU_WAIT;
     end
     6'd8: begin
      fv[10] <= aur[15:0];
      au_op <= O_DIV; au_a <= {{84{1'b0}}, a16} <<< 10;
      au_b <= {{84{b16[19]}}, b16}; au_k <= 8'd0; au_sig <= 8'd20;
      au_go <= 1'b1; ret <= 6'd9; sub <= SU_WAIT;
     end
     6'd9: begin
      fv[11] <= aur[15:0];
      au_op <= O_DIV; au_a <= rn_num2; au_b <= 104'sd94371840;
      au_k <= 8'd0; au_sig <= 8'd20; au_go <= 1'b1; ret <= 6'd10; sub <= SU_WAIT;
     end
     6'd10: begin
      fv[12] <= aur[15:0]; valid <= 1'b1; reason <= R_OK;
      sub <= 6'd0; stage <= S_DONE;
     end
     default: sub <= 6'd0;
    endcase
   end

   // -------------------------------------------------------------- finish --
   S_DONE: begin
    case (sub)
     6'd0: begin dbg_valid <= 1'b1; dbg_id <= 8'd120; dbg_val <= fv[0];  sub <= 6'd1; end
     6'd1: begin dbg_valid <= 1'b1; dbg_id <= 8'd121; dbg_val <= fv[1];  sub <= 6'd2; end
     6'd2: begin dbg_valid <= 1'b1; dbg_id <= 8'd122; dbg_val <= fv[2];  sub <= 6'd3; end
     6'd3: begin dbg_valid <= 1'b1; dbg_id <= 8'd123; dbg_val <= fv[3];  sub <= 6'd4; end
     6'd4: begin dbg_valid <= 1'b1; dbg_id <= 8'd124; dbg_val <= fv[4];  sub <= 6'd5; end
     6'd5: begin dbg_valid <= 1'b1; dbg_id <= 8'd125; dbg_val <= fv[5];  sub <= 6'd6; end
     6'd6: begin dbg_valid <= 1'b1; dbg_id <= 8'd126; dbg_val <= fv[6];  sub <= 6'd7; end
     6'd7: begin dbg_valid <= 1'b1; dbg_id <= 8'd127; dbg_val <= fv[7];  sub <= 6'd8; end
     6'd8: begin dbg_valid <= 1'b1; dbg_id <= 8'd128; dbg_val <= fv[8];  sub <= 6'd9; end
     6'd9: begin dbg_valid <= 1'b1; dbg_id <= 8'd129; dbg_val <= fv[9];  sub <= 6'd10; end
     6'd10: begin dbg_valid <= 1'b1; dbg_id <= 8'd130; dbg_val <= fv[10]; sub <= 6'd11; end
     6'd11: begin dbg_valid <= 1'b1; dbg_id <= 8'd131; dbg_val <= fv[11]; sub <= 6'd12; end
     6'd12: begin dbg_valid <= 1'b1; dbg_id <= 8'd132; dbg_val <= fv[12]; sub <= 6'd13; end
     6'd13: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd140; dbg_val <= {63'd0, valid}; sub <= 6'd14;
     end
     6'd14: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd141; dbg_val <= {59'd0, reason}; sub <= 6'd15;
     end
     6'd15: begin
      dbg_valid <= 1'b1; dbg_id <= 8'd142; dbg_val <= {54'd0, iters}; sub <= 6'd16;
     end
     default: begin done <= 1'b1; busy <= 1'b0; sub <= 6'd0; stage <= S_IDLE; end
    endcase
   end

   // --------------------------------------------------------------- fail ---
   S_FAIL: begin
    done <= 1'b1; busy <= 1'b0; valid <= 1'b0;
    if (sub == 6'd0) begin
     dbg_valid <= 1'b1; dbg_id <= 8'd141; dbg_val <= {59'd0, reason};
     sub <= 6'd1;
    end else if (sub == 6'd1) begin
     dbg_valid <= 1'b1; dbg_id <= 8'd140; dbg_val <= 64'sd0;
     sub <= 6'd2;
    end else begin
     sub <= 6'd0; stage <= S_IDLE;
    end
   end

   default: stage <= S_IDLE;
   endcase
  end
 end

endmodule
`endif
