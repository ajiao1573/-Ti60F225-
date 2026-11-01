`ifndef CALIBRATION_CAPTURE_V
`define CALIBRATION_CAPTURE_V
// Diagnostic thumbnail of a complete live camera frame, independent of OCR
// freeze. Source samples (6*x,6*y); sys port reads only after completion ACK.
module calibration_capture(
 input cam_clk,sys_clk,rst_n,arm,input in_valid,in_sop,in_eop,
 input [10:0] x,y,input [7:0] gray,
 input read_enable,input [15:0] read_address,output reg [7:0] read_data,
 output ready
);
 reg [7:0] pixels[0:57599];reg [2:0] arm_sync,done_sync;
 reg seen,done,active,ever;reg[15:0] index;
 wire start=in_valid&&in_sop&&arm_sync[2]!=seen;
 wire sample=in_valid&&(active||start)&&x%6==0&&y%6==0;
 always @(posedge cam_clk)if(sample)pixels[start ? 16'd0:index]<=gray;
 always @(posedge sys_clk)if(read_enable)read_data<=pixels[read_address];
 always @(posedge sys_clk or negedge rst_n)
 if(!rst_n)begin done_sync<=0;ever<=0;end
 else begin done_sync<={done_sync[1:0],done};if(arm)ever<=1;end
 assign ready=ever&&done_sync[2]==arm;
 always @(posedge cam_clk or negedge rst_n)
 if(!rst_n)begin arm_sync<=0;seen<=0;done<=0;active<=0;index<=0;end
 else begin
  arm_sync<={arm_sync[1:0],arm};
  if(start)begin seen<=arm_sync[2];active<=1;index<=1;end
  else if(sample)index<=index+1'b1;
  if(in_valid&&in_eop&&(active||start))begin active<=0;done<=seen;end
 end
endmodule
`endif
