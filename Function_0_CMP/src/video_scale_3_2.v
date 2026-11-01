`ifndef VIDEO_SCALE_3_2_V
`define VIDEO_SCALE_3_2_V
// 1280x720 -> 1920x1080 nearest-neighbour presentation scaler.
// Reads each source pixel once; caches one RGB line for repeated output rows.
// Coordinates/request are the lcd_driver one-cycle-ahead interface.
module video_scale_3_2(
 input clk,rst_n,request,input [11:0] x_pos,y_pos,input [23:0] source_rgb,
 output [11:0] source_x,source_y,output source_request,output [23:0] rgb);
 wire repeat_x=x_pos%3==1;
 wire repeat_y=y_pos%3==1;
 assign source_x=(x_pos*2)/3;
 assign source_y=(y_pos*2)/3;
 assign source_request=request && !repeat_x && !repeat_y;
 reg [23:0] line_mem[0:1279];
 reg [23:0] held_rgb,replay_rgb;
 wire [11:0] next_source_x=x_pos>=1919 ? 0 : ((x_pos+1)*2)/3;
 // Read ahead to align synchronous BRAM data with the next LCD request.
 always @(posedge clk) begin
  replay_rgb<=line_mem[next_source_x];
  if(source_request) line_mem[source_x]<=source_rgb;
 end
 always @(posedge clk or negedge rst_n)
  if(!rst_n) held_rgb<=0;
  else if(source_request) held_rgb<=source_rgb;
 assign rgb=!request ? 24'd0 : repeat_y ? replay_rgb : repeat_x ? held_rgb : source_rgb;
endmodule
`endif
