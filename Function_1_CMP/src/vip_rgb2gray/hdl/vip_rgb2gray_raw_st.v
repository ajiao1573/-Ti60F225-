//File name  :vip_rgb2gray_raw_st
//Module name:vip_rgb2gray_raw_st.v
//Author     :hanjunma111
//Email      :865021481@qq.com
//Version    :V1.0
//Abstract   :RGB转灰度，默认颜色通道为并行3通道，BPS可参数化设置,Avalon-ST裸流接口
// Y = (R*306 + G*601 + B*117)/1024
//R:sink_data[3*BPS-1 : 2*BPS]
//G:sink_data[2*BPS-1 : BPS]
//B:sink_data[BPS-1   : 0]
//总延迟：4个clk 乘法器4个、加法2个
module vip_rgb2gray_raw_st #(
parameter BPS    = 8,
parameter WIDTH  = 480,
parameter HEIGHT = 272
)(
    input              clk,
	input              rst_n,
    input              sink_sop,
    input              sink_valid,
    input  [3*BPS-1:0] sink_data,
    input              sink_eop,
    output             sink_ready,
    output             source_sop,
    output             source_valid,
    output [BPS-1:0]   source_data,
    output             source_eop,
    input              source_ready
);
wire [BPS-1:0] data_w0;
wire           sop_w0,eop_w0,valid_w0;
wire           fifo_almost_full_w,fifo_empty_w,fifo_rd_w;
wire [BPS-1:0] fifo_q_w;
wire           fifo_aclr_w;
assign sink_ready = !fifo_almost_full_w;
vip_rgb2gray_proc #(
    .BPS(BPS)
)vip_rgb2gray_proc_0
(
    .clk(clk),
    .rst_n(rst_n),
    .sink_sop(sink_sop),
    .sink_valid(sink_valid),
    .sink_data(sink_data),
    .sink_eop(sink_eop),
    .source_sop(sop_w0),
    .source_valid(valid_w0),
    .source_data(data_w0),
    .source_eop(eop_w0)
);
vip_rgb2gray_shift_regs#(
    .DWIDTH(1),   //数据位宽
    .DELAY_DUTY(1)//延迟的时钟周期数，最小是1
)vip_rgb2gray_shift_regs_0
(
    .clk(clk),
    .rst_n(rst_n),
    .idata(sink_sop && sink_valid),
    .odata(fifo_aclr_w)
);
vip_rgb2gray_scfifo #(
    .DWIDTH(BPS)
)
u_vip_rgb2gray_scfifo_0 (
    .aclr(~rst_n),//(fifo_aclr_w),
    .clock(clk),
    .data(data_w0),
    .rdreq(fifo_rd_w),
    .wrreq(valid_w0),
    .almost_full(fifo_almost_full_w),
    .empty(fifo_empty_w),
    .q(fifo_q_w)
);
vip_rgb2gray_fifo2st #(
    .DWIDTH(BPS),
    .TOTAL_PIXELS(WIDTH*HEIGHT)
)
u_vip_rgb2gray_fifo2st_0
(
    .clk(clk),              //本模块将FIFO数据转化成非标Avalon-ST视频流，即不带控制包头，并且无视频数据包头，sop对应一帧的第一个有效数据,eop对应一帧的最后一个有效数据
    .rst_n(rst_n),
    .fifo_aclr(~rst_n),//(fifo_aclr_w),        //外部模块需要根据视频流特征生成扇出FIFO的异步aclr信号
    .fifo_empty(fifo_empty_w),       //FIFO空标志信号
    .fifo_q(fifo_q_w),
    .fifo_rd(fifo_rd_w),
    .source_sop(source_sop),
    .source_valid(source_valid),
    .source_data(source_data),
    .source_eop(source_eop),
    .source_ready(source_ready)
               );
endmodule 