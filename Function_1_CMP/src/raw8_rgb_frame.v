`ifndef RAW8_RGB_FRAME_V
`define RAW8_RGB_FRAME_V
`include "src/canny/canny_window.v"
// Center-aligned bilinear BGGR demosaic. Reflect missing neighbors within
// the CURRENT frame: old-frame row RAM contents never become image borders.
module raw8_rgb_frame #(parameter IMG_HDISP=1920,IMG_VDISP=1080)(
 input clk,rst_n,input [1:0] mirror,
 input per_frame_vsync,per_frame_href,per_frame_hsync,input [7:0] per_img_RAW,
 output post_frame_vsync,output reg post_frame_href,output post_frame_hsync,
 output reg [7:0] post_img_red,post_img_green,post_img_blue
);
 localparam XW=$clog2(IMG_HDISP),YW=$clog2(IMG_VDISP);
 reg [XW-1:0] ix,ox;reg [YW-1:0] iy,oy;
 wire take=per_frame_vsync && per_frame_href;
 wire sop=take && ix==0 && iy==0;
 wire eop=take && ix==IMG_HDISP-1 && iy==IMG_VDISP-1;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin ix<=0;iy<=0;end
  else if(!per_frame_vsync) begin ix<=0;iy<=0;end
  else if(take) begin
   if(ix==IMG_HDISP-1) begin ix<=0;iy<=iy==IMG_VDISP-1 ? 0 : iy+1'b1;end
   else ix<=ix+1'b1;
  end
 wire v,s,e,border;wire [7:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
 canny_window #(.WIDTH(IMG_HDISP),.HEIGHT(IMG_VDISP),.DW(8)) window3(
  .clk(clk),.rst_n(rst_n),.in_valid(take),.in_sop(sop),.in_eop(eop),.in_data(per_img_RAW),
  .out_valid(v),.out_sop(s),.out_eop(e),.border(border),
  .p11(p11),.p12(p12),.p13(p13),.p21(p21),.p22(p22),.p23(p23),.p31(p31),.p32(p32),.p33(p33));
 wire [XW-1:0] x=s ? 0 : ox;wire [YW-1:0] y=s ? 0 : oy;
 wire left=x!=0,right=x!=IMG_HDISP-1,top=y!=0,bottom=y!=IMG_VDISP-1;
 wire [7:0] l=left ? p21:p23,r=right ? p23:p21,t=top ? p12:p32,b=bottom ? p32:p12;
 wire [7:0] tl=top ? (left ? p11:p13) : (left ? p31:p33);
 wire [7:0] tr=top ? (right ? p13:p11) : (right ? p33:p31);
 wire [7:0] bl=bottom ? (left ? p31:p33) : (left ? p11:p13);
 wire [7:0] br=bottom ? (right ? p33:p31) : (right ? p13:p11);
 wire [9:0] axes={2'b0,l}+{2'b0,r}+{2'b0,t}+{2'b0,b};
 wire [9:0] diagonals={2'b0,tl}+{2'b0,tr}+{2'b0,bl}+{2'b0,br};
 wire [8:0] horizontal={1'b0,l}+{1'b0,r},vertical={1'b0,t}+{1'b0,b};
 wire [1:0] phase={y[0],x[0]}^mirror;
 reg frame_active;
 assign post_frame_vsync=frame_active || post_frame_href;
 assign post_frame_hsync=post_frame_href;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin ox<=0;oy<=0;frame_active<=0;post_frame_href<=0;post_img_red<=0;post_img_green<=0;post_img_blue<=0;end
  else begin
   post_frame_href<=v;
   if(v) begin
    if(s) frame_active<=1;
    if(e) begin frame_active<=0;ox<=0;oy<=0;end
    else if(x==IMG_HDISP-1) begin ox<=0;oy<=y+1'b1;end else begin ox<=x+1'b1;oy<=y;end
    case(phase)
     0:begin post_img_blue<=p22;post_img_green<=axes[9:2];post_img_red<=diagonals[9:2];end
     1:begin post_img_green<=p22;post_img_blue<=horizontal[8:1];post_img_red<=vertical[8:1];end
     2:begin post_img_green<=p22;post_img_red<=horizontal[8:1];post_img_blue<=vertical[8:1];end
     3:begin post_img_red<=p22;post_img_green<=axes[9:2];post_img_blue<=diagonals[9:2];end
    endcase
   end
  end
 end
endmodule
`endif
