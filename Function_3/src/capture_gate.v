`ifndef CAPTURE_GATE_V
`define CAPTURE_GATE_V
`timescale 1ns/1ps
// Local frame gate for the realtime (no-DDR) path.
//
// upstream split_frame_ctrl used to hold capture_ready low between frames and
// raise it only after the DDR write response came back, i.e. DDR doubled as the
// frame gate. With DDR removed that feedback never returns, so the gate is
// rebuilt here from local state only.
//
// No per-frame arbitration is needed: canny_frame already refuses re-entry via
// its internal occupied flag (set on frame_start, cleared on edge_valid &&
// edge_eop) and exposes it as busy. A frame that arrives while the previous one
// is still draining is simply skipped, which is exactly the back-pressure the
// DDR handshake used to provide. This module therefore only has to keep the very
// first frames out while the sensor, PLLs and CDC synchronisers settle.
module capture_gate #(
 parameter WARMUP_BITS=12
)(
 input clk,
 input rst_n,
 output ready
);
 reg [WARMUP_BITS-1:0] warm;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) warm<=0;
  else if(!(&warm)) warm<=warm+1'b1;
 end
 assign ready=&warm;
endmodule
`endif
