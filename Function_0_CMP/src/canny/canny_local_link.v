`ifndef TI60_CANNY_LOCAL_LINK_V
`define TI60_CANNY_LOCAL_LINK_V
// Bounded, symmetric 8-neighbor linking. Each pass grows accepted edges by
// ONE candidate pixel. Two passes retain weak chains of at most two hops
// from a strong seed, without a frame map or iterative frame scans.
module canny_local_link #(parameter WIDTH=848,HEIGHT=636,PASSES=2,PROTECT_ENABLE=0)(
 input clk,input rst_n,input in_valid,input in_sop,input in_eop,
 input [1:0] in_class,
 output out_valid,output out_sop,output out_eop,output [7:0] out_data,input in_protect,output out_protect
);
 localparam DW=PROTECT_ENABLE ? 3:2;
 wire [DW*(PASSES+1)-1:0] stage_data;
 wire [3*(PASSES+1)-1:0] stage_ctrl;
 // bit1: eligible candidate; bit0: accepted/strong seed.
 assign stage_data[0+:DW]=PROTECT_ENABLE ? {in_protect,in_class!=0,in_class==2}:{1'b0,in_class!=0,in_class==2};
 assign stage_ctrl[0+:3]={in_sop,in_eop,in_valid};
 genvar pass;
 generate for(pass=0;pass<PASSES;pass=pass+1) begin:local_pass
  wire v,s,e,border;
  wire [DW-1:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
  canny_window #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.DW(DW)) window3(
   .clk(clk),.rst_n(rst_n),.in_valid(stage_ctrl[3*pass]),
   .in_sop(stage_ctrl[3*pass+2]),.in_eop(stage_ctrl[3*pass+1]),.in_data(stage_data[DW*pass+:DW]),
   .out_valid(v),.out_sop(s),.out_eop(e),.border(border),
   .p11(p11),.p12(p12),.p13(p13),.p21(p21),.p22(p22),.p23(p23),.p31(p31),.p32(p32),.p33(p33));
  localparam XW=($clog2(WIDTH)<1 ? 1 : $clog2(WIDTH));
  localparam YW=($clog2(HEIGHT)<1 ? 1 : $clog2(HEIGHT));
  reg [XW-1:0] x;
  reg [YW-1:0] y;
  wire [XW-1:0] cx=s ? 0 : x;
  wire [YW-1:0] cy=s ? 0 : y;
  wire has_left=cx!=0,has_right=cx<WIDTH-1,has_top=cy!=0,has_bottom=cy<HEIGHT-1;
  wire neighbor=(has_top && ((has_left && p11[0]) || p12[0] || (has_right && p13[0]))) ||
                (has_left && p21[0]) || (has_right && p23[0]) ||
                (has_bottom && ((has_left && p31[0]) || p32[0] || (has_right && p33[0])));
  reg [DW-1:0] data;
  reg [2:0] ctrl;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin x<=0;y<=0;data<=0;ctrl<=0;end
   else begin
    ctrl<={s,e,v};
    if(v) begin
     data[1:0]<={p22[1],p22[0] || (p22[1] && neighbor)};
     if(PROTECT_ENABLE) data[DW-1]<=p22[DW-1];
     if(e) begin x<=0;y<=0;end
     else if(cx==WIDTH-1) begin x<=0;y<=cy+1'b1;end
     else begin x<=cx+1'b1;y<=cy;end
    end
   end
  end
  assign stage_data[DW*(pass+1)+:DW]=data;
  assign stage_ctrl[3*(pass+1)+:3]=ctrl;
 end endgenerate
 assign out_valid=stage_ctrl[3*PASSES];
 assign out_sop=stage_ctrl[3*PASSES+2];
 assign out_eop=stage_ctrl[3*PASSES+1];
 assign out_data={8{stage_data[DW*PASSES]}};
assign out_protect=PROTECT_ENABLE && stage_data[DW*PASSES+DW-1] && stage_data[DW*PASSES];
endmodule
`endif
