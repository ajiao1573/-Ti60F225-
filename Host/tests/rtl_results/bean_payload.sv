module host_result_bridge #(parameter CLOCK_HZ=96000000,TASK_ID=1,WIDTH=1920,HEIGHT=1080,PROC_W=960,PROC_H=540)(
input sys_clk,sys_rst_n,source_clk,source_rst_n,input[383:0]source_status,input apply_boundary,app_ready,rx,output tx,app_valid,output[7:0]app_code,output[15:0]app_value);
assign tx=1;assign app_valid=0;assign app_code=0;assign app_value=0;endmodule
`include "bean/bean_config.vh"
module tb;
localparam VIDEO_WIDTH=1920,VIDEO_HEIGHT=1080;
reg clk_pixel=0;always #5 clk_pixel=~clk_pixel;
wire clk_sys=clk_pixel;reg rstn_sys=0,rstn_pixel=0,uart_rx_i=1;wire uart_tx_o;
reg lcd_vs=1,video_ready_pixel=1,video_error_pixel=0,bean_overflow=0,bean_busy=0,frozen_pixel=1,bean_result_valid=1,runtime_menu=0;
reg[15:0]bean_count=0;reg[7:0]ddr_error_status=0;
(* async_reg="true" *) reg [7:0] web_error_meta,web_error_sync;
// HOST_WEB_RESULT_ENDPOINT: pixel-domain results; system-domain UART.
wire web_app_valid;wire [7:0] web_app_code;wire [15:0] web_app_value;
wire [`BEAN_CFG_BITS-1:0] web_config;
wire [15:0] web_boxes;wire [31:0] web_result_id;
reg [383:0] web_source_status;
reg web_vs_d;
always @(posedge clk_pixel or negedge rstn_pixel)
 if(!rstn_pixel)web_vs_d<=1;else web_vs_d<=lcd_vs;
always @* begin
 web_source_status=0;
 web_source_status[0+:8]=1;web_source_status[8+:8]=1;
 web_source_status[2*8+:8]=!video_ready_pixel ? 0:video_error_pixel || bean_overflow ? 4:bean_busy ? 2:frozen_pixel ? 3:1;
 web_source_status[3*8+:8]={1'b1,frozen_pixel,(bean_result_valid && !bean_overflow),
    (video_error_pixel || bean_overflow),3'b0,video_ready_pixel};
 web_source_status[4*8+:16]={8'd0,web_config[`BC_THRESHOLD]};
 web_source_status[6*8+:8]={5'd0,web_config[`BC_DARK],web_config[`BC_VIEW]};
 web_source_status[7*8+:8]={7'd0,video_error_pixel || bean_overflow};
 web_source_status[8*8+:16]=bean_count;
 web_source_status[10*8+:16]=web_boxes;
 // AXI error bits are diagnostic and synchronized separately below.
 web_source_status[14*8+:8]=web_error_sync;
 web_source_status[15*8+:8]={7'd0,runtime_menu};
 web_source_status[16*8+:16]={4'd0,web_config[`BC_X0]};
 web_source_status[18*8+:16]={4'd0,web_config[`BC_Y0]};
 web_source_status[20*8+:16]=web_config[`BC_X1]-web_config[`BC_X0];
 web_source_status[22*8+:16]=web_config[`BC_Y1]-web_config[`BC_Y0];
 web_source_status[32*8+:32]=web_result_id;
 web_source_status[36*8+:16]=VIDEO_WIDTH;web_source_status[38*8+:16]=VIDEO_HEIGHT;
 web_source_status[40*8+:16]=VIDEO_WIDTH/2;web_source_status[42*8+:16]=VIDEO_HEIGHT/2;
 web_source_status[45*8+:8]=1;web_source_status[46*8+:16]=2;
end

always @(posedge clk_pixel or negedge rstn_pixel)
 if(!rstn_pixel)begin web_error_meta<=0;web_error_sync<=0;end
 else begin web_error_meta<=ddr_error_status;web_error_sync<=web_error_meta;end
host_result_bridge #(.TASK_ID(1)) web_bridge(
 .sys_clk(clk_sys),.sys_rst_n(rstn_sys),.source_clk(clk_pixel),.source_rst_n(rstn_pixel),
 .source_status(web_source_status),.apply_boundary(web_vs_d && !lcd_vs),.app_ready(1'b1),
 .rx(uart_rx_i),.tx(uart_tx_o),.app_valid(web_app_valid),.app_code(web_app_code),.app_value(web_app_value));

assign web_config={12'd240,12'd240,12'd5,12'd5,20'd11250,20'd36,12'd1008,12'd1824,12'd72,12'd96,2'd2,1'b1,8'd112};
assign web_boxes=0;assign web_result_id=19;
initial begin
@(negedge clk_pixel);rstn_sys=1;rstn_pixel=1;repeat(3)@(negedge clk_pixel);
#1;$display("STATUS %096h",web_source_status);
bean_count=129;#1;$display("STATUS %096h",web_source_status);
video_error_pixel=1;#1;$display("STATUS %096h",web_source_status);
$finish;end
endmodule
