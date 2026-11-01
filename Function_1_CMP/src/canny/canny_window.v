`ifndef TI60_CANNY_WINDOW_V
`define TI60_CANNY_WINDOW_V
// Full-size 3x3 window. One token per valid clock, synchronous block RAM.
// Output centers retain raster order and frame size. Border is flagged so
// callers can bypass/mask it. EOP drains WIDTH+1 tokens without another frame.
// Input must remain idle during drain (the frame controller enforces this).
module canny_window #(parameter WIDTH=848, HEIGHT=636, DW=8, REFLECT_BORDER=0)(
 input clk, input rst_n, input in_valid, input in_sop, input in_eop,
 input [DW-1:0] in_data,
 output reg out_valid, output reg out_sop, output reg out_eop,
 output reg border,
 output wire [DW-1:0] p11,p12,p13,p21,p22,p23,p31,p32,p33
);
 reg [DW-1:0] r11,r12,r13,r21,r22,r23,r31,r32,r33;
 reg left_edge,right_edge,top_edge,bottom_edge;
 localparam AW=$clog2(WIDTH), CW=$clog2(WIDTH*HEIGHT+WIDTH+2);
 reg [2*DW-1:0] rows[0:WIDTH-1];
 reg [2*DW-1:0] rows_q;
 reg [DW-1:0] data_q;
 reg [AW-1:0] col,col_q;
 reg [CW-1:0] tokens;
 reg [$clog2(WIDTH+2)-1:0] drain;
 reg token_q, emit_q;
 wire step = in_valid || (drain!=0);
 wire [AW-1:0] addr = in_sop && in_valid ? 0 : col;
 wire [DW-1:0] data_in = in_valid ? in_data : {DW{1'b0}};
 wire emit = (in_sop && in_valid) ? 1'b0 : tokens>=WIDTH+1;
 // Read and write different columns in a continuous stream. No RAM reset.
 always @(posedge clk) begin
   if(step) rows_q <= rows[addr];
   if(token_q) rows[col_q] <= {rows_q[DW-1:0],data_q};
 end
 reg [AW-1:0] ox;
 reg [$clog2(HEIGHT)-1:0] oy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   col<=0; col_q<=0; tokens<=0; drain<=0;
   data_q<=0; token_q<=0; emit_q<=0; ox<=0; oy<=0;
   out_valid<=0; out_sop<=0; out_eop<=0; border<=1;left_edge<=0;right_edge<=0;top_edge<=0;bottom_edge<=0;
   r11<=0;r12<=0;r13<=0;r21<=0;r22<=0;r23<=0;r31<=0;r32<=0;r33<=0;
  end else begin
   token_q<=step; emit_q<=step && emit;
   out_valid<=token_q && emit_q;
   out_sop<=token_q && emit_q && ox==0 && oy==0;
   out_eop<=token_q && emit_q && ox==WIDTH-1 && oy==HEIGHT-1;
   if(step) begin
    data_q<=data_in; col_q<=addr;
    if(addr==WIDTH-1) col<=0; else col<=addr+1'b1;
    if(in_valid && in_sop) tokens<=1;
    else tokens<=tokens+1'b1;
    if(in_valid && in_eop) drain<=WIDTH+1;
    else if(drain!=0) drain<=drain-1'b1;
   end
   if(token_q) begin
    {r11,r12,r13}<={r12,r13,rows_q[2*DW-1:DW]};
    {r21,r22,r23}<={r22,r23,rows_q[DW-1:0]};
    {r31,r32,r33}<={r32,r33,data_q};
    if(emit_q) begin
     border<=ox==0 || ox==WIDTH-1 || oy==0 || oy==HEIGHT-1;
     left_edge<=ox==0;right_edge<=ox==WIDTH-1;top_edge<=oy==0;bottom_edge<=oy==HEIGHT-1;
     if(ox==WIDTH-1) begin
      ox<=0;
      if(oy==HEIGHT-1) oy<=0;else oy<=oy+1'b1;
     end
     else ox<=ox+1'b1;
    end
   end
  end
 end
 // Mirror 101 borders, using only valid neighbors from this frame.
 assign p11=REFLECT_BORDER ? (top_edge ? (left_edge ? r33:r31):(left_edge ? r13:r11)):r11;
 assign p12=REFLECT_BORDER && top_edge ? r32:r12;
 assign p13=REFLECT_BORDER ? (top_edge ? (right_edge ? r31:r33):(right_edge ? r11:r13)):r13;
 assign p21=REFLECT_BORDER && left_edge ? r23:r21;
 assign p22=r22;
 assign p23=REFLECT_BORDER && right_edge ? r21:r23;
 assign p31=REFLECT_BORDER ? (bottom_edge ? (left_edge ? r13:r11):(left_edge ? r33:r31)):r31;
 assign p32=REFLECT_BORDER && bottom_edge ? r12:r32;
 assign p33=REFLECT_BORDER ? (bottom_edge ? (right_edge ? r11:r13):(right_edge ? r31:r33)):r33;
endmodule

`endif
