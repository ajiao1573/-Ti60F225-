module vip_rgb2gray_top #(
parameter BPS    = 8,
parameter WIDTH  = 480,
parameter HEIGHT = 320
)
(
    input clk,
	input rst_n,
	//sink 
	input             sink_sop,
	input             sink_eop,
	input             sink_valid,
	input [BPS*3-1:0] sink_data,
	output            sink_ready,
	//source
	output            source_sop,
	output            source_eop,
	output            source_valid,
	output [BPS-1:0]  source_data,
	input             source_ready
);

vip_rgb2gray_raw_st #(
	.BPS(BPS),
	.WIDTH(WIDTH),
	.HEIGHT(HEIGHT)
)u_vip_rgb2gray_raw_st_0
(
    .clk(clk),
	.rst_n(rst_n),
    .sink_sop(sink_sop),
    .sink_valid(sink_valid),
    .sink_data(sink_data),
    .sink_eop(sink_eop),
    .sink_ready(sink_ready),
    .source_sop(source_sop),
    .source_valid(source_valid),
    .source_data(source_data),
    .source_eop(source_eop),
    .source_ready(source_ready)
);

endmodule 