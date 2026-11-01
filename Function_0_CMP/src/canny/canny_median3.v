`ifndef TI60_CANNY_MEDIAN3_V
`define TI60_CANNY_MEDIAN3_V
// Exact 3x3 median prefilter for impulse noise. Nine pipelined odd/even
// compare-exchange levels sustain one pixel per clock; frame borders bypass.
module canny_median3 #(parameter WIDTH=848,HEIGHT=636,BORDER_REFLECT=0)(
 input clk,input rst_n,input in_valid,input in_sop,input in_eop,
 input [7:0] in_data,
 output out_valid,output out_sop,output out_eop,output [7:0] out_data
);
 wire v,s,e,b;
 wire [7:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
 canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(8),.REFLECT_BORDER(BORDER_REFLECT)) window3(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_sop(in_sop),.in_eop(in_eop),.in_data(in_data),
  .out_valid(v),.out_sop(s),.out_eop(e),.border(b),
  .p11(p11),.p12(p12),.p13(p13),.p21(p21),.p22(p22),.p23(p23),.p31(p31),.p32(p32),.p33(p33));
 wire [71:0] stage[0:9];
 wire [11:0] meta[0:9];
 assign stage[0]={p33,p32,p31,p23,p22,p21,p13,p12,p11};
 assign meta[0]={b,p22,s,e,v};
 genvar k,j;
 generate for(k=0;k<9;k=k+1) begin:levels
  wire [71:0] next_data;
  reg [71:0] data_q;
  reg [11:0] meta_q;
  for(j=0;j<9;j=j+1) begin:items
   if(j<8 && j%2==k%2) begin:lo
    assign next_data[j*8+:8]=stage[k][j*8+:8]<stage[k][(j+1)*8+:8] ? stage[k][j*8+:8] : stage[k][(j+1)*8+:8];
   end else if(j>0 && (j-1)%2==k%2) begin:hi
    assign next_data[j*8+:8]=stage[k][j*8+:8]>stage[k][(j-1)*8+:8] ? stage[k][j*8+:8] : stage[k][(j-1)*8+:8];
   end else begin:pass
    assign next_data[j*8+:8]=stage[k][j*8+:8];
   end
  end
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin data_q<=0;meta_q<=0;end
   else begin data_q<=next_data;meta_q<=meta[k];end
  end
  assign stage[k+1]=data_q;assign meta[k+1]=meta_q;
 end endgenerate
 assign out_data=meta[9][11] && !BORDER_REFLECT ? meta[9][10:3] : stage[9][39:32];
 assign out_valid=meta[9][0];assign out_sop=meta[9][2];assign out_eop=meta[9][1];
endmodule
`endif
