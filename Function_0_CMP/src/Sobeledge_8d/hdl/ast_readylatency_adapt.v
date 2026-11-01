//Avalon-ST视频流readylatency适配器
module ast_readylatency_adapt#(
parameter DWIDTH       = 10,
parameter WIDTH        = 640,
parameter HEIGHT       = 51,
parameter FIFO_DEPTH   = 1024 //FIFO的深度，必须为2的整数次方倍切大于32
)(
input               clk,
input               rst_n,
input               sink_sop,
input               sink_valid,
input  [DWIDTH-1:0] sink_data,
input               sink_eop, 
output              sink_ready,             
output              source_sop,
output              source_valid,
output [DWIDTH-1:0] source_data,
output              source_eop,
input               source_ready
);
wire fifo_rd_w,fifo_empty_w,fifo_almost_full_w;
reg source_valid_r;
assign fifo_rd_w    = !fifo_empty_w && source_ready;
assign sink_ready   = !fifo_almost_full_w;
assign source_valid = source_valid_r;
ast_readylatency_adapt_scfifo#(
    .DWIDTH(DWIDTH+2),
    .NUMWORDS(FIFO_DEPTH)
    )
u_ast_readylatency_adapt_scfifo_0 (
    .aclr(!rst_n),
    .clock(clk),
    .data({sink_sop,sink_eop,sink_data}),
    .rdreq(fifo_rd_w),
    .wrreq(sink_valid),
    .almost_full(fifo_almost_full_w),
    .empty(fifo_empty_w),
    .q({source_sop,source_eop,source_data})
    );
always@(posedge clk or negedge rst_n)
begin
if(rst_n == 1'b0)
    source_valid_r <= 1'b0;
else
    source_valid_r <= fifo_rd_w;
end
endmodule 