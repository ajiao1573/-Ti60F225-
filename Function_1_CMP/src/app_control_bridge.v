`ifndef APP_CONTROL_BRIDGE_V
`define APP_CONTROL_BRIDGE_V
// Bundled-data toggle mailbox. Source holds a snapshot until destination has
// acknowledged it; the toggle traverses three registers before data is used.
module status_snapshot #(parameter WIDTH=32)(
 input source_clk,source_rst_n,input [WIDTH-1:0] source_data,
 input target_clk,target_rst_n,input request,
 output busy,output reg valid,output reg [WIDTH-1:0] data
);
 reg request_toggle,ack_toggle;
 reg [2:0] request_sync,ack_sync;
 reg [WIDTH-1:0] held;
 assign busy=request_toggle!=ack_sync[2];
 always @(posedge source_clk or negedge source_rst_n)
  if(!source_rst_n) begin request_sync<=0;ack_toggle<=0;held<=0;end
  else begin
   request_sync<={request_sync[1:0],request_toggle};
   if(request_sync[2]!=ack_toggle) begin held<=source_data;ack_toggle<=request_sync[2];end
  end
 reg waiting;
 always @(posedge target_clk or negedge target_rst_n)
  if(!target_rst_n) begin request_toggle<=0;ack_sync<=0;data<=0;valid<=0;waiting<=0;end
  else begin
   ack_sync<={ack_sync[1:0],ack_toggle};valid<=0;
   if(request && !busy && !waiting) begin request_toggle<=!request_toggle;waiting<=1;end
   if(waiting && !busy) begin data<=held;valid<=1;waiting<=0;end
  end
endmodule

// System UART stays responsive even if the camera is absent. Camera controls
// use a separate mailbox and are only applied at an independent sensor SOP.
module app_control_bridge #(parameter CLOCK_HZ=96000000)(
 input sys_clk,sys_rst_n,cam_clk,cam_rst_n,frame_boundary,
 input command_valid,input [7:0] command_code,input [15:0] command_value,
 output command_ready,input [383:0] camera_status,output reg [383:0] status_payload,
 output reg [9:0] edge_threshold,output reg run_enable,
 output reg remote_load,output reg [7:0] remote_adjust,output reg remote_rescan
);
 reg req,ack;reg [2:0] ack_sync,req_sync;
 reg [7:0] held_code;reg [15:0] held_value;
 assign command_ready=req==ack_sync[2];
 always @(posedge sys_clk or negedge sys_rst_n)
 if(!sys_rst_n) begin req<=0;ack_sync<=0;held_code<=0;held_value<=0;end
 else begin
  ack_sync<={ack_sync[1:0],ack};
  if(command_valid && command_ready) begin held_code<=command_code;held_value<=command_value;req<=!req;end
 end
 always @(posedge cam_clk or negedge cam_rst_n)
 if(!cam_rst_n) begin
  req_sync<=0;ack<=0;edge_threshold<=27;run_enable<=1;remote_load<=0;remote_adjust<=128;remote_rescan<=0;
 end else begin
  req_sync<={req_sync[1:0],req};remote_load<=0;remote_rescan<=0;
  if(frame_boundary && req_sync[2]!=ack) begin
   case(held_code)
    8'h10:edge_threshold<=held_value[9:0];
    8'h11:begin remote_adjust<=held_value[7:0];remote_load<=1;end
    8'h14:run_enable<=held_value[0];
   endcase
   remote_rescan<=1;ack<=req_sync[2];
  end
 end
 reg [23:0] timer;
 reg [16:0] heartbeat;
 always @(posedge cam_clk or negedge cam_rst_n)
  if(!cam_rst_n) heartbeat<=0;else heartbeat<=heartbeat+1'b1;
 reg [2:0] heartbeat_sync;
 reg [23:0] idle_count;reg camera_alive;
 always @(posedge sys_clk or negedge sys_rst_n)
 if(!sys_rst_n) begin heartbeat_sync<=0;idle_count<=0;camera_alive<=0;end
 else begin
  heartbeat_sync<={heartbeat_sync[1:0],heartbeat[16]};
  if(heartbeat_sync[2]!=heartbeat_sync[1]) begin idle_count<=0;camera_alive<=1;end
  else if(idle_count<CLOCK_HZ/8) idle_count<=idle_count+1'b1;
  else camera_alive<=0;
 end
 wire sample_request=timer==0;
 wire sampled;wire [383:0] sampled_status;
 status_snapshot #(.WIDTH(384)) snapshot(
  .source_clk(cam_clk),.source_rst_n(cam_rst_n),.source_data(camera_status),
  .target_clk(sys_clk),.target_rst_n(sys_rst_n),.request(sample_request),
  .busy(),.valid(sampled),.data(sampled_status));
 always @(posedge sys_clk or negedge sys_rst_n)
 if(!sys_rst_n) begin
  timer<=0;status_payload<=0;
  status_payload[0+:8]<=1;status_payload[3*8+:8]<=8'h80;
  status_payload[4*8+:16]<=27;status_payload[6*8+:8]<=128;
  status_payload[8*8+:48]<=48'h3f3f3f3f3f3f;
  status_payload[36*8+:16]<=1920;status_payload[38*8+:16]<=1080;
  status_payload[40*8+:16]<=848;status_payload[42*8+:16]<=477;
  status_payload[45*8+:8]<=1;status_payload[46*8+:16]<=1;
 end else begin
  timer<=timer==CLOCK_HZ/10-1 ? 0:timer+1'b1;
  if(sampled) status_payload<=sampled_status;
  if(!camera_alive) begin
   status_payload[2*8+:8]<=0;
   status_payload[3*8+:8]<={status_payload[3*8+7],7'd0};
   status_payload[8*8+:48]<=48'h3f3f3f3f3f3f;
  end
 end
endmodule
`endif
