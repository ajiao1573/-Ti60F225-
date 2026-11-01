`ifndef NATIVE_GRAY_CAPTURE_V
`define NATIVE_GRAY_CAPTURE_V
// Admit a whole source frame at its first pixel, then finish despite enable
// dropping during capture. The OCR branch shares this exact source SOP.
module native_gray_capture #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,rst_n,enable,in_frame,in_valid,input [23:0] in_rgb,
 output take,output start,output last,output [7:0] gray,output [10:0] source_x,source_y
);
 reg [10:0] x,y;reg accepting;
 assign source_x=x;assign source_y=y;
 wire sop=in_frame && in_valid && x==0 && y==0;
 assign start=sop && enable;
 assign take=in_valid && (start || accepting);
 assign last=take && x==WIDTH-1 && y==HEIGHT-1;
 wire [9:0] luma={2'b0,in_rgb[23:16]}+{1'b0,in_rgb[15:8],1'b0}+{2'b0,in_rgb[7:0]};
 assign gray=luma[9:2];
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin x<=0;y<=0;accepting<=0;end
  else begin
   if(!in_frame)begin x<=0;y<=0;end
   else if(in_valid)begin
    if(x==WIDTH-1)begin x<=0;y<=y==HEIGHT-1 ? 0:y+1'b1;end
    else x<=x+1'b1;
   end
   if(sop)accepting<=enable;
   if(last)accepting<=0;
  end
endmodule
`endif
