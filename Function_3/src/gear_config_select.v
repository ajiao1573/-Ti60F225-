`ifndef GEAR_CONFIG_SELECT_V
`define GEAR_CONFIG_SELECT_V
// ---------------------------------------------------------------------------
// Maps the front-panel gear to the video-processing configuration.
//
// Gears 1..5 keep the original behaviour exactly, including the legacy SHAPE
// threshold offset of -10 in gear 5 and the DDR temporal request of algorithm 4.
//
// Gear 6 (gear index 5) forces the verified Canny+Median configuration with an
// actual processing threshold of 27, suppresses the SHAPE threshold offset and
// suppresses the temporal (DDR/display) request.  The mode flag is only updated
// on a legal frame boundary, so entering or leaving gear 6 never swaps the
// threshold/algorithm pair inside a frame.  The former five-gear configuration
// is restored by the same mechanism one frame after the gear changes back.
// ---------------------------------------------------------------------------
module gear_config_select #(
 parameter [2:0] ML_GEAR              = 3'd5,
 parameter [2:0] SHAPE_GEAR           = 3'd4,
 parameter [9:0] ML_THRESHOLD         = 10'd27,
 parameter [1:0] ML_SPATIAL           = 2'd3,
 parameter [9:0] SHAPE_THRESHOLD_STEP = 10'd10
)(
 input clk,
 input rst_n,
 input frame_boundary,
 input [2:0] gear,
 input [2:0] algorithm_requested,
 input [9:0] threshold_requested,
 output ml_active,
 output [1:0] spatial_algorithm,
 output [9:0] processing_threshold,
 output temporal_requested,
 output shape_requested
);
 reg ml_latched;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) ml_latched <= 1'b0;
  else if(frame_boundary) ml_latched <= (gear == ML_GEAR);
 end
 assign ml_active = ml_latched;
 // The SHAPE blocks follow the gear directly, as in the original design, but
 // they stay disabled while the ML configuration is still latched: during the
 // transition frame the video pipeline is still configured for gear 6, and the
 // two configurations must never be enabled at the same time.
 assign shape_requested = (gear == SHAPE_GEAR) && !ml_latched;

 wire [9:0] shape_threshold = (threshold_requested > SHAPE_THRESHOLD_STEP)
                              ? (threshold_requested - SHAPE_THRESHOLD_STEP) : 10'd0;
 wire alg_is_majority = (algorithm_requested == 3'd4);

 assign processing_threshold = ml_latched ? ML_THRESHOLD :
                               shape_requested ? shape_threshold : threshold_requested;
 assign temporal_requested = !ml_latched && alg_is_majority;
 assign spatial_algorithm = ml_latched ? ML_SPATIAL :
                            alg_is_majority ? 2'd3 : algorithm_requested[1:0];
endmodule
`endif
