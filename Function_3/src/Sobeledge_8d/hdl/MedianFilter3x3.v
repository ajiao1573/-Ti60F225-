// 3x3 median filter for an 8-bit grayscale video stream.
//
// The nine window samples are sorted by an odd-even transposition network.
// Each of the nine network levels contains four parallel compare/exchange
// units and is separated by registers.  The result therefore sustains one
// pixel per clock without a long, serial nine-element sort in one cycle.

module median_compare_exchange_8 (
	input  [7:0] data_a,
	input  [7:0] data_b,
	output [7:0] data_lo,
	output [7:0] data_hi
);
	assign data_lo = (data_a <= data_b) ? data_a : data_b;
	assign data_hi = (data_a <= data_b) ? data_b : data_a;
endmodule

// Compare (0,1), (2,3), (4,5), (6,7); item 8 passes through.
module median_sort_even_phase_8 (
	input  [71:0] data_in,
	output [71:0] data_out
);
	median_compare_exchange_8 u_cmp01(data_in[7:0],   data_in[15:8],  data_out[7:0],   data_out[15:8]);
	median_compare_exchange_8 u_cmp23(data_in[23:16], data_in[31:24], data_out[23:16], data_out[31:24]);
	median_compare_exchange_8 u_cmp45(data_in[39:32], data_in[47:40], data_out[39:32], data_out[47:40]);
	median_compare_exchange_8 u_cmp67(data_in[55:48], data_in[63:56], data_out[55:48], data_out[63:56]);
	assign data_out[71:64] = data_in[71:64];
endmodule

// Item 0 passes through; compare (1,2), (3,4), (5,6), (7,8).
module median_sort_odd_phase_8 (
	input  [71:0] data_in,
	output [71:0] data_out
);
	assign data_out[7:0] = data_in[7:0];
	median_compare_exchange_8 u_cmp12(data_in[15:8],  data_in[23:16], data_out[15:8],  data_out[23:16]);
	median_compare_exchange_8 u_cmp34(data_in[31:24], data_in[39:32], data_out[31:24], data_out[39:32]);
	median_compare_exchange_8 u_cmp56(data_in[47:40], data_in[55:48], data_out[47:40], data_out[55:48]);
	median_compare_exchange_8 u_cmp78(data_in[63:56], data_in[71:64], data_out[63:56], data_out[71:64]);
endmodule

module MedianFilter3x3 #(
	parameter WIDTH  = 480,
	parameter HEIGHT = 320
)(
	input        clk,
	input        rst_n,
	input        sink_sop,
	input        sink_eop,
	input        sink_valid,
	input  [7:0] sink_data,
	output       source_sop,
	output       source_eop,
	output       source_valid,
	output [7:0] source_data
);
	wire [7:0] window_p11,window_p12,window_p13;
	wire [7:0] window_p21,window_p22,window_p23;
	wire [7:0] window_p31,window_p32,window_p33;
	wire       window_sop,window_eop,window_valid;

	Sobeledge_matrix_3x3 #(
		.WIDTH(WIDTH),
		.HEIGHT(HEIGHT),
		.DATA_WIDTH(8)
	) u_window_3x3 (
		.clk(clk),
		.rst_n(rst_n),
		.sink_sop(sink_sop),
		.sink_eop(sink_eop),
		.sink_valid(sink_valid),
		.sink_data(sink_data),
		.matrix_sop(window_sop),
		.matrix_eop(window_eop),
		.matrix_valid(window_valid),
		.matrix_p11(window_p11),
		.matrix_p12(window_p12),
		.matrix_p13(window_p13),
		.matrix_p21(window_p21),
		.matrix_p22(window_p22),
		.matrix_p23(window_p23),
		.matrix_p31(window_p31),
		.matrix_p32(window_p32),
		.matrix_p33(window_p33)
	);

	// Element 0 occupies bits [7:0].  After nine alternating phases all
	// elements are ascending, so element 4 ([39:32]) is the exact median.
	wire [71:0] sort_input = {
		window_p33, window_p32, window_p31,
		window_p23, window_p22, window_p21,
		window_p13, window_p12, window_p11
	};
	wire [71:0] phase1_next,phase2_next,phase3_next;
	wire [71:0] phase4_next,phase5_next,phase6_next;
	wire [71:0] phase7_next,phase8_next,phase9_next;
	reg  [71:0] sort_stage1,sort_stage2,sort_stage3;
	reg  [71:0] sort_stage4,sort_stage5,sort_stage6;
	reg  [71:0] sort_stage7,sort_stage8,sort_stage9;

	median_sort_even_phase_8 u_phase1(sort_input,   phase1_next);
	median_sort_odd_phase_8  u_phase2(sort_stage1, phase2_next);
	median_sort_even_phase_8 u_phase3(sort_stage2, phase3_next);
	median_sort_odd_phase_8  u_phase4(sort_stage3, phase4_next);
	median_sort_even_phase_8 u_phase5(sort_stage4, phase5_next);
	median_sort_odd_phase_8  u_phase6(sort_stage5, phase6_next);
	median_sort_even_phase_8 u_phase7(sort_stage6, phase7_next);
	median_sort_odd_phase_8  u_phase8(sort_stage7, phase8_next);
	median_sort_even_phase_8 u_phase9(sort_stage8, phase9_next);

	reg [8:0] sop_pipe;
	reg [8:0] eop_pipe;
	reg [8:0] valid_pipe;
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			sort_stage1 <= 72'd0;
			sort_stage2 <= 72'd0;
			sort_stage3 <= 72'd0;
			sort_stage4 <= 72'd0;
			sort_stage5 <= 72'd0;
			sort_stage6 <= 72'd0;
			sort_stage7 <= 72'd0;
			sort_stage8 <= 72'd0;
			sort_stage9 <= 72'd0;
			sop_pipe    <= 9'd0;
			eop_pipe    <= 9'd0;
			valid_pipe  <= 9'd0;
		end else begin
			sort_stage1 <= phase1_next;
			sort_stage2 <= phase2_next;
			sort_stage3 <= phase3_next;
			sort_stage4 <= phase4_next;
			sort_stage5 <= phase5_next;
			sort_stage6 <= phase6_next;
			sort_stage7 <= phase7_next;
			sort_stage8 <= phase8_next;
			sort_stage9 <= phase9_next;
			sop_pipe    <= {sop_pipe[7:0], window_sop};
			eop_pipe    <= {eop_pipe[7:0], window_eop};
			valid_pipe  <= {valid_pipe[7:0], window_valid};
		end
	end

	assign source_data  = sort_stage9[39:32];
	assign source_sop   = sop_pipe[8];
	assign source_eop   = eop_pipe[8];
	assign source_valid = valid_pipe[8];
endmodule
