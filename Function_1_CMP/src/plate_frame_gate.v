`ifndef PLATE_FRAME_GATE_V
`define PLATE_FRAME_GATE_V
// Serialize accepted source frames through the existing DDR commit handshake.
// A registered zero-plane token accompanies each accepted source pixel.
// This retains DDR row sizes without computing unused edge algorithms.
module plate_frame_gate(input clk,rst_n,capture_ready,
 input in_valid,in_sop,in_eop,output frame_start,
 output reg out_valid,out_sop,out_eop);
 reg accepting;
 assign frame_start=in_valid && in_sop && !accepting && capture_ready;
 wire take=in_valid && (frame_start || accepting);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin accepting<=0;out_valid<=0;out_sop<=0;out_eop<=0;end
  else begin
   out_valid<=take;out_sop<=frame_start;out_eop<=take && in_eop;
   if(frame_start) accepting<=1;
   if(take && in_eop) accepting<=0;
  end
 end
endmodule
`endif
