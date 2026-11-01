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
(* async_reg="true" *) reg [7:0] web_error_meta,web_error_sync;
always @(posedge clk_pixel or negedge rstn_pixel)
 if(!rstn_pixel)begin web_error_meta<=0;web_error_sync<=0;end
 else begin web_error_meta<=ddr_error_status;web_error_sync<=web_error_meta;end
host_result_bridge #(.TASK_ID(1)) web_bridge(
 .sys_clk(clk_sys),.sys_rst_n(rstn_sys),.source_clk(clk_pixel),.source_rst_n(rstn_pixel),
 .source_status(web_source_status),.apply_boundary(web_vs_d && !lcd_vs),.app_ready(1'b1),
 .rx(uart_rx_i),.tx(uart_tx_o),.app_valid(web_app_valid),.app_code(web_app_code),.app_value(web_app_value));
