module host_result_bridge #(parameter CLOCK_HZ=96000000,TASK_ID=1,WIDTH=1920,HEIGHT=1080,PROC_W=960,PROC_H=540)(
input sys_clk,sys_rst_n,source_clk,source_rst_n,input[383:0]source_status,input apply_boundary,app_ready,rx,output tx,app_valid,output[7:0]app_code,output[15:0]app_value);
assign tx=1;assign app_valid=0;assign app_code=0;assign app_value=0;endmodule
`define ML_ACC_W 29
module tb;
reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;
wire clk_sys=cmos_pclk;reg rstn_sys=0,uart_rx_i=1;wire uart_tx_o;
reg ml_selftest_start=0,ml_selftest_clear=0,scan_busy=0,filter_busy=0,num_busy=0,ml_feat_request_ready=1;
reg[2:0]live_state=0;reg scan_start=0,ml_res_valid=0,ml_res_source=0,i2c_config_done=1;
reg[1:0]ml_res_class=0;reg signed[28:0]ml_res_acc=0;reg[11:0]sample_id=0,ml_res_frame_id=0;
reg[3:0]ml_res_reason=0;reg[4:0]num_reason=0,scan_reason=0;
reg[9:0]saved_count=0,scan_count=0;
// HOST_WEB_RESULT_ENDPOINT: complete transaction latched in camera domain.
wire web_app_valid;wire [7:0] web_app_code;wire [15:0] web_app_value;
wire web_sample=ml_selftest_start || (web_app_valid && web_app_code==8'h21);
wire web_clear=ml_selftest_clear || (web_app_valid && web_app_code==8'h22);
wire web_work_busy=live_state!=0 || scan_busy || filter_busy || num_busy || !ml_feat_request_ready;
reg web_have_result;reg [1:0] web_class;reg signed [31:0] web_acc;
reg [11:0] web_id;reg [3:0] web_reason;reg [4:0] web_numeric_reason,web_scan_reason;
reg [9:0] web_points,web_scan_points;
always @(posedge cmos_pclk or negedge rstn_sys)
 if(!rstn_sys)begin
  web_have_result<=0;web_class<=2;web_acc<=0;web_id<=0;web_reason<=0;
  web_numeric_reason<=0;web_scan_reason<=0;web_points<=0;web_scan_points<=0;
 end else if(web_clear || scan_start)begin
  web_have_result<=0;web_acc<=0;web_id<=sample_id;web_reason<=0;web_numeric_reason<=0;
  web_scan_reason<=0;web_points<=0;web_scan_points<=0;
 end else if(ml_res_valid && !ml_res_source)begin
  web_have_result<=1;web_class<=ml_res_class;web_acc<={{(32-`ML_ACC_W){ml_res_acc[`ML_ACC_W-1]}},ml_res_acc};
  web_id<=ml_res_frame_id;web_reason<=ml_res_reason;web_numeric_reason<=num_reason;
  web_scan_reason<=scan_reason;web_points<=saved_count;web_scan_points<=scan_count;
 end
reg [383:0] web_source_status;
always @* begin
 web_source_status=0;web_source_status[0+:8]=1;web_source_status[8+:8]=3;
 web_source_status[2*8+:8]=!i2c_config_done ? 0:web_work_busy ? 2:!web_have_result ? 1:
     web_class==0 ? 3:web_class==1 ? 4:5;
 web_source_status[3*8+:8]={1'b1,1'b0,(web_have_result && !web_work_busy),4'b0,i2c_config_done};
 web_source_status[4*8+:16]=27;web_source_status[6*8+:8]=3;
 web_source_status[7*8+:8]={4'd0,web_reason};
 web_source_status[8*8+:32]=web_acc;web_source_status[12*8+:16]={6'd0,web_points};
 web_source_status[14*8+:8]={3'd0,web_scan_reason};web_source_status[15*8+:8]={6'd0,web_class};
 web_source_status[16*8+:16]=128;web_source_status[18*8+:16]=8;
 web_source_status[20*8+:16]=704;web_source_status[22*8+:16]=704;
 web_source_status[28*8+:8]={3'd0,web_numeric_reason};web_source_status[30*8+:16]={6'd0,web_scan_points};
 web_source_status[32*8+:32]={20'd0,(web_have_result ? web_id:sample_id)};
 web_source_status[36*8+:16]=960;web_source_status[38*8+:16]=720;
 web_source_status[40*8+:16]=960;web_source_status[42*8+:16]=720;
 web_source_status[45*8+:8]=1;web_source_status[46*8+:16]=8;
end
host_result_bridge #(.TASK_ID(3),.WIDTH(960),.HEIGHT(720),.PROC_W(960),.PROC_H(720)) web_bridge(
 .sys_clk(clk_sys),.sys_rst_n(rstn_sys),.source_clk(cmos_pclk),.source_rst_n(rstn_sys),
 .source_status(web_source_status),.apply_boundary(1'b1),.app_ready(!web_work_busy),
 .rx(uart_rx_i),.tx(uart_tx_o),.app_valid(web_app_valid),.app_code(web_app_code),.app_value(web_app_value));

task tick;begin @(negedge cmos_pclk);end endtask
task show;begin #1;$display("STATUS %096h",web_source_status);end endtask
initial begin
tick;rstn_sys=1;tick;show;
live_state=1;tick;show;
live_state=0;ml_res_valid=1;ml_res_acc=-5325003;ml_res_frame_id=7;sample_id=7;saved_count=245;scan_count=318;tick;ml_res_valid=0;show;
scan_start=1;sample_id=8;tick;scan_start=0;show;
ml_res_valid=1;ml_res_class=2;ml_res_reason=1;num_reason=9;ml_res_frame_id=8;tick;ml_res_valid=0;show;
ml_selftest_clear=1;tick;ml_selftest_clear=0;show;
$finish;end
endmodule
