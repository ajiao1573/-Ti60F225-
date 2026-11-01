`ifndef TI60_ML_SCAN_V
`define TI60_ML_SCAN_V
// Image -> candidate scan points, bit-compatible with `scan_points` and with
// the step/protect export of `refpipe.points_of` in the frozen reference.
//
// Reference rules (W=960, H=720, box [128,832) x [8,712), step 6, half step 6):
//   rows y = 8,14,...,710 : first edge pixel in the box -> L, last -> R
//   cols x = 128,134,...,830 : first edge pixel in the box -> T, last -> B
//   step  = |gray(y, x+6) - gray(y, x-6)|   for L/R
//           |gray(y+6, x) - gray(y-6, x)|   for T/B
//   a point exists only when its own step >= 4, and its real slot index travels
//   with it so holes stay visible downstream
//   protect = any() of the protect map over the 5x5 window centred on the point,
//   i.e. rows y-2..y+2 and columns x-2..x+2
//   emission order is side major: L, R, T, B, ascending slot within a side
//
// Stream timing.  Measured on the real canny_frame (tests/tb_canny_latency.v):
// the edge stream trails the gray stream by 1928 pixels = 2 rows + 8 pixels,
// both dense (one valid pixel per cycle, sop only at (0,0), eop only at
// (W-1,H-1)).
//
// Two look-ahead requirements drive the pipeline: T/B need gray(y+6), and every
// point needs protect over rows y-2..y+2.  A pixel (x,y) is therefore decided
// only once the input edge stream has reached (x+6, y+8).  Three rasters run in
// lockstep, each with its own counter re-seeded on the input edge sop, so no
// coordinate is ever reconstructed by modular subtraction:
//   input    (sx , sy )                          writes the rings
//   window   (wcx, wry) = input - (2 px, 4 rows)  horizontal 5-tap + column ring
//   decision (ddx, ddy) = input - (6 px, 8 rows)  extremum latch, column scan
// The decision raster is four pixels and four rows behind the window raster: the
// protect stream is read through one register stage (so the 5-tap window is
// centred on wcx-4, wry-2), and the 5-tap is then shifted into a per-column
// vertical ring, which centres the 5x5 window on (wcx-4, wry-4).  The decision
// coordinate is registered alongside the ring read data so that coordinate,
// edge bit and 5x5 window are always consumed together.
//
// Bounded on-chip storage, nothing full-frame:
//   16 x 960 x 1 b   protect ring
//   16 x 960 x 1 b   edge ring
//    4 x 960 x 1 b   5x5 window results, read back by the row finaliser
//   16 x 960 x 8 b   gray of the last sixteen scan rows (slot = y[3:0])
//   118 x 32 x 8 b   gray of the 118 scan columns, 32 rows deep
//   960 x 5 b        per-column vertical window taps
//   2 x 236 x 32 b   slot tables
module ml_scan #(
 parameter WIDTH  = 960,
 parameter HEIGHT = 720
)(
 input clk,
 input rst_n,
 input start,                      // arm: take the next complete frame pair
 input gray_valid, input gray_sop, input gray_eop, input [7:0] gray_data,
 input edge_valid, input edge_sop, input edge_eop,
 input edge_data, input edge_protect,
 // candidate list, laid out exactly like the bench's point words
 output reg pt_we, output reg [10:0] pt_addr, output reg [63:0] pt_wdata,
 output reg done, output reg [9:0] n_points, output reg [4:0] reason,
 output reg busy
);
 localparam W  = WIDTH;
 localparam H  = HEIGHT;
 localparam NB = 118;              // slots per side
 localparam CD = 32;               // column-ring depth, in rows

 localparam BX0 = 128, BX1 = 832, BY0 = 8, BY1 = 712;
 localparam [7:0] MIN_STEP = 8'd4;
 localparam [7:0] NB8      = 8'd118;

 localparam [4:0] SC_OK = 5'd0, SC_LEAD = 5'd1, SC_OVF = 5'd2, SC_NOGRAY = 5'd3;
 localparam [1:0] SD_T = 2'd0, SD_R = 2'd1, SD_B = 2'd2, SD_L = 2'd3;

 // ---------------------------------------------------------------- storage --
 reg        pram [0:16*W-1];       // protect, 16-row ring, input order
 reg        eram [0:16*W-1];       // edge,    16-row ring, input order
 reg        vram [0:4*W-1];        // 5x5 window result, 4-row ring
 reg [7:0]  rram [0:16*W-1];       // gray of the last sixteen scan rows
 reg [7:0]  cram [0:NB*CD-1];      // gray of the 118 scan columns
 reg [3:0]  w5   [0:W-1];          // vertical window taps, one entry per column
 // slot word, 32 bits: {2'b00, valid, prot, step[7:0], y[9:0], x[9:0]}
 reg [31:0] rtab [0:2*NB-1];       // [0..117] = L, [118..235] = R
 reg [31:0] ctab [0:2*NB-1];       // [0..117] = T, [118..235] = B

 reg        pram_q, eram_q, vram_q;
 reg [7:0]  rram_q, cram_q;
 integer    bi;

 // ------------------------------------------------------------- arming ------
 reg arm_i, armed_pend, wait_dsop;
 reg [1:0] gfrm, efrm, dfrm, afrm_g, afrm_d;
 reg clr_on;
 reg [8:0] clr_i;

 // ------------------------------------------------------------ gray raster --
 reg [9:0] gx, gy;
 reg [7:0] gcn;
 reg [2:0] gph, grh;
 reg gwe, cwe;
 reg [7:0] gray_q;
 reg [13:0] gwa;
 reg [11:0] cwa;
 reg [19:0] gcnt;

 wire [9:0] gcx = gray_sop ? 10'd0 : gx;
 wire [9:0] gcy = gray_sop ? 10'd0 : gy;
 wire [7:0] gcn_e = gray_sop ? 8'd0 : gcn;
 wire [2:0] gph_e = gray_sop ? 3'd0 : gph;
 wire [2:0] grh_e = gray_sop ? 3'd0 : grh;

 wire g_act    = gray_valid && arm_i && !armed_pend && (gfrm == afrm_g);
 wire g_rowhit = g_act && (grh_e == 3'd2) && (gcy >= BY0[9:0]) && (gcy < BY1[9:0]);
 wire g_colhit = g_act && (gph_e == 3'd2) && (gcn_e >= 8'd21) && (gcn_e < 8'd139);
 wire [13:0] gwa_c = {10'd0, gcy[3:0]} * W[13:0] + {4'd0, gcx};
 wire [11:0] cwa_c = {4'd0, (gcn_e - 8'd21)} * CD[11:0] + {7'd0, gcy[4:0]};

 always @(posedge clk) if (gwe) rram[gwa] <= gray_q;
 always @(posedge clk) if (cwe) cram[cwa] <= gray_q;

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   gx <= 10'd0; gy <= 10'd0; gcn <= 8'd0; gph <= 3'd0; grh <= 3'd0;
   gfrm <= 2'd0; arm_i <= 1'b0; armed_pend <= 1'b0;
   afrm_g <= 2'd0;
   gwe <= 1'b0; cwe <= 1'b0; gray_q <= 8'd0; gwa <= 14'd0; cwa <= 12'd0; gcnt <= 10'd0;
  end else begin
   gwe <= 1'b0; cwe <= 1'b0; gray_q <= gray_data;
   if (start && !busy) begin arm_i <= 1'b1; armed_pend <= 1'b1;
                        gcnt <= 20'd0; end
   if (gray_valid) begin
    if (gray_sop) begin
     gx <= 10'd1; gy <= 10'd0; gcn <= 8'd0; gph <= 3'd1; grh <= 3'd0;
     if (armed_pend) begin armed_pend <= 1'b0; afrm_g <= gfrm; end
     else gfrm <= gfrm + 2'd1;
    end else if (g_act) begin
     if (g_rowhit) begin gwe <= 1'b1; gwa <= gwa_c; end
     if (g_colhit) begin cwe <= 1'b1; cwa <= cwa_c; end
     gcnt <= gcnt + 20'd1;
    end
    if (!gray_sop && gx == W[9:0] - 10'd1) begin
     gx <= 10'd0; gph <= 3'd0; gcn <= 8'd0;
     gy <= (gy == H[9:0] - 10'd1) ? 10'd0 : gy + 10'd1;
     grh <= (grh == 3'd5) ? 3'd0 : grh + 3'd1;
    end else if (!gray_sop) begin
     gx <= gx + 10'd1;
     gph <= (gph == 3'd5) ? 3'd0 : gph + 3'd1;
     if (gph == 3'd2) gcn <= gcn + 8'd1;
    end
   end
  end
 end

 // ------------------------------------------------------------ edge rasters --
 reg [9:0] sx, sy;                 // input
 reg [9:0] wcx, wry;               // window   = input - (2 px, 4 rows)
 reg [9:0] ddx, ddy;               // decision = input - (6 px, 8 rows)
 reg [2:0] dph, drh;               // column / row residue of the decision raster
 reg [7:0] dcn;                    // (ddx-2)/6, maintained incrementally
 reg [9:0] dky;                    // scan-row index inside the decision frame
 reg dvld, evld;

 wire [9:0] isx = edge_sop ? 10'd0 : sx;
 wire [9:0] isy = edge_sop ? 10'd0 : sy;
 wire [13:0] wa_i = {10'd0, isy[3:0]} * W[13:0] + {4'd0, isx};
 wire [13:0] wa_p = {10'd0, wry[3:0]} * W[13:0] + {4'd0, wcx};
 wire [13:0] wa_d = {10'd0, ddy[3:0]} * W[13:0] + {4'd0, ddx};

 always @(posedge clk) begin
  if (edge_valid) begin
   eram[wa_i] <= edge_data;
   pram[wa_i] <= edge_protect;
  end
  eram_q <= eram[wa_d];
  pram_q <= pram[wa_p];
 end

 // ------------------------------------------- horizontal 5-tap on protect ----
 reg [4:0] psh;
 wire hwin = |psh;
 wire [9:0] wcol = (wcx >= 10'd4) ? (wcx - 10'd4) : (wcx + W[9:0] - 10'd4);
 wire [9:0] wcx_next = edge_valid ? (edge_sop ? W[9:0]-10'd1 : (wcx==W[9:0]-10'd1 ? 10'd0 : wcx+10'd1)) : wcx;
 wire [9:0] wcol_next = (wcx_next >= 10'd4) ? (wcx_next - 10'd4) : (wcx_next + W[9:0] - 10'd4);
 reg [3:0] w5q;
 reg [9:0] w5_clear;
 reg w5_init_done;
 wire [4:0] w5nx = {w5q, hwin};
 wire vwin = |w5nx;

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) psh <= 5'd0;
  else if (edge_valid) begin
   if (wcx == 10'd1) psh <= 5'd0;
   else psh <= {psh[3:0], pram_q};
  end
 end

 // Initial scrub and subsequent one-word synchronous read/write.
 wire [9:0] w5_wa = !w5_init_done ? w5_clear : wcol;
 wire [3:0] w5_wd = !w5_init_done ? 4'd0 : w5nx[3:0];
 always @(posedge clk) begin
  w5q <= w5[wcol_next];
  if (!w5_init_done || (edge_valid && evld)) w5[w5_wa] <= w5_wd;
 end
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin w5_clear<=0; w5_init_done<=0; end
  else if (!w5_init_done) begin
   if(w5_clear==W-1) w5_init_done<=1;
   else w5_clear<=w5_clear+1'b1;
  end
 end

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   sx <= 10'd0; sy <= 10'd0; wcx <= 10'd0; wry <= 10'd0;
   ddx <= 10'd0; ddy <= 10'd0; dph <= 3'd0; drh <= 3'd0; dcn <= 8'd0;
   dvld <= 1'b0; evld <= 1'b0; efrm <= 2'd0; dfrm <= 2'd0;
  end else if (edge_valid) begin
   if (edge_sop) begin
    sx <= 10'd1; sy <= 10'd0;
    wcx <= W[9:0] - 10'd1;  wry <= H[9:0] - 10'd5;
    ddx <= W[9:0] - 10'd5;  ddy <= H[9:0] - 10'd9;
    dph <= 3'd1; drh <= 3'd3; dcn <= 8'd158;
    dvld <= 1'b1; evld <= 1'b1;
    efrm <= efrm + 2'd1;

   end else begin
    if (sx == W[9:0] - 10'd1) begin
     sx <= 10'd0; sy <= (sy == H[9:0] - 10'd1) ? 10'd0 : sy + 10'd1;
    end else sx <= sx + 10'd1;

    if (wcx == W[9:0] - 10'd1) begin
     wcx <= 10'd0; wry <= (wry == H[9:0] - 10'd1) ? 10'd0 : wry + 10'd1;
    end else wcx <= wcx + 10'd1;

    if (ddx == W[9:0] - 10'd1) begin
     ddx <= 10'd0; dph <= 3'd0; dcn <= 8'd0;
     drh <= (drh == 3'd5) ? 3'd0 : drh + 3'd1;
     if (ddy == H[9:0] - 10'd1) begin
      ddy <= 10'd0; dfrm <= dfrm + 2'd1;

     end else ddy <= ddy + 10'd1;
    end else begin
     ddx <= ddx + 10'd1;
     dph <= (dph == 3'd5) ? 3'd0 : dph + 3'd1;
     if (dph == 3'd2) dcn <= dcn + 8'd1;
    end
   end
  end
 end

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin wait_dsop <= 1'b0; afrm_d <= 2'd0; end
  else if (start && !busy) wait_dsop <= 1'b1;
  else if (edge_valid && !edge_sop && ddx == W[9:0]-10'd1 && ddy == H[9:0]-10'd1 && wait_dsop && !armed_pend) begin
   wait_dsop <= 1'b0; afrm_d <= dfrm + 2'd1;
  end
 end
 // --------------------------------------------- decision-stage registers -----
 // The ring read data is registered, so the decision coordinate is registered
 // with it and carries its own residue / column index; nothing is recomputed
 // from the live raster, which is one pixel ahead by then.
 reg rvalid;
 reg [9:0] rdx, rdy;
 reg [2:0] rdph, rdrh;
 reg [7:0] rdcn;
 reg [1:0] rfrm;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin rvalid <= 1'b0; rdx <= 0; rdy <= 0; rdph <= 0; rdrh <= 0; rdcn <= 0; rfrm <= 0; end
  else begin
   rvalid <= edge_valid && dvld;
   rdx <= ddx; rdy <= ddy; rdph <= dph; rdrh <= drh; rdcn <= dcn; rfrm <= dfrm;
  end
 end
 reg qval, qee;
 reg [1:0] qfrm;
 reg [9:0] qdx, qdy;
 reg qwin;
 reg [2:0] qdph, qdrh;
 reg [7:0] qdcn;

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   qval <= 1'b0; qfrm <= 2'd0; qdx <= 10'd0; qdy <= 10'd0; qee <= 1'b0; qwin <= 1'b0;
   qdph <= 3'd0; qdrh <= 3'd0; qdcn <= 8'd0;
  end else begin
   qval <= rvalid;
   qfrm <= rfrm; qdx <= rdx; qdy <= rdy; qee <= eram_q; qwin <= vwin;
   qdph <= rdph; qdrh <= rdrh; qdcn <= rdcn;
  end
 end

 wire dact = qval && arm_i && !armed_pend && !wait_dsop && (qfrm == afrm_d);
 wire d_rowend = (qdx == W[9:0] - 10'd1);
 wire d_colscn = (qdx >= BX0[9:0]) && (qdx < BX1[9:0]);
 wire d_inbox  = (qdy >= BY0[9:0]) && (qdy < BY1[9:0]);
 wire d_hit    = (qdrh == 3'd2) && d_inbox;
 wire d_frameend = dact && d_rowend && (qdy == H[9:0] - 10'd1);

 // -------------------------------------------------- row extremum latch -----
 reg rf_v, rl_v;
 reg [9:0] rf_x, rl_x;

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   rf_v <= 1'b0; rl_v <= 1'b0; rf_x <= 10'd0; rl_x <= 10'd0;
  end else if (dact && (qdx == 10'd0)) begin
   rf_v <= 1'b0; rl_v <= 1'b0; rf_x <= 10'd0; rl_x <= 10'd0;
  end else if (dact && qee && d_colscn) begin
   if (!rf_v) begin rf_v <= 1'b1; rf_x <= qdx; end
   rl_v <= 1'b1; rl_x <= qdx;
  end
 end

 // ------------------------------------------------------ row finaliser ------
 localparam [2:0] RE_IDLE = 3'd0, RE_R1 = 3'd1, RE_R2 = 3'd2,
                  RE_R3 = 3'd3, RE_R4 = 3'd4, RE_WL = 3'd5, RE_WR = 3'd6;
 reg [2:0] re_st;
 reg re_fv, re_lv;
 reg [9:0] re_fx, re_lx, re_y, re_k;
 reg pw_f, pw_l;
 reg [7:0] re_a, re_b, re_c, re_d;
 reg [13:0] rra, vra;
 wire [7:0] rstep_a = (re_a > re_b) ? (re_a - re_b) : (re_b - re_a);
 wire [7:0] rstep_b = (re_c > re_d) ? (re_c - re_d) : (re_d - re_c);
 wire [13:0] rrbase = {10'd0, re_y[3:0]} * W[13:0];
 wire [11:0] vrbase = {2'd0, re_y[1:0]} * W[11:0];

 always @* begin
  case (re_st)
   RE_R1:   begin rra = rrbase + {4'd0, re_fx} - 14'd6;
                 vra = vrbase + {2'd0, re_fx}; end
   RE_R2:   begin rra = rrbase + {4'd0, re_fx} + 14'd6;
                 vra = vrbase + {2'd0, re_lx}; end
   RE_R3:   begin rra = rrbase + {4'd0, re_lx} - 14'd6; vra = vrbase; end
   RE_R4:   begin rra = rrbase + {4'd0, re_lx} + 14'd6; vra = vrbase; end
   RE_WL:   begin rra = rrbase; vra = vrbase; end
   RE_WR:   begin rra = rrbase; vra = vrbase; end
   default: begin rra = rrbase; vra = {2'b00,qdy[1:0]} * W + qdx; end
  endcase
 end

 always @(posedge clk) begin
  rram_q <= rram[rra];
  if (dact && qdx != W-1) vram[((qdy[1:0] + 2'd2) & 2'b11) * W + qdx + 10'd1] <= qwin;
  vram_q <= vram[vra];
 end

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   re_st <= RE_IDLE; re_fv <= 1'b0; re_lv <= 1'b0;
   re_fx <= 10'd0; re_lx <= 10'd0; re_y <= 10'd0; re_k <= 10'd0;
   re_a <= 8'd0; re_b <= 8'd0; re_c <= 8'd0; re_d <= 8'd0;
   pw_f <= 1'b0; pw_l <= 1'b0;
  end else begin
   case (re_st)
    RE_IDLE: if (dact && d_rowend && d_hit) begin
      re_fv <= rf_v; re_lv <= rl_v; re_fx <= rf_x; re_lx <= rl_x;
      re_y <= qdy; re_k <= dky; re_st <= RE_R1;
     end
    RE_R1: re_st <= RE_R2;
    RE_R2: begin pw_f <= vram_q; re_a <= rram_q; re_st <= RE_R3; end
    RE_R3: begin pw_l <= vram_q; re_b <= rram_q; re_st <= RE_R4; end
    RE_R4: begin re_c <= rram_q; re_st <= RE_WL; end
    RE_WL: begin re_d <= rram_q; re_st <= RE_WR; end
    RE_WR: re_st <= RE_IDLE;
    default: re_st <= RE_IDLE;
   endcase
  end
 end

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) dky <= 10'd0;
  else if (edge_valid && (edge_sop || (ddx == W[9:0]-10'd1 && ddy == H[9:0]-10'd1))) dky <= 10'd0;
  else if ((re_st == RE_IDLE) && dact && d_rowend && d_hit) dky <= dky + 10'd1;
 end

 // ------------------------------------------------------- column FSM --------
 localparam [1:0] CE_I = 2'd0, CE_1 = 2'd1, CE_2 = 2'd2, CE_3 = 2'd3;
 reg [1:0] ce_st;
 reg [6:0] ce_k;
 reg [9:0] ce_y;
 reg ce_p, ce_ok;
 reg [7:0] ce_gp, ce_step;
 reg [11:0] cra;
 reg [NB-1:0] cvd;

 wire [6:0] kin   = qdcn[6:0] - 7'd21;
 wire [11:0] cb_i = {5'd0, kin} * CD[11:0];
 wire [11:0] cbase = {5'd0, ce_k} * CD[11:0];
 wire [4:0] ce_rp = qdy[4:0] + 5'd6;
 wire [4:0] ce_rm = ce_y[4:0] - 5'd6;
 wire [7:0] cstep = (ce_gp > cram_q) ? (ce_gp - cram_q) : (cram_q - ce_gp);
 wire [9:0] ce_xw = BX0[9:0] + ({3'd0, ce_k} << 2) + ({3'd0, ce_k} << 1);
 wire ce_ev = dact && qee && d_colscn && (qdph == 3'd2) && d_inbox;

 always @* begin
  case (ce_st)
   CE_I:    cra = cb_i  + {7'd0, ce_rp};   // read gray(y+6, x)
   CE_1:    cra = cbase + {7'd0, ce_rm};   // read gray(y-6, x)
   default: cra = cbase;
  endcase
 end
 always @(posedge clk) cram_q <= cram[cra];

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   ce_st <= CE_I; ce_k <= 7'd0; ce_y <= 10'd0; ce_p <= 1'b0; ce_ok <= 1'b0;
   ce_gp <= 8'd0; ce_step <= 8'd0;
  end else begin
   case (ce_st)
    CE_I: if (ce_ev) begin
      ce_k <= kin; ce_y <= qdy; ce_st <= CE_1;
     end
    CE_1: begin ce_gp <= cram_q; ce_p <= vram_q; ce_st <= CE_2; end
    CE_2: begin
      ce_step <= cstep; ce_ok <= (cstep >= MIN_STEP); ce_st <= CE_3;
     end
    CE_3: ce_st <= CE_I;
    default: ce_st <= CE_I;
   endcase
  end
 end

 // ------------------------------------------------------- slot table writes -
 // One write per array per cycle: the clear pass owns the tables until it is
 // done, then the row finaliser and the column FSM write disjoint entries.
 reg rwe, cwe_slot;
 reg [7:0] rwa, cwa_slot;
 reg [31:0] rwd, cwd;
 always @* begin
  rwe=0; cwe_slot=0; rwa=0; cwa_slot=0; rwd=0; cwd=0;
  if (clr_on) begin
   rwe=1; cwe_slot=1; rwa=clr_i[7:0]; cwa_slot=clr_i[7:0];
  end else begin
   if (re_st==RE_WL) begin rwe=1; rwa={1'b0,re_k[6:0]}; rwd=(re_fv && rstep_a>=MIN_STEP) ? {2'b00,1'b1,pw_f,rstep_a,re_y,re_fx}:32'd0; end
   if (re_st==RE_WR) begin rwe=1; rwa=NB8+re_k[7:0]; rwd=(re_lv && rstep_b>=MIN_STEP) ? {2'b00,1'b1,pw_l,rstep_b,re_y,re_lx}:32'd0; end
   if (ce_st==CE_2 && !cvd[ce_k] && cstep>=MIN_STEP) begin cwe_slot=1; cwa_slot={1'b0,ce_k}; cwd={2'b00,1'b1,ce_p,cstep,ce_y,ce_xw}; end
   if (ce_st==CE_3) begin cwe_slot=1; cwa_slot=NB8+{1'b0,ce_k}; cwd=ce_ok ? {2'b00,1'b1,ce_p,ce_step,ce_y,ce_xw}:32'd0; end
  end
 end
 always @(posedge clk) begin
  if(rwe) rtab[rwa]<=rwd;
  if(cwe_slot) ctab[cwa_slot]<=cwd;
  if(start) cvd<={NB{1'b0}};
  else if(!clr_on && ce_st==CE_2) cvd[ce_k]<=1'b1;
 end

 // clear pass counter
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin clr_on <= 1'b0; clr_i <= 9'd0; end
  else if (start && !busy) begin clr_on <= 1'b1; clr_i <= 9'd0; end
  else if (clr_on) begin
   clr_i <= clr_i + 9'd1;
   if (clr_i == 9'd235) clr_on <= 1'b0;
  end
 end

 // ----------------------------------------------------------- compaction ----
 localparam [2:0] CP_IDLE = 3'd0, CP_RD = 3'd1, CP_WR = 3'd2, CP_INC = 3'd3,
                  CP_END = 3'd4;
 reg [2:0] cp_st;
 reg [1:0] cp_side;
 reg [6:0] cp_slot;
 reg [9:0] cp_n;
 reg [31:0] row_q, col_q;
 wire [31:0] cw=cp_side[1] ? col_q:row_q;
 wire [7:0] cpa = cp_side[0] ? (NB8 + {1'b0, cp_slot}) : {1'b0, cp_slot};

 always @(posedge clk) begin
 row_q<=rtab[cpa]; col_q<=ctab[cpa];
 end

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   cp_st <= CP_IDLE; cp_side <= 2'd0; cp_slot <= 7'd0; cp_n <= 10'd0;
   pt_we <= 1'b0; pt_addr <= 11'd0; pt_wdata <= 64'd0;
   done <= 1'b0; n_points <= 10'd0; reason <= SC_OK; busy <= 1'b0;
  end else begin
   pt_we <= 1'b0;
   if (start && !busy) begin
    busy <= 1'b1; done <= 1'b0; reason <= SC_OK; n_points <= 10'd0;
   end
   // a frame captured without gray (or without the matching edge frame) is a
   // timing violation, not a valid empty result
   case (cp_st)
    CP_IDLE: if (d_frameend) begin
      // a frame whose gray side was truncated cannot yield a trusted scan
      if (gcnt < 20'd690000) reason <= SC_NOGRAY;
      cp_side <= 2'd0; cp_slot <= 7'd0; cp_n <= 10'd0; cp_st <= CP_RD;
     end
    CP_RD: cp_st <= CP_WR;
    CP_WR: begin
      if (cw[29]) begin
       pt_we <= 1'b1;
       pt_addr <= {cp_n, 1'b0};
       pt_wdata <= {25'd0, 1'b1, cw[28], cw[27:20], cp_slot,
                    ((cp_side == 2'd0) ? SD_L : (cp_side == 2'd1) ? SD_R :
                     (cp_side == 2'd2) ? SD_T : SD_B),
                    cw[19:10], cw[9:0]};
       cp_n <= cp_n + 10'd1;
      end
      cp_st <= CP_INC;
     end
    CP_INC: begin
      if (cp_slot == 7'd117) begin
       cp_slot <= 7'd0;
       if (cp_side == 2'd3) cp_st <= CP_END;
       else begin cp_side <= cp_side + 2'd1; cp_st <= CP_RD; end
      end else begin cp_slot <= cp_slot + 7'd1; cp_st <= CP_RD; end
     end
    CP_END: begin
      n_points <= (reason == SC_OK) ? cp_n : 10'd0;
      done <= 1'b1; busy <= 1'b0; cp_st <= CP_IDLE;
     end
    default: cp_st <= CP_IDLE;
   endcase
  end
 end

endmodule
`endif
