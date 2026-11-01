`ifndef POINT_GAP_FILTER_V
`define POINT_GAP_FILTER_V
// Experimental: buffer scanner points, identify the largest empty vertical
// interval; if >=60 pixels and both sides contain >=24 points, retain the
// larger component. This is a heuristic and can remove genuine defects.
module point_gap_filter(input clk,rst_n,start,in_we,input [10:0] in_addr,input [63:0] in_data,input go,input [9:0] n_in,
 output reg out_we,output reg [10:0] out_addr,output reg [63:0] out_data,output reg [9:0] n_out,output reg done,output reg busy);
reg [40:0] pts[0:471];reg [40:0] q;reg [8:0] rd; reg seen_mem[0:719]; reg seen_q, clear_active, early; reg [9:0] clear_idx; reg [3:0] st;
reg [9:0] pos,runlen,bestgap,cut,idx,left_count,right_count,keep_count;reg seen_first,filter_en,keep_left;
wire [9:0] py=q[19:10];
wire [9:0] seen_waddr=clear_active ? clear_idx : in_data[19:10];
wire seen_we=clear_active || (in_we && in_data[19:10]<720);
always @(posedge clk) begin
 if(seen_we) seen_mem[seen_waddr]<=!clear_active;
 seen_q<=seen_mem[pos];
end
always @(posedge clk) begin if(in_we && in_addr[10:1]<472) pts[in_addr[9:1]]<=in_data[40:0]; q<=pts[rd]; end
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin clear_active<=0;clear_idx<=0;early<=0;st<=0;rd<=0;pos<=0;runlen<=0;bestgap<=0;cut<=0;idx<=0;left_count<=0;right_count<=0;keep_count<=0;seen_first<=0;filter_en<=0;keep_left<=0;out_we<=0;out_addr<=0;out_data<=0;n_out<=0;done<=0;busy<=0;end
 else begin
  out_we<=0;
  if(start) begin clear_active<=1;clear_idx<=0;early<=0;done<=0;busy<=0;st<=0;end
  else begin
   if(clear_active) begin
    if(in_we) early<=1;
    if(clear_idx==719) clear_active<=0; else clear_idx<=clear_idx+1'b1;
   end
   case(st)
    0: if(go) begin pos<=0;runlen<=0;bestgap<=0;cut<=0;seen_first<=0;busy<=1;done<=0;if(early || clear_active) st<=11; else st<=1;end
    1: st<=10;
    10: begin
      if(seen_q) begin
       if(seen_first && runlen>=59 && runlen>bestgap) begin bestgap<=runlen;cut<=pos-((runlen+1)>>1);end
       seen_first<=1;runlen<=0;
      end else if(seen_first) runlen<=runlen+1'b1;
      if(pos==719) begin idx<=0;rd<=0;left_count<=0;right_count<=0;st<=2;end else begin pos<=pos+1'b1;st<=1;end
     end
    2: begin rd<=idx[8:0];st<=8;end
    8: st<=3;
    3: begin if(py<=cut) left_count<=left_count+1'b1;else right_count<=right_count+1'b1;
       if(idx==n_in-1) begin idx<=0;st<=4;end else begin idx<=idx+1'b1;st<=2;end end
    4: begin filter_en<=(bestgap>=59 && left_count>=24 && right_count>=24);keep_left<=(left_count>=right_count);idx<=0;keep_count<=0;st<=5;end
    5: begin rd<=idx[8:0];st<=9;end
    9: st<=6;
    6: begin
      if(!filter_en || ((py<=cut)==keep_left)) begin out_we<=1;out_addr<={keep_count,1'b0};out_data<={23'd0,q};keep_count<=keep_count+1'b1;end
      if(idx==n_in-1) st<=7; else begin idx<=idx+1'b1;st<=5;end
     end
    7: begin n_out<=keep_count;busy<=0;done<=1;st<=0;end
    11: begin n_out<=0;busy<=0;done<=1;st<=0;end
    default:st<=0;
   endcase
  end
 end
end
endmodule
`endif
