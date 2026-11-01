`ifndef ML_GEAR6_VH
`define ML_GEAR6_VH
// Gear 6 (machine-learning interface) source bundle.  Included by example_top.v
// so that an Efinity project that re-saves an older source list still reaches
// these modules, exactly like src/canny/canny_rtl.vh.
`include "src/ml_int13_params.vh"
`include "src/ml_selftest_vectors.vh"
`include "src/ml_dec9.v"
`include "src/ml_int13_classifier.v"
`include "src/ml_gear6_ctrl.v"
`include "src/ml_result_sync.v"
`include "src/gear_config_select.v"
`include "src/ml_status_osd.v"
`endif
