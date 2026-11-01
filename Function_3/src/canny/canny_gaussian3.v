`ifndef TI60_CANNY_GAUSSIAN3_V
`define TI60_CANNY_GAUSSIAN3_V
// Separable binomial Gaussian [1 2 1;2 4 2;1 2 1]/16, rounded.
module canny_gaussian3 #(parameter WIDTH=848,HEIGHT=636,BORDER_REFLECT=0)(
 input clk,input rst_n,input in_valid,input in_sop,input in_eop,input [7:0] in_data,
 output out_valid,output out_sop,output out_eop,output reg [7:0] out_data
);
 wire v,s,e,b;
 wire [7:0] a11,a12,a13,a21,a22,a23,a31,a32,a33;
 canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(8),.REFLECT_BORDER(BORDER_REFLECT)) window3(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_sop(in_sop),.in_eop(in_eop),.in_data(in_data),
  .out_valid(v),.out_sop(s),.out_eop(e),.border(b),
  .p11(a11),.p12(a12),.p13(a13),.p21(a21),.p22(a22),.p23(a23),.p31(a31),.p32(a32),.p33(a33));
 reg [9:0] top,mid,bot;
 reg [7:0] center;
 reg [3:0] ctrl1;
 reg [2:0] ctrl2;
 wire [11:0] sum={2'b0,top}+{1'b0,mid,1'b0}+{2'b0,bot}+12'd8;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin top<=0;mid<=0;bot<=0;center<=0;ctrl1<=0;ctrl2<=0;out_data<=0;end
  else begin
   top<={2'b0,a11}+{1'b0,a12,1'b0}+{2'b0,a13};
   mid<={2'b0,a21}+{1'b0,a22,1'b0}+{2'b0,a23};
   bot<={2'b0,a31}+{1'b0,a32,1'b0}+{2'b0,a33};
   center<=a22;ctrl1<={b,s,e,v};
   out_data<=ctrl1[3] && !BORDER_REFLECT ? center : sum[11:4];ctrl2<=ctrl1[2:0];
  end
 end
 assign out_valid=ctrl2[0];assign out_sop=ctrl2[2];assign out_eop=ctrl2[1];
endmodule
`endif
