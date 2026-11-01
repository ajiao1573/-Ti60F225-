// 实现8位灰度图像数据的Sobel边缘检测
// WIDTH、HEIGHT为图像参数
module Sobeledge_8d_proc#(
parameter WIDTH=480,
parameter HEIGHT=320
)(
	input			    clk,
	input			    rst_n,
	input           edge_en,//边缘检测使能，高有效
	input           bin_en,//二值化使能，高有效
	input  [9:0]    edge_threshold,
	//sink 
	input           sink_sop,
	input           sink_eop,
	input           sink_valid,
	input 	[7:0]  sink_data,			//原始数据
	//source
	output          source_sop,
	output          source_eop,
	output          source_valid,
	output  [7:0]   source_data,			//Sobel边缘检测结果
	output  [7:0]   source_gray_data		//与边缘结果对齐的滤波后灰度
);

// 灰度化之后、Sobel 之前先做精确 3x3 中值滤波。排序网络按级流水，
// 各级内的比较器并行工作，连续视频流仍可保持每拍一个像素。
wire [7:0] filtered_data;
wire       filter_sop,filter_eop,filter_valid;

MedianFilter3x3 #(
	.WIDTH(WIDTH),
	.HEIGHT(HEIGHT)
) u_median_filter_3x3 (
	.clk(clk),
	.rst_n(rst_n),
	.sink_sop(sink_sop),
	.sink_eop(sink_eop),
	.sink_valid(sink_valid),
	.sink_data(sink_data),
	.source_sop(filter_sop),
	.source_eop(filter_eop),
	.source_valid(filter_valid),
	.source_data(filtered_data)
);

// 对滤波后的像素再生成 3x3 矩阵进行 Sobel，避免噪点被放大成粗白块。
wire [15:0]		matrix_pack_p11,matrix_pack_p12,matrix_pack_p13;
wire [15:0]		matrix_pack_p21,matrix_pack_p22,matrix_pack_p23;
wire [15:0]		matrix_pack_p31,matrix_pack_p32,matrix_pack_p33;
wire [7:0]		matrix_p11 = matrix_pack_p11[15:8];
wire [7:0]		matrix_p12 = matrix_pack_p12[15:8];
wire [7:0]		matrix_p13 = matrix_pack_p13[15:8];
wire [7:0]		matrix_p21 = matrix_pack_p21[15:8];
wire [7:0]		matrix_p22 = matrix_pack_p22[15:8];
wire [7:0]		matrix_p23 = matrix_pack_p23[15:8];
wire [7:0]		matrix_p31 = matrix_pack_p31[15:8];
wire [7:0]		matrix_p32 = matrix_pack_p32[15:8];
wire [7:0]		matrix_p33 = matrix_pack_p33[15:8];
wire	matrix_sop,matrix_eop,matrix_valid;
wire [7:0]     matrix_gray_dly;//滤波灰度延迟4个时钟，和Gmax对齐
Sobeledge_matrix_3x3 #(
.WIDTH(WIDTH),
.HEIGHT(HEIGHT),
.DATA_WIDTH(16)
)u_Sobeledge_matrix_3x3(
	.clk(clk),
	.rst_n(rst_n),
	
	.sink_sop(filter_sop),
	.sink_eop(filter_eop),
	.sink_valid(filter_valid),
	// 高8位参与Sobel；低8位携带滤波灰度，仅做后续时序对齐。
	.sink_data({filtered_data,filtered_data}),
	
	.matrix_sop(matrix_sop),
	.matrix_eop(matrix_eop),
	.matrix_valid(matrix_valid),
	.matrix_p11(matrix_pack_p11),
	.matrix_p12(matrix_pack_p12),
	.matrix_p13(matrix_pack_p13),
	.matrix_p21(matrix_pack_p21),
	.matrix_p22(matrix_pack_p22),
	.matrix_p23(matrix_pack_p23),
	.matrix_p31(matrix_pack_p31),
	.matrix_p32(matrix_pack_p32),
	.matrix_p33(matrix_pack_p33)
);
// Step 1 计算卷积并求绝对值
// Sobel算子
//																
// 		[-1	-2		-1]			[-2	-1		 0]		[-1		0	   +1]		 [0	+1		+2]
// 0°	   [0		0		 0]	45°	[-1	0		+1] 90°  [-2		0	   +2]  135° [-1	0		+1]
//		   [+1	+2		+1]			[0		+1		+2]		[-1		0	   +1]		 [-2	-1		 0]

// 		[+1	+2		+1]			[+2	+1		 0]		[+1		0	   -1]		 [0	-1		-2]
// 180°	[0		0		 0]	225°  [+1	0		-1] 270° [+2		0	   -2]  315° [+1	0		-1]
//		   [-1	-2		-1]			[0		-1		-2]		[+1		0	   -1]		 [+2	+1		 0]
//通过观察可以发现，180°和0°的算子是对称的，二者结果的绝对值是相等的，同理225°、270°、315°
//因此只需要计算4组算子的卷积即可
reg	[9:0]	G0_p,G0_n,G0;
reg	[9:0]	G45_p,G45_n,G45;
reg	[9:0]	G90_p,G90_n,G90;
reg	[9:0]	G135_p,G135_n,G135;
//0°
always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
	begin
		G0_p <= 'd0;
		G0_n <= 'd0;
		G0   <= 'd0;
	end
	else begin
		G0_p <= matrix_p11 + ({1'b0,matrix_p12,1'b0}) + matrix_p13;
		G0_n <= matrix_p31 + ({1'b0,matrix_p32,1'b0}) + matrix_p33;
		G0   <= (G0_p>=G0_n) ? G0_p-G0_n:G0_n-G0_p;
	end	
end
//45°
always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
	begin
		G45_p <= 'd0;
		G45_n <= 'd0;
		G45   <= 'd0;
	end
	else begin
		G45_p <= matrix_p23 + ({1'b0,matrix_p33,1'b0}) + matrix_p32;
		G45_n <= matrix_p12 + ({1'b0,matrix_p11,1'b0}) + matrix_p21;	
		G45   <= (G45_p>=G45_n) ? G45_p-G45_n:G45_n-G45_p;
	end	
end
//90°
always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
	begin
		G90_p <= 'd0;
		G90_n <= 'd0;
		G90   <= 'd0;
	end
	else begin
		G90_p <= matrix_p13 + ({1'b0,matrix_p23,1'b0}) + matrix_p33;
		G90_n <= matrix_p11 + ({1'b0,matrix_p21,1'b0}) + matrix_p31;
		G90   <= (G90_p>=G90_n) ? G90_p-G90_n:G90_n-G90_p;
	end	
end
//135°
always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
	begin
		G135_p <= 'd0;
		G135_n <= 'd0;
		G135   <= 'd0;
	end
	else begin
		G135_p <= matrix_p12 + ({1'b0,matrix_p13,1'b0}) + matrix_p23;
		G135_n <= matrix_p21 + ({1'b0,matrix_p31,1'b0}) + matrix_p32;
		G135   <= (G135_p>=G135_n) ? G135_p-G135_n:G135_n-G135_p;
	end	
end
// Step 2 找最大的G
// Gmax = max(G0,G45,G90,G135)
reg [9:0] Gmax_0_45,Gmax_90_135;
reg [1:0] Gdir_0_45,Gdir_90_135;
reg [9:0] Gmax;//边缘强度
reg [1:0] Gdir;// 0:0°, 1:45°, 2:90°, 3:135°
always@(posedge clk or negedge rst_n)
begin
if(!rst_n)
    begin
    Gmax_0_45   <= 'd0;
    Gmax_90_135 <= 'd0;
	Gdir_0_45   <= 2'd0;
	Gdir_90_135 <= 2'd2;
    end
else
    begin
    Gmax_0_45   <= (G0 >= G45)?G0:G45;
    Gmax_90_135 <= (G90 >= G135)?G90:G135;
	Gdir_0_45   <= (G0 >= G45)?2'd0:2'd1;
	Gdir_90_135 <= (G90 >= G135)?2'd2:2'd3;
    end
end
always@(posedge clk or negedge rst_n)
begin
if(!rst_n) begin
	Gmax <= 'd0;
	Gdir <= 2'd0;
end
else begin
	Gmax <= (Gmax_0_45 >= Gmax_90_135)?Gmax_0_45:Gmax_90_135;
	Gdir <= (Gmax_0_45 >= Gmax_90_135)?Gdir_0_45:Gdir_90_135;
end
end

// Gmax/Gdir 与中心灰度、流控信号对齐。
wire gradient_sop,gradient_valid,gradient_eop;
shift_regs#(
.DWIDTH(3),     
.DELAY_DUTY(4)
)u_gradient_ctrl_delay(
    .clk(clk),
	.rst_n(rst_n),
	.idata({matrix_sop,matrix_valid,matrix_eop}),
	.odata({gradient_sop,gradient_valid,gradient_eop})
);
shift_regs#(
.DWIDTH(8),     
.DELAY_DUTY(4)
)u_gradient_gray_delay(
    .clk(clk),
	.rst_n(rst_n),
	.idata(matrix_pack_p22[7:0]),
	.odata(matrix_gray_dly)
);

// Step 3 非极大值抑制 (NMS)
// 沿梯度方向只保留局部峰值，将 Sobel 的双线/粗线压缩为约 1 像素。
wire [19:0] nms_p11,nms_p12,nms_p13;
wire [19:0] nms_p21,nms_p22,nms_p23;
wire [19:0] nms_p31,nms_p32,nms_p33;
wire        nms_sop,nms_eop,nms_valid;

Sobeledge_matrix_3x3 #(
	.WIDTH(WIDTH),
	.HEIGHT(HEIGHT),
	.DATA_WIDTH(20)
) u_nms_matrix (
	.clk(clk),
	.rst_n(rst_n),
	.sink_sop(gradient_sop),
	.sink_eop(gradient_eop),
	.sink_valid(gradient_valid),
	.sink_data({Gdir,Gmax,matrix_gray_dly}),
	.matrix_sop(nms_sop),
	.matrix_eop(nms_eop),
	.matrix_valid(nms_valid),
	.matrix_p11(nms_p11),
	.matrix_p12(nms_p12),
	.matrix_p13(nms_p13),
	.matrix_p21(nms_p21),
	.matrix_p22(nms_p22),
	.matrix_p23(nms_p23),
	.matrix_p31(nms_p31),
	.matrix_p32(nms_p32),
	.matrix_p33(nms_p33)
);

wire [1:0] nms_dir = nms_p22[19:18];
wire [9:0] nms_mag = nms_p22[17:8];
reg  [9:0] nms_neighbor_a;
reg  [9:0] nms_neighbor_b;

always @(*) begin
	case (nms_dir)
		2'd0: begin // 0° Sobel: 上/下比较
			nms_neighbor_a = nms_p12[17:8];
			nms_neighbor_b = nms_p32[17:8];
		end
		2'd1: begin // 45°: 左上/右下比较
			nms_neighbor_a = nms_p11[17:8];
			nms_neighbor_b = nms_p33[17:8];
		end
		2'd2: begin // 90°: 左/右比较
			nms_neighbor_a = nms_p21[17:8];
			nms_neighbor_b = nms_p23[17:8];
		end
		default: begin // 135°: 右上/左下比较
			nms_neighbor_a = nms_p13[17:8];
			nms_neighbor_b = nms_p31[17:8];
		end
	endcase
end

// 一边用 >=、另一边用 >，在相邻梯度相等时只保留其中一个像素。
wire nms_peak = (nms_mag >= nms_neighbor_a) && (nms_mag > nms_neighbor_b);

// Canny-style dual-threshold hysteresis.  A weak edge is retained only when
// one of its 8 neighbours is a strong edge.  This rejects isolated, unstable
// speckles without raising the user threshold enough to erase real contours.
localparam [9:0] HYSTERESIS_GAP = 10'd8;
wire [10:0] high_threshold_sum = {1'b0, edge_threshold} + HYSTERESIS_GAP;
wire [9:0]  high_threshold = high_threshold_sum[10] ? 10'd1023 :
                                                       high_threshold_sum[9:0];
wire nms_weak   = nms_peak && (nms_mag >= edge_threshold);
wire nms_strong = nms_peak && (nms_mag >= high_threshold);

wire [19:0] hyst_p11,hyst_p12,hyst_p13;
wire [19:0] hyst_p21,hyst_p22,hyst_p23;
wire [19:0] hyst_p31,hyst_p32,hyst_p33;
wire        hyst_sop,hyst_eop,hyst_valid;

Sobeledge_matrix_3x3 #(
	.WIDTH(WIDTH),
	.HEIGHT(HEIGHT),
	.DATA_WIDTH(20)
) u_hysteresis_matrix (
	.clk(clk),
	.rst_n(rst_n),
	.sink_sop(nms_sop),
	.sink_eop(nms_eop),
	.sink_valid(nms_valid),
	.sink_data({nms_strong,nms_weak,nms_mag,nms_p22[7:0]}),
	.matrix_sop(hyst_sop),
	.matrix_eop(hyst_eop),
	.matrix_valid(hyst_valid),
	.matrix_p11(hyst_p11),
	.matrix_p12(hyst_p12),
	.matrix_p13(hyst_p13),
	.matrix_p21(hyst_p21),
	.matrix_p22(hyst_p22),
	.matrix_p23(hyst_p23),
	.matrix_p31(hyst_p31),
	.matrix_p32(hyst_p32),
	.matrix_p33(hyst_p33)
);

wire strong_neighbour = hyst_p11[19] | hyst_p12[19] | hyst_p13[19] |
	                       hyst_p21[19] |                  hyst_p23[19] |
	                       hyst_p31[19] | hyst_p32[19] | hyst_p33[19];
wire hysteresis_edge = hyst_p22[19] | (hyst_p22[18] & strong_neighbour);
// One-bit temporal persistence map. Weak contours must survive for two
// adjacent frames at the same pixel; strong contours bypass this wait. This
// specifically removes frame-to-frame twinkling while keeping motion response
// for clearly defined objects. The array infers block RAM (about 0.9 Mbit).
localparam integer FRAME_PIXELS = WIDTH * HEIGHT;
reg edge_history [0:FRAME_PIXELS-1];
reg [19:0] history_addr;
reg        history_valid;
reg        history_ready_d;
reg        previous_edge_d;
reg        current_edge_d;
reg [19:0] hyst_center_d;
reg        hyst_sop_d,hyst_eop_d,hyst_valid_d;

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		history_addr <= 20'd0;
		history_valid <= 1'b0;
		history_ready_d <= 1'b0;
		previous_edge_d <= 1'b0;
		current_edge_d <= 1'b0;
		hyst_center_d <= 20'd0;
		hyst_sop_d <= 1'b0;
		hyst_eop_d <= 1'b0;
		hyst_valid_d <= 1'b0;
	end else begin
		hyst_valid_d <= hyst_valid;
		if(hyst_valid) begin
			previous_edge_d <= edge_history[history_addr];
			edge_history[history_addr] <= hysteresis_edge;
			current_edge_d <= hysteresis_edge;
			hyst_center_d <= hyst_p22;
			hyst_sop_d <= hyst_sop;
			hyst_eop_d <= hyst_eop;
			history_ready_d <= history_valid;
			if(hyst_eop) begin
				history_addr <= 20'd0;
				history_valid <= 1'b1;
			end else begin
				history_addr <= history_addr + 1'b1;
			end
		end
	end
end

wire temporal_edge = !history_ready_d ? current_edge_d :
	                   (hyst_center_d[19] |
	                   (current_edge_d & previous_edge_d));
wire [9:0] temporal_mag = hyst_center_d[17:8];

assign source_sop   = hyst_sop_d;
assign source_eop   = hyst_eop_d;
assign source_valid = hyst_valid_d;

assign source_data = edge_en ?
	(bin_en ? (temporal_edge ? 8'hff : 8'h00) :
	          (temporal_edge ? ((temporal_mag > 10'd510) ? 8'hff : temporal_mag[8:1]) : 8'h00)) :
	hyst_center_d[7:0];
assign source_gray_data = hyst_center_d[7:0];
endmodule
