// ---------------------------------------------------------------------------
// ml_num_au : the one sequential arithmetic unit of the gear-6 core.
//
//   MUL   48 x 48 signed  -> exact product on a 104-bit bus, 50 cycles
//   DIVQ  62-bit / 48-bit  -> fx.div_q semantics, incl. the "shrink both
//                             operands by s" approximation and its
//                             precision_loss refusal, 100 cycles
//   SQ    floor(sqrt(x))   -> restoring square root, x < 2^62, 32 cycles
//   SQR   round(sqrt(x))   -> floor plus the exact tie test 4x >= (2a+1)^2
//   RSHR  round-half-even v / 2^k (k = 0..96), 2 cycles
//   SHL   v << k with the 104-bit signed range check
//   DIVT  truncating division (no rounding step), same divider core
//
// Rounding is round-half-to-even on exact integers, identical to fx.rshift_r
// and fx.div_q.  No temporary is unbounded: the product lives in a 144-bit
// accumulator, the shifted dividend and the remainder in 98-bit registers, the
// radicand in a 62-bit register.
// ---------------------------------------------------------------------------
module ml_num_au (
 input  clk,
 input  rst_n,
 input  go,
 input  [2:0] op,                        // 1=MUL 2=DIVQ 3=SQ 4=SQR 5=RSHR 6=SHL 7=DIVT
 input  signed [103:0] a_in,
 input  signed [103:0] b_in,
 input  [7:0] k_in,
 input  [7:0] sig_in,
 output reg signed [103:0] q,
 output reg done,
 output reg fail,
 output reg [3:0] fail_code
);
 localparam OP_MUL = 3'd1, OP_DIV = 3'd2, OP_SQ = 3'd3, OP_SQR = 3'd4;
 localparam OP_RSHR = 3'd5, OP_SHL = 3'd6, OP_DIVT = 3'd7;
 localparam F_ZERO = 5'd1, F_PREC = 5'd2, F_RANGE = 5'd3, F_NEG = 5'd4;

 function [7:0] bitlen;                   // bit length of |v|
  input signed [103:0] v;
  reg [103:0] t;
  integer i;
  begin
   t = v[103] ? (~v + 104'd1) : v;
   bitlen = 8'd0;
   for (i = 0; i < 104; i = i + 1)
     if (t[i]) bitlen = i[7:0] + 8'd1;
  end
 endfunction

 function signed [103:0] rshr;            // round-half-to-even v / 2^k, k>0
  input signed [103:0] v;
  input [7:0] k;
  reg signed [103:0] fl;
  reg [103:0] r, half, lmask;
  begin
   fl    = v >>> k;
   lmask = (104'd1 << k) - 104'd1;
   r     = v & lmask;
   half  = 104'd1 << (k - 8'd1);
   if ((r > half) || ((r == half) && fl[0])) rshr = fl + 104'd1;
   else                                     rshr = fl;
  end
 endfunction

 reg [4:0] st;
 reg signed [103:0] aa, bb;
 reg [7:0]  kk, sg;
 reg signed [143:0] mac, asr;
 reg [6:0]  idx, nbits;
 reg [97:0] num, rem, dvs, quot;
 reg [6:0]  dstep;
 reg neg;
 reg [61:0] sx;
 reg [63:0] srem;
 reg [31:0] sq;
 reg [5:0]  sstep;
 reg [103:0] sqf;
 reg [67:0] odd;
 reg [67:0] fourx;
 reg [7:0]  mw;
 reg [2:0]  op_r;
 wire [5:0] sh2  = {sstep, 1'b0};
 wire [61:0] sxs = sx >> sh2;
 wire [1:0] pair = sxs[1:0];

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   st <= 5'd0; done <= 1'b0; fail <= 1'b0; fail_code <= 5'd0; q <= 104'd0;
   aa <= 0; bb <= 0; kk <= 0; sg <= 0; mac <= 0; asr <= 0; idx <= 0;
   nbits <= 0; num <= 0; rem <= 0; dvs <= 0; quot <= 0; dstep <= 0; neg <= 0;
   sx <= 0; srem <= 0; sq <= 0; sstep <= 0; sqf <= 0; odd <= 0; fourx <= 0;
   mw <= 0; op_r <= 0;
  end else begin
   done <= 1'b0;
   if (go && st == 5'd0) begin
    fail <= 1'b0; fail_code <= 5'd0;
    aa <= a_in; bb <= b_in; kk <= k_in; sg <= sig_in; op_r <= op;
    case (op)
     OP_MUL: begin
      // magnitudes only: a 48-bit two's complement multiplier can not be
      // scanned bit by bit without a correction term, so take |a|*|b| and
      // apply the sign at the end.  Both magnitudes are <= 2^47.
      mac  <= 0;
      neg  <= (a_in < 0) ^ (b_in < 0);
      asr  <= {96'd0, (a_in < 0 ? -a_in : a_in)};
      bb   <= (b_in < 0 ? -b_in : b_in);
      idx  <= 0; nbits <= 8'd48; st <= 5'd1;
     end
     OP_DIV: begin
      neg <= (a_in < 0) ^ (b_in < 0);
      if (b_in == 0) begin
       fail <= 1'b1; fail_code <= F_ZERO; done <= 1'b1;
      end else if (bitlen(a_in) == 0) begin
       q <= 104'd0; done <= 1'b1;
      end else if (bitlen(a_in) + k_in > 62) begin
       nbits <= bitlen(a_in) + k_in - 62;
       st    <= 5'd10;
      end else begin
       num  <= $unsigned(a_in < 0 ? -a_in : a_in) << k_in;
       dvs  <= $unsigned(b_in < 0 ? -b_in : b_in);
       rem  <= 0; quot <= 0; dstep <= 7'd97; st <= 5'd11;
      end
     end
     OP_SQ, OP_SQR: begin
      if (a_in < 0) begin
       fail <= 1'b1; fail_code <= F_NEG; done <= 1'b1;
      end else begin
       sx <= a_in[61:0]; srem <= 0; sq <= 0; sstep <= 6'd30; st <= 5'd20;
      end
     end
     // ---- constant/variable shifts -------------------------------------
     OP_RSHR: begin
      if (k_in > 8'd96) begin
       fail <= 1'b1; fail_code <= F_RANGE; done <= 1'b1;
      end else if (k_in == 8'd0) begin
       q <= a_in; done <= 1'b1;
      end else begin
       q <= rshr(a_in, k_in); done <= 1'b1;
      end
     end
     OP_SHL: begin
      if (bitlen(a_in) + k_in > 8'd103) begin
       fail <= 1'b1; fail_code <= F_RANGE;
      end else begin
       q <= a_in <<< k_in;
      end
      done <= 1'b1;
     end
     // ---- truncating divide: same core, rounding step skipped ----------
     OP_DIVT: begin
      neg <= (a_in < 0) ^ (b_in < 0);
      if (b_in == 0) begin
       fail <= 1'b1; fail_code <= F_ZERO; done <= 1'b1;
      end else if (bitlen(a_in) == 0) begin
       q <= 104'd0; done <= 1'b1;
      end else if (bitlen(a_in) + k_in > 62) begin
       nbits <= bitlen(a_in) + k_in - 62;
       st    <= 5'd14;
      end else begin
       num  <= $unsigned(a_in < 0 ? -a_in : a_in) << k_in;
       dvs  <= $unsigned(b_in < 0 ? -b_in : b_in);
       rem  <= 0; quot <= 0; dstep <= 7'd97; st <= 5'd11;
      end
     end
     default: done <= 1'b1;
    endcase
   end else case (st)
    // ------------------------------------------------------------ multiplier
    5'd1: begin
     if (idx == nbits) st <= 5'd2;
     else begin
      if (bb[idx % 48]) mac <= mac + asr;
      asr <= asr <<< 1;
      idx <= idx + 7'd1;
     end
    end
    5'd2: begin
     q <= neg ? -mac[103:0] : mac[103:0];
     if (mac[143:103] != 0) begin            // |product| >= 2^103
      fail <= 1'b1; fail_code <= F_RANGE;
     end
     done <= 1'b1; st <= 5'd0;
    end
    // -------------------------------------------------------------- divider
    // 10: shrink both operands by s, exactly as fx.div_q does
    5'd10: begin
     if ((bitlen(bb) <= nbits) || ((bitlen(bb) - nbits) < sg)) begin
      fail <= 1'b1; fail_code <= F_PREC; done <= 1'b1; st <= 5'd0;
     end else if (rshr(aa < 0 ? -aa : aa, nbits) == 0 ||
                  rshr(bb < 0 ? -bb : bb, nbits) == 0) begin
      fail <= 1'b1; fail_code <= F_PREC; done <= 1'b1; st <= 5'd0;
     end else begin
      num   <= $unsigned(rshr(aa < 0 ? -aa : aa, nbits)) << kk;
      dvs   <= $unsigned(rshr(bb < 0 ? -bb : bb, nbits));
      rem   <= 0; quot <= 0; dstep <= 7'd97; st <= 5'd11;
     end
    end
    // 11: restoring division, 98 quotient bits, MSB first
    5'd11: begin
     if (({rem[96:0], num[dstep]} ) >= dvs) begin
      rem  <= ({rem[96:0], num[dstep]}) - dvs;
      quot <= (quot << 1) | 98'd1;
     end else begin
      rem  <= {rem[96:0], num[dstep]};
      quot <= quot << 1;
     end
     if (dstep == 7'd0) st <= 5'd12;
     else dstep <= dstep - 7'd1;
    end
    // 12: round-half-to-even on 2*rem against the divisor
    5'd12: begin
     if (op_r == OP_DIVT)
      q <= neg ? -$signed(quot) : $signed(quot);
     else if (((rem << 1) > dvs) || (((rem << 1) == dvs) && quot[0]))
      q <= neg ? -$signed(quot + 98'd1) : $signed(quot + 98'd1);
     else
      q <= neg ? -$signed(quot) : $signed(quot);
     done <= 1'b1; st <= 5'd0;
    end
    // 14: truncating divide, shrunk operands (mirror of the DIVQ path)
    5'd14: begin
     if (rshr(aa < 0 ? -aa : aa, nbits) == 0 ||
         rshr(bb < 0 ? -bb : bb, nbits) == 0) begin
      fail <= 1'b1; fail_code <= F_ZERO; done <= 1'b1; st <= 5'd0;
     end else begin
      num   <= $unsigned(rshr(aa < 0 ? -aa : aa, nbits)) << kk;
      dvs   <= $unsigned(rshr(bb < 0 ? -bb : bb, nbits));
      rem   <= 0; quot <= 0; dstep <= 7'd97; st <= 5'd11;
     end
    end
    // ----------------------------------------------------------- square root
    5'd20: begin
     srem <= {srem[61:0], pair};
     st   <= 5'd21;
    end
    5'd21: begin
     if (srem >= (({32'd0, sq} << 2) | 64'd1)) begin
      srem <= srem - (({32'd0, sq} << 2) | 64'd1);
      sq   <= (sq << 1) | 32'd1;
     end else begin
      sq   <= sq << 1;
     end
     if (sstep == 6'd0) st <= 5'd24;
     else begin
      sstep <= sstep - 6'd1;
      st    <= 5'd20;
     end
    end
    // 24: the last digit has landed in sq -- latch it before using it
    5'd24: begin
     sqf <= {72'd0, sq};
     neg <= 1'b0;
     if (op_r == OP_SQR) begin
      fourx <= {68'd0, sx} << 2;
      mac   <= 0;
      asr   <= {{96{1'b0}}, sq[19:0], 1'b1};
      bb    <= {84'd0, sq[19:0], 1'b1};
      idx   <= 0; nbits <= 8'd21; st <= 5'd22;
     end else begin
      q <= {72'd0, sq}; done <= 1'b1; st <= 5'd0;
     end
    end
    5'd22: begin
     if (idx == nbits) st <= 5'd23;
     else begin
      if (bb[idx % 48]) mac <= mac + asr;
      asr <= asr <<< 1;
      idx <= idx + 7'd1;
     end
    end
    5'd23: begin                                   // mac = (2a+1)^2
     q <= (fourx >= mac[67:0]) ? sqf + 104'd1 : sqf;
     done <= 1'b1; st <= 5'd0;
    end
    default: st <= 5'd0;
   endcase
  end
 end
endmodule
