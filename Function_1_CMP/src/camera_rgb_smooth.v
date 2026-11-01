`ifndef CAMERA_RGB_SMOOTH_V
`define CAMERA_RGB_SMOOTH_V
`include "src/canny/canny_window.v"
// Streaming per-channel 3x3 binomial anti-alias filter. Packed RGB shares
// the window/valid counters; mirror borders only use the current frame.
module camera_rgb_smooth #(parameter WIDTH=1920,HEIGHT=1080,EDGE_AWARE=0,FLAT_RANGE=24)(
 input clk,rst_n,in_frame,in_valid,input [23:0] in_rgb,
 output out_frame,output out_valid,output reg [23:0] out_rgb
);
 reg [$clog2(WIDTH)-1:0] x;
 reg [$clog2(HEIGHT)-1:0] y;
 wire take=in_frame && in_valid;
 wire sop=take && x==0 && y==0;
 wire eop=take && x==WIDTH-1 && y==HEIGHT-1;
 always @(posedge clk or negedge rst_n)
 if(!rst_n) begin x<=0;y<=0;end
 else if(!in_frame) begin x<=0;y<=0;end
 else if(take) begin
  if(x==WIDTH-1) begin x<=0;y<=y==HEIGHT-1 ? 0:y+1'b1;end else x<=x+1'b1;
 end
 wire v,s,e,border;wire [23:0] a11,a12,a13,a21,a22,a23,a31,a32,a33;
 canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(24),.REFLECT_BORDER(1)) window3(
 .clk(clk),.rst_n(rst_n),.in_valid(take),.in_sop(sop),.in_eop(eop),.in_data(in_rgb),
 .out_valid(v),.out_sop(s),.out_eop(e),.border(border),
 .p11(a11),.p12(a12),.p13(a13),.p21(a21),.p22(a22),.p23(a23),.p31(a31),.p32(a32),.p33(a33));
 reg [2:0] ctrl1,ctrl2;
 always @(posedge clk or negedge rst_n)
 if(!rst_n) begin ctrl1<=0;ctrl2<=0;end
 else begin ctrl1<={s,e,v};ctrl2<=ctrl1;end
 function [7:0] min3;
 input [7:0] a,b,c;
 begin min3=a<b ? (a<c ? a:c) : (b<c ? b:c);end
 endfunction
 function [7:0] max3;
 input [7:0] a,b,c;
 begin max3=a>b ? (a>c ? a:c) : (b>c ? b:c);end
 endfunction
 wire [2:0] flat_channel;
 wire flat_region=&flat_channel;
 genvar c;
 generate for(c=0;c<3;c=c+1) begin:color
  reg [9:0] top,mid,bot;
  reg [7:0] center,local_range;
  reg preserve_edge;
  wire [7:0] min_top=min3(a11[c*8+:8],a12[c*8+:8],a13[c*8+:8]);
  wire [7:0] min_mid=min3(a21[c*8+:8],a22[c*8+:8],a23[c*8+:8]);
  wire [7:0] min_bot=min3(a31[c*8+:8],a32[c*8+:8],a33[c*8+:8]);
  wire [7:0] max_top=max3(a11[c*8+:8],a12[c*8+:8],a13[c*8+:8]);
  wire [7:0] max_mid=max3(a21[c*8+:8],a22[c*8+:8],a23[c*8+:8]);
  wire [7:0] max_bot=max3(a31[c*8+:8],a32[c*8+:8],a33[c*8+:8]);
  wire [7:0] local_min=min3(min_top,min_mid,min_bot);
  wire [7:0] local_max=max3(max_top,max_mid,max_bot);
  wire [9:0] xp={2'd0,a13[c*8+:8]}+{1'b0,a23[c*8+:8],1'b0}+{2'd0,a33[c*8+:8]};
  wire [9:0] xn={2'd0,a11[c*8+:8]}+{1'b0,a21[c*8+:8],1'b0}+{2'd0,a31[c*8+:8]};
  wire [9:0] yp={2'd0,a31[c*8+:8]}+{1'b0,a32[c*8+:8],1'b0}+{2'd0,a33[c*8+:8]};
  wire [9:0] yn={2'd0,a11[c*8+:8]}+{1'b0,a12[c*8+:8],1'b0}+{2'd0,a13[c*8+:8]};
  wire [9:0] ax=xp>=xn ? xp-xn:xn-xp;
  wire [9:0] ay=yp>=yn ? yp-yn:yn-yp;
  wire [9:0] axis= ax>ay ? ax:ay;
  wire [7:0] range_now=local_max-local_min;
  wire [10:0] range_times7=({3'd0,range_now}<<3)-{3'd0,range_now};
  // A coherent weak ramp has G/range near4, even when its contrast is small.
  // Preserve it using a relative test, independent of the user's edge THR.
  assign flat_channel[c]=local_range<=FLAT_RANGE && !preserve_edge;
  wire [11:0] sum={2'd0,top}+{1'b0,mid,1'b0}+{2'd0,bot}+12'd8;
  always @(posedge clk or negedge rst_n)
  if(!rst_n) begin top<=0;mid<=0;bot<=0;center<=0;local_range<=0;preserve_edge<=0;out_rgb[c*8+:8]<=0;end
  else begin
   top<={2'd0,a11[c*8+:8]}+{1'b0,a12[c*8+:8],1'b0}+{2'd0,a13[c*8+:8]};
   mid<={2'd0,a21[c*8+:8]}+{1'b0,a22[c*8+:8],1'b0}+{2'd0,a23[c*8+:8]};
   bot<={2'd0,a31[c*8+:8]}+{1'b0,a32[c*8+:8],1'b0}+{2'd0,a33[c*8+:8]};
   center<=a22[c*8+:8];local_range<=local_max-local_min;
   preserve_edge<=range_now!=0 && {axis,1'b0}>=range_times7;
   // Shared RGB decision preserves colored edges as well as luminance edges.
   out_rgb[c*8+:8]<=EDGE_AWARE && !flat_region ? center : sum[11:4];
  end
 end endgenerate
 reg active;
 always @(posedge clk or negedge rst_n)
 if(!rst_n) active<=0;
 else if(ctrl2[0]) begin if(ctrl2[2]) active<=1;if(ctrl2[1]) active<=0;end
 assign out_valid=ctrl2[0];
 assign out_frame=active || ctrl2[0];
endmodule
`endif
