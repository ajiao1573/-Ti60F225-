// Feed the frozen reference's gray / edge / protect planes into ml_scan with the
// timing the real canny_frame produces (edge trails gray by 1928 pixels, both
// dense) and compare the emitted candidate list against refpipe.points_of.
//
//   +NEXP=n   number of expected points (from verification/scan/meta.json)
//   +VEC=dir  directory holding gray.hex / edge.hex / prot.hex / exp.hex
`timescale 1ns/1ps
module tb_ml_scan;
 localparam W = 960;
 localparam H = 720;
 localparam F = W * H;                 // 691200 pixels per frame
 localparam LEAD = 1928;               // measured edge lag, in pixels
 localparam NFRM = 3;

 reg clk, rst_n, start;
 reg gray_valid, gray_sop, gray_eop;
 reg [7:0] gray_data;
 reg edge_valid, edge_sop, edge_eop, edge_data, edge_protect;

 wire pt_we;
 wire [10:0] pt_addr;
 wire [63:0] pt_wdata;
 wire done;
 wire [9:0] n_points;
 wire [4:0] reason;
 wire busy;

 reg [127:0] gmem [0:F/16-1];
 reg [63:0]  emem [0:F/64-1];
 reg [63:0]  pmem [0:F/64-1];
 reg [63:0]  expw [0:1023];
 reg [63:0]  gotw [0:1023];

 integer gi, ei, cyc, nexp, nread, fails, i;
 reg [8*256-1:0] vecdir, vecpath;
 integer writes=0, addr_errors=0;
 integer dump_fd; reg [2047:0] dump_path;

 ml_scan #(.WIDTH(W), .HEIGHT(H)) dut (
  .clk(clk), .rst_n(rst_n), .start(start),
  .gray_valid(gray_valid), .gray_sop(gray_sop), .gray_eop(gray_eop),
  .gray_data(gray_data),
  .edge_valid(edge_valid), .edge_sop(edge_sop), .edge_eop(edge_eop),
  .edge_data(edge_data), .edge_protect(edge_protect),
  .pt_we(pt_we), .pt_addr(pt_addr), .pt_wdata(pt_wdata),
  .done(done), .n_points(n_points), .reason(reason), .busy(busy)
 );

 initial clk = 1'b0;
 always #5 clk = ~clk;

 always @(posedge clk) if (pt_we) begin
  if (pt_addr !== (writes << 1)) addr_errors = addr_errors + 1;
  gotw[pt_addr >> 1] <= pt_wdata; writes = writes + 1;
 end

 initial begin
  if (!$value$plusargs("NEXP=%d", nexp)) nexp = -1;
  if (!$value$plusargs("VEC=%s", vecdir)) vecdir = "verification/scan";
  $sformat(vecpath, "%0s/gray.hex", vecdir);
  $readmemh(vecpath, gmem);
  $sformat(vecpath, "%0s/edge.hex", vecdir);
  $readmemh(vecpath, emem);
  $sformat(vecpath, "%0s/prot.hex", vecdir);
  $readmemh(vecpath, pmem);
  $sformat(vecpath, "%0s/exp.hex", vecdir);
  $readmemh(vecpath, expw);
 end

 // ------------------------------------------------------------ stimulus ----
 initial begin
  rst_n = 1'b0; start = 1'b0;
  gray_valid = 1'b0; edge_valid = 1'b0;
  gray_sop = 1'b0; gray_eop = 1'b0; gray_data = 8'd0;
  edge_sop = 1'b0; edge_eop = 1'b0; edge_data = 1'b0; edge_protect = 1'b0;
  gi = 0; ei = -LEAD; cyc = 0;
  repeat (8) @(negedge clk);
  rst_n = 1'b1;
  @(negedge clk);

  for (cyc = 0; cyc < NFRM * F + 6000; cyc = cyc + 1) begin
   // gray: dense, sop only at (0,0), eop only at (W-1,H-1)
   if (gi >= 0 && gi < NFRM * F) begin
    gray_valid = 1'b1;
    gray_data = gmem[(gi % F) >> 4] >> (((gi % F) & 15) * 8);
    gray_sop = ((gi % F) == 0);
    gray_eop = ((gi % F) == F - 1);
   end else begin
    gray_valid = 1'b0; gray_sop = 1'b0; gray_eop = 1'b0;
   end
   // edge: the same plane, 1928 pixels later
   if (ei >= 0 && ei < NFRM * F) begin
    edge_valid = 1'b1;
    edge_data = (emem[(ei % F) >> 6] >> ((ei % F) & 63)) & 1'b1;
    edge_protect = (pmem[(ei % F) >> 6] >> ((ei % F) & 63)) & 1'b1;
    edge_sop = ((ei % F) == 0);
    edge_eop = ((ei % F) == F - 1);
   end else begin
    edge_valid = 1'b0; edge_sop = 1'b0; edge_eop = 1'b0;
   end
   start = (cyc == 100);
   @(negedge clk);
   gi = gi + 1;
   ei = ei + 1;
   if (done && cyc > 2 * F) cyc = NFRM * F + 5000;   // finish early
  end
 end

 // ------------------------------------------------------------ check -------
 initial begin
  wait (done === 1'b1);
  repeat (4) @(posedge clk);
  fails = 0;
  $display("SCAN n_points=%0d reason=%0d expected=%0d cyc=%0d", n_points, reason, nexp,
           $time / 10);
  if (reason !== 0 || addr_errors != 0 || writes != n_points) begin
   fails = fails + 1;
   $display("SCAN FAIL reason=%0d addr_errors=%0d writes=%0d",reason,addr_errors,writes);
  end
  if (nexp >= 0 && n_points != nexp) begin
   fails = fails + 1;
   $display("SCAN FAIL count got=%0d want=%0d", n_points, nexp);
  end
  if ($value$plusargs("GOT=%s",dump_path)) begin
   dump_fd=$fopen(dump_path,"w");
   for(i=0;i<n_points;i=i+1) $fdisplay(dump_fd,"%016x",gotw[i]);
   $fclose(dump_fd);
  end
  nread = (nexp >= 0) ? nexp : n_points;
  for (i = 0; i < nread; i = i + 1) begin
   if (gotw[i] !== expw[i]) begin
    fails = fails + 1;
    if (fails < 1024)
     $display("SCAN FAIL i=%0d got=%016x want=%016x  (x %0d/%0d y %0d/%0d side %0d/%0d slot %0d/%0d step %0d/%0d prot %0d/%0d)",
      i, gotw[i], expw[i],
      gotw[i][9:0], expw[i][9:0], gotw[i][19:10], expw[i][19:10],
      gotw[i][21:20], expw[i][21:20], gotw[i][28:22], expw[i][28:22],
      gotw[i][36:29], expw[i][36:29], gotw[i][37], expw[i][37]);
   end
  end
  if (fails == 0) $display("SCAN PASS points=%0d", n_points);
  else $display("SCAN FAILURES=%0d", fails);
  $finish;
 end

 initial begin
  #(NFRM * F * 12 + 200000);
  $display("SCAN TIMEOUT points=%0d reason=%0d busy=%0d", n_points, reason, busy);
  $finish;
 end
endmodule
