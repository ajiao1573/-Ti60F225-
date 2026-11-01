`ifndef CAMERA_FULL_VIEW_V
`define CAMERA_FULL_VIEW_V
`timescale 1ns/1ps
// Endpoint-aligned RGB downsampling. A short FIFO absorbs the top letterbox
// interval; it is not a frame buffer. Drop whole input frames while busy.
module camera_full_view #(
 parameter IN_W=1920, IN_H=1080, WIDTH=848, HEIGHT=636,
 parameter IMAGE_H=477, FIFO_BITS=14, LINE_GAP=12
)(
 input clk,rst_n,enable,in_frame,in_valid,
 input [23:0] in_rgb,
 output reg out_valid,out_sop,out_eop,
 output reg [23:0] out_rgb,
 output reg [10:0] out_x,out_y,
 output reg overflow
);
 localparam TOP=(HEIGHT-IMAGE_H)/2;
 localparam IDLE=0, RUN=1;
 localparam X_STEP=(IN_W-1)/(WIDTH-1), X_REM=(IN_W-1)%(WIDTH-1);
 localparam Y_STEP=(IN_H-1)/(IMAGE_H-1), Y_REM=(IN_H-1)%(IMAGE_H-1);
 reg state,accepting;
 reg [11:0] sx,sy,next_x,next_y,x_error,y_error;
 reg [10:0] dx,dy;
 reg [4:0] gap;
 reg [FIFO_BITS:0] wp,rp;
 reg [23:0] pixels [0:(1<<FIFO_BITS)-1];
 wire start=in_frame && in_valid && sx==0 && sy==0 && state==IDLE && enable;
 wire selected=in_valid && (accepting || start) && sx==next_x && sy==next_y;
 wire full=(wp[FIFO_BITS]!=rp[FIFO_BITS]) && (wp[FIFO_BITS-1:0]==rp[FIFO_BITS-1:0]);
 wire black=dy<TOP || dy>=TOP+IMAGE_H;
 wire emit=state==RUN && gap==0 && (black || wp!=rp);
 always @(posedge clk) begin
  if(selected && !full) pixels[wp[FIFO_BITS-1:0]]<=in_rgb;
  if(emit) out_rgb<=black ? 24'd0 : pixels[rp[FIFO_BITS-1:0]];
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;accepting<=0;sx<=0;sy<=0;next_x<=0;next_y<=0;
   x_error<=0;y_error<=0;dx<=0;dy<=0;gap<=0;wp<=0;rp<=0;
   out_valid<=0;out_sop<=0;out_eop<=0;out_x<=0;out_y<=0;overflow<=0;
  end else begin
   out_valid<=emit;out_sop<=emit && dx==0 && dy==0;
   out_eop<=emit && dx==WIDTH-1 && dy==HEIGHT-1;
   if(!in_frame) begin sx<=0;sy<=0;end
   else if(in_valid) begin
    if(sx==IN_W-1) begin sx<=0;sy<=sy+1'b1;end
    else sx<=sx+1'b1;
   end
   if(start) begin
    state<=RUN;accepting<=1;dx<=0;dy<=0;gap<=0;
    wp<=1;rp<=0;next_x<=X_STEP;x_error<=X_REM;next_y<=0;y_error<=0;
   end else if(selected) begin
    if(full) begin overflow<=1;accepting<=0;end
    else wp<=wp+1'b1;
    if(sx==IN_W-1) begin
     next_x<=0;x_error<=0;
     if(y_error+Y_REM>=IMAGE_H-1) begin
      next_y<=next_y+Y_STEP+1;y_error<=y_error+Y_REM-(IMAGE_H-1);
     end else begin next_y<=next_y+Y_STEP;y_error<=y_error+Y_REM;end
     if(sy==IN_H-1) accepting<=0;
    end else if(x_error+X_REM>=WIDTH-1) begin
     next_x<=next_x+X_STEP+1;x_error<=x_error+X_REM-(WIDTH-1);
    end else begin next_x<=next_x+X_STEP;x_error<=x_error+X_REM;end
   end
   if(gap!=0) gap<=gap-1'b1;
   if(emit) begin
    out_x<=dx;out_y<=dy;
    if(!black) rp<=rp+1'b1;
    if(dx==WIDTH-1) begin
     dx<=0;dy<=dy+1'b1;gap<=LINE_GAP;
     if(dy==HEIGHT-1) begin state<=IDLE;wp<=0;rp<=0;next_x<=0;next_y<=0;x_error<=0;y_error<=0;end
    end else dx<=dx+1'b1;
   end
  end
 end
endmodule
`endif
