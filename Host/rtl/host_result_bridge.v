`ifndef HOST_RESULT_BRIDGE_V
`define HOST_RESULT_BRIDGE_V
// Bundled status snapshot and command mailbox. Held buses settle while their
// toggle traverses three synchronizer stages. UART always uses clk_sys.
module host_result_bridge #(
 parameter CLOCK_HZ=96000000,TASK_ID=1,WIDTH=1920,HEIGHT=1080,PROC_W=960,PROC_H=540
)(input sys_clk,sys_rst_n,source_clk,source_rst_n,
 input [383:0] source_status,input apply_boundary,input app_ready,
 input rx,output tx,output reg app_valid,output reg [7:0] app_code,output reg [15:0] app_value);
 wire command_valid;wire [7:0] command_code;wire [15:0] command_value;
 reg req,ack;reg [7:0] held_code;reg [15:0] held_value;
 (* async_reg="true" *) reg [2:0] req_sync,ack_sync;
 wire command_ready=req==ack_sync[2];
 reg [383:0] payload;
 host_uart #(.CLOCK_HZ(CLOCK_HZ),.APP_TASK(TASK_ID)) uart(
  .clk(sys_clk),.rst_n(sys_rst_n),.rx(rx),.tx(tx),.status_payload(payload),
  .command_ready(command_ready),.command_valid(command_valid),.command_code(command_code),.command_value(command_value),
  .image_ready(1'b0),.image_data(8'd0));
 always @(posedge sys_clk or negedge sys_rst_n)
  if(!sys_rst_n)begin req<=0;ack_sync<=0;held_code<=0;held_value<=0;end
  else begin ack_sync<={ack_sync[1:0],ack};
   if(command_valid && command_ready)begin held_code<=command_code;held_value<=command_value;req<=!req;end
  end
 always @(posedge source_clk or negedge source_rst_n)
  if(!source_rst_n)begin req_sync<=0;ack<=0;app_valid<=0;app_code<=0;app_value<=0;end
  else begin req_sync<={req_sync[1:0],req};app_valid<=0;
   if(req_sync[2]!=ack && apply_boundary && (app_ready || held_code==8'h22))begin
    app_valid<=1;app_code<=held_code;app_value<=held_value;ack<=req_sync[2];
   end
  end
 reg [23:0] timer,dead_count;reg snap_req,snap_ack;reg [383:0] held_status;
 (* async_reg="true" *) reg [2:0] snap_req_sync,snap_ack_sync;
 reg [16:0] heartbeat;
 (* async_reg="true" *) reg [2:0] heartbeat_sync;
 wire alive=dead_count<CLOCK_HZ/8;
 always @(posedge source_clk or negedge source_rst_n)
  if(!source_rst_n)begin snap_req_sync<=0;snap_ack<=0;held_status<=0;heartbeat<=0;end
  else begin
   heartbeat<=heartbeat+1'b1;snap_req_sync<={snap_req_sync[1:0],snap_req};
   if(snap_req_sync[2]!=snap_ack)begin held_status<=source_status;snap_ack<=snap_req_sync[2];end
  end
 reg waiting;
 always @(posedge sys_clk or negedge sys_rst_n)
  if(!sys_rst_n)begin
   timer<=0;snap_req<=0;snap_ack_sync<=0;waiting<=0;heartbeat_sync<=0;dead_count<=CLOCK_HZ/8;
   payload<=0;payload[0+:8]<=1;payload[8+:8]<=TASK_ID;
   payload[36*8+:16]<=WIDTH;payload[38*8+:16]<=HEIGHT;
   payload[40*8+:16]<=PROC_W;payload[42*8+:16]<=PROC_H;
   payload[45*8+:8]<=1;payload[46*8+:16]<=1<<TASK_ID;
  end else begin
   timer<=timer==CLOCK_HZ/10-1 ? 0:timer+1'b1;
   heartbeat_sync<={heartbeat_sync[1:0],heartbeat[16]};
   if(heartbeat_sync[2]!=heartbeat_sync[1])dead_count<=0;
   else if(dead_count<CLOCK_HZ/8)dead_count<=dead_count+1'b1;
   snap_ack_sync<={snap_ack_sync[1:0],snap_ack};
   if(timer==0 && !waiting)begin snap_req<=!snap_req;waiting<=1;end
   if(waiting && snap_req==snap_ack_sync[2])begin payload<=held_status;waiting<=0;end
   if(!alive)begin payload[2*8+:8]<=0;payload[3*8+:8]<=0;end
  end
endmodule
`endif
