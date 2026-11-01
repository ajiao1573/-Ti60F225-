`ifndef VIDEO_THUMBNAIL2_V
`define VIDEO_THUMBNAIL2_V
// 2x2 box average, dropping the unpaired last row/column. One synchronous
// RGB row RAM. The four pixels always belong to the accepted current frame.
module video_thumbnail2 #(parameter WIDTH=848)(
 input clk,rst_n,in_valid,input [10:0] in_x,in_y,input [23:0] in_rgb,
 output reg out_valid,out_eol,output reg [23:0] out_rgb
);
 reg [23:0] row[0:WIDTH-1];
 reg [23:0] above,current,left,above_left;
 reg [10:0] xq,yq;reg vq;
 wire [9:0] sum_r={2'd0,above[23:16]}+{2'd0,current[23:16]}+{2'd0,left[23:16]}+{2'd0,above_left[23:16]}+10'd2;
 wire [9:0] sum_g={2'd0,above[15:8]}+{2'd0,current[15:8]}+{2'd0,left[15:8]}+{2'd0,above_left[15:8]}+10'd2;
 wire [9:0] sum_b={2'd0,above[7:0]}+{2'd0,current[7:0]}+{2'd0,left[7:0]}+{2'd0,above_left[7:0]}+10'd2;
 always @(posedge clk) if(in_valid) begin above<=row[in_x];row[in_x]<=in_rgb;current<=in_rgb;end
 always @(posedge clk or negedge rst_n)
 if(!rst_n) begin vq<=0;xq<=0;yq<=0;out_valid<=0;out_eol<=0;out_rgb<=0;left<=0;above_left<=0;end
 else begin
  vq<=in_valid;
  if(in_valid) begin xq<=in_x;yq<=in_y;end
  out_valid<=vq && xq[0] && yq[0];out_eol<=vq && xq==WIDTH-1 && yq[0];
  if(vq) begin
   left<=current;above_left<=above;
   if(xq[0] && yq[0]) out_rgb<={sum_r[9:2],sum_g[9:2],sum_b[9:2]};
  end
 end
endmodule
`endif
