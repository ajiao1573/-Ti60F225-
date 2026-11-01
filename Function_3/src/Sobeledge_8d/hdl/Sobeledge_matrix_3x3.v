// 实现3*3像素矩阵输出，忽略图像边界2像素宽度数据
// 根据有效数据计数生成矩阵的sop eop valid信号
module Sobeledge_matrix_3x3 #(
parameter	WIDTH=480,
parameter	HEIGHT=320,
parameter	DATA_WIDTH=8
)(
	input			clk,
	input			rst_n,
	
	input			sink_sop,
	input			sink_eop,
	input			sink_valid,
	input	[DATA_WIDTH-1:0]	sink_data,
	
	output			matrix_sop,
	output			matrix_eop,
	output			matrix_valid,
	output	reg	[DATA_WIDTH-1:0]	matrix_p11,matrix_p12,matrix_p13,
	output	reg	[DATA_WIDTH-1:0]	matrix_p21,matrix_p22,matrix_p23,
	output	reg	[DATA_WIDTH-1:0]	matrix_p31,matrix_p32,matrix_p33
);

wire [DATA_WIDTH-1:0]	row1_data,row2_data;
wire  matrix_en;
reg	[DATA_WIDTH-1:0]	row3_data;
always@(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
		row3_data<='d0;
	end
	else begin
		if(sink_valid)
			row3_data<=sink_data;
		else
			row3_data<=row3_data;
	end
end
// 缓存两行，与当前输入行构成三行输出
extract_region_c_shiftram_xtap #(
	.DISTANCE(WIDTH),	// 抽头间间距，跟随实际图像行宽
	.DWIDTH(DATA_WIDTH),	// 数据位宽
	.TAPS_NUM(2)		// 抽头数
)u_linebuffers(
	.clken(sink_valid),
	.clock(clk),
	.shiftin(row3_data),
	.shiftout(),
	.taps({row1_data,row2_data})
);

// sink_valid延迟一个clk，生成matrix_en信号，用于矩阵生成
shift_regs#(
.DWIDTH(1),     
.DELAY_DUTY(1)
)u2_shift_regs(
    .clk(clk),
	.rst_n(rst_n),
	.idata(sink_valid),
	.odata(matrix_en)
);
// 生成3*3像素矩阵
always@(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
		{matrix_p11,matrix_p12,matrix_p13}<='d0;
		{matrix_p21,matrix_p22,matrix_p23}<='d0;
		{matrix_p31,matrix_p32,matrix_p33}<='d0;
	end
	else begin
		if(matrix_en)begin
			{matrix_p11,matrix_p12,matrix_p13}<={matrix_p12,matrix_p13,row1_data};
			{matrix_p21,matrix_p22,matrix_p23}<={matrix_p22,matrix_p23,row2_data};
			{matrix_p31,matrix_p32,matrix_p33}<={matrix_p32,matrix_p33,row3_data};
		end
		else begin
			{matrix_p11,matrix_p12,matrix_p13}<={matrix_p11,matrix_p12,matrix_p13};
			{matrix_p21,matrix_p22,matrix_p23}<={matrix_p21,matrix_p22,matrix_p23};
			{matrix_p31,matrix_p32,matrix_p33}<={matrix_p31,matrix_p32,matrix_p33};
		end
	end
end

reg [11:0] cnt;
always@(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
		cnt<=12'd0;
	end
	else if(sink_valid && sink_sop)begin
		cnt<=12'd0;
	end
	else if(matrix_en)begin
		cnt<=(cnt>WIDTH+2)?cnt:cnt+1'b1;
	end
	else begin
		cnt<=cnt;
	end
end
// 对有效的图像数据进行计数
reg [11:0] xcnt,ycnt;

always@(posedge clk or negedge rst_n)begin
	if(!rst_n)begin
		xcnt<=12'd0;
		ycnt<=12'd0;
	end
	else if(cnt==WIDTH+1 && matrix_en)begin
		xcnt<=12'd0;
		ycnt<=12'd0;
	end
	else if(matrix_en)begin
		xcnt<=(xcnt>=WIDTH-1)?12'd0:xcnt+1'b1;
		ycnt<=(xcnt>=WIDTH-1)?((ycnt>=HEIGHT-1)?12'd0:ycnt+1'b1):ycnt;
	end
	else begin
		xcnt<=xcnt;
		ycnt<=ycnt;
	end
end
// 生成matrix_valid matrix_sop matrix_eop信号
assign matrix_valid=(matrix_en==1'b1 && (cnt>=WIDTH+2||ycnt!=12'd0)&& ~(ycnt==12'd1 && cnt<WIDTH+2))?1'b1:1'b0;
assign matrix_sop=(xcnt==12'd0 && ycnt==12'd0 && cnt==WIDTH+2 && matrix_valid)?1'b1:1'b0;
assign matrix_eop=(ycnt==HEIGHT-1 && xcnt==WIDTH-1 && matrix_valid)?1'b1:1'b0;


endmodule

