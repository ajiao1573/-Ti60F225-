`ifndef SHAPE_STABILIZER_V
`define SHAPE_STABILIZER_V
// Hysteresis over completed recognition frames, never over pixel/display
// clocks. Confirm a new target with 3/5 votes, change class with 4/5 votes,
// and tolerate seven consecutive misses before clearing on the eighth.
module shape_stabilizer #(
 parameter ACQUIRE_VOTES=3,SWITCH_VOTES=4,LOST_FRAMES=8
)(input clk,rst_n,enable,input raw_valid,input [1:0] raw_shape,
 output reg [1:0] shape,output reg result_valid);
 localparam LOSS_W=LOST_FRAMES<2 ? 1 : $clog2(LOST_FRAMES+1);
 reg [7:0] history;
 reg [LOSS_W-1:0] misses;
 function [2:0] votes;
  input [1:0] kind,sample;input [7:0] previous;integer i;
  begin
   votes=sample==kind;
   for(i=0;i<4;i=i+1) votes=votes+(previous[i*2+:2]==kind);
  end
 endfunction
 wire [2:0] circle_votes=votes(2'd1,raw_shape,history);
 wire [2:0] rectangle_votes=votes(2'd2,raw_shape,history);
 wire [2:0] triangle_votes=votes(2'd3,raw_shape,history);
 wire [1:0] acquire=circle_votes>=ACQUIRE_VOTES ? 2'd1 :
                     rectangle_votes>=ACQUIRE_VOTES ? 2'd2 :
                     triangle_votes>=ACQUIRE_VOTES ? 2'd3 : 2'd0;
 wire [1:0] replacement=circle_votes>=SWITCH_VOTES ? 2'd1 :
                         rectangle_votes>=SWITCH_VOTES ? 2'd2 :
                         triangle_votes>=SWITCH_VOTES ? 2'd3 : 2'd0;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin history<=0;misses<=0;shape<=0;result_valid<=0;end
  else begin
   result_valid<=0;
   if(!enable) begin
    history<=0;misses<=0;shape<=0;
    if(shape!=0) result_valid<=1;
   end else if(raw_valid) begin
    history<={history[5:0],raw_shape};
    if(shape==0) begin
     misses<=0;
     if(acquire!=0) begin shape<=acquire;result_valid<=1;end
    end else if(replacement!=0 && replacement!=shape) begin
     shape<=replacement;misses<=0;result_valid<=1;
    end else if(raw_shape==shape) misses<=0;
    else if(misses>=LOST_FRAMES-1) begin
     // Discard old votes as well: ambiguous samples must earn a fresh
     // confirmation after expiry, rather than revive a stale target.
     shape<=0;history<=0;misses<=0;result_valid<=1;
    end else misses<=misses+1'b1;
   end
  end
 end
endmodule
`endif
