// 图像Sobel边缘检测IP，可实现灰度图像数据的Sobel边缘检测
// 可配置参数图像宽度WIDTH 高度HEIGHT Sobel边缘检测阈值Sobel_Threshold
module Sobeledge #(
parameter WIDTH  = 480,
parameter HEIGHT = 272
)(
    input              clk,
	 input              rst_n,
	 input              edge_en,//边缘检测使能，高有效
	 input              bin_en,//二值化使能，高有效
	 input [9:0]        edge_threshold,
    input              sink_sop,
    input              sink_valid,
    input  [7:0]	     sink_data,			//灰度数据
    input              sink_eop,
    output             sink_ready,
    output             source_sop,
    output             source_valid,
    output [7:0]	     source_data,			//边缘强度
    output             source_eop,
    input              source_ready
);
wire [7:0]     data_w0;
wire           sop_w0,eop_w0,valid_w0;
wire [7:0]     data_w1;
wire           sop_w1,eop_w1,valid_w1;
wire [7:0]     data_w2;
wire           sop_w2,eop_w2,valid_w2;
wire		      ready_w0,ready_w1;
wire [15:0]		im_width,im_height;
wire [3:0]	   video_inter;
wire [7:0]     source_data0;
/*
// 解包模块
decode #(
.DATA_WIDTH(8),
.COLOR_BITS(8),
.COLOR_PLANES(1)
)Sobeledge_decode(
	.clk(clk),
	.rst_n(rst_n),

	.im_width(im_width),
	.im_height(im_height),
	.im_interlaced(video_inter),

	.din_data(sink_data),
	.din_valid(sink_valid),
	.din_ready(sink_ready),
	.din_startofpacket(sink_sop),
	.din_endofpacket(sink_eop),

	.dout_data(data_w0),
	.dout_valid(valid_w0),
	.dout_ready(ready_w0),
	.dout_startofpacket(sop_w0),
	.dout_endofpacket(eop_w0)
);
*/
// Sobel边缘检测实现模块
Sobeledge_8d_proc #(
.WIDTH(WIDTH),     
.HEIGHT(HEIGHT)
)Sobeledge_proc_0
(
    .clk(clk),
    .rst_n(rst_n),
	 .edge_en(edge_en),//边缘检测使能，高有效
	 .bin_en(bin_en),//二值化使能，高有效
	 .edge_threshold(edge_threshold),
	 .sink_sop(sink_sop),
    .sink_valid(sink_valid),
    .sink_data(sink_data),				
    .sink_eop(sink_eop),
	 
    .source_sop(sop_w1),
    .source_valid(valid_w1),
    .source_data(data_w1),
    .source_eop(eop_w1)
);
// 同步模块
ast_readylatency_adapt#(
.DWIDTH(8),    
.FIFO_DEPTH(1024) 
)Sobeledge_readylatency_adapt(
	.clk(clk),
	.rst_n(rst_n),
	.sink_sop(sop_w1),
	.sink_valid(valid_w1),
	.sink_data(data_w1),
	.sink_eop(eop_w1), 
	.sink_ready(sink_ready),
	
	.source_sop(source_sop),
	.source_valid(source_valid),
	.source_data(source_data),
	.source_eop(source_eop),
	.source_ready(source_ready)
);
/*
// 打包模块
encode #(
.DATA_WIDTH(8),
.DATA_BITS(8),
.DATA_PLANES(1)
)Sobeledge_encode(
	.clk(clk),
	.rst_n(rst_n),

	.video_width(im_width),
	.video_height(im_height),
	.video_interlaced(video_inter),

	.din_data(source_data0),
	.din_valid(valid_w2),
	.din_ready(ready_w1),
	.din_startofpacket(sop_w2),
	.din_endofpacket(eop_w2),

	.dout_data(source_data),
	.dout_valid(source_valid),
	.dout_ready(source_ready),
	.dout_startofpacket(source_sop),
	.dout_endofpacket(source_eop)
);
*/
endmodule 
