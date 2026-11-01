`ifndef ML_RESULT_SYNC_V
`define ML_RESULT_SYNC_V
// ---------------------------------------------------------------------------
// One-bundle result snapshot crossing from the processing clock to the display
// clock.
//
// The whole result record (source, state, class, vector index, test verdict,
// signed accumulator, decimal digits, frame identifier) travels on ONE bus.  A
// toggle is raised whenever the source copy changes; the receiver only captures
// the record when that toggle pipeline is quiet, which proves the captured bus
// had been stable for at least two destination clocks and therefore came from a
// single source sample.  Fields are never synchronised independently, so the
// display can never combine the accumulator of one transaction with the class of
// another.
//
// The capture itself is armed by the display vertical blanking event, so the
// panel keeps one record for a whole frame.  Because the capture is qualified by
// "quiet" rather than by "toggle edge seen", a burst of source updates that is
// faster than the display clock cannot leave a stale record on screen: once the
// burst stops, the next blanking event shows the newest complete record.
// ---------------------------------------------------------------------------
module ml_result_sync #(
 parameter integer W = 77
)(
 input src_clk,
 input src_rst_n,
 input [W-1:0] src_bundle,
 input dst_clk,
 input dst_rst_n,
 input dst_latch,
 output reg [W-1:0] dst_bundle
);
 reg [W-1:0] bundle_q;
 reg toggle_src;
 always @(posedge src_clk or negedge src_rst_n) begin
  if(!src_rst_n) begin
   bundle_q<= {W{1'b0}};
   toggle_src<=1'b0;
  end else begin
   bundle_q<=src_bundle;
   if(bundle_q != src_bundle) toggle_src<=~toggle_src;
  end
 end

 reg t_meta, t_sync;
 reg [W-1:0] meta, sync;
 // 1 when the toggle has already reached every synchroniser stage, i.e. no
 // source update is in flight.
 wire quiet = (toggle_src == t_meta) && (t_meta == t_sync);
 // The capture enable is registered so that the record taken at a blanking
 // event is one that was already settled on the previous destination clock.
 reg armed;
 always @(posedge dst_clk or negedge dst_rst_n) begin
  if(!dst_rst_n) begin
   t_meta<=1'b0; t_sync<=1'b0;
   meta<={W{1'b0}}; sync<={W{1'b0}};
   armed<=1'b0;
   dst_bundle<={W{1'b0}};
  end else begin
   t_meta<=toggle_src;
   t_sync<=t_meta;
   meta<=bundle_q;
   sync<=meta;
   armed<=quiet;
   if(dst_latch && armed) dst_bundle<=sync;
  end
 end
endmodule
`endif
