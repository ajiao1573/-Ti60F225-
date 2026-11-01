`timescale 1ns/1ps
module gap_fsm(input cmos_pclk,rstn_sys,ml_selftest_clear,ml_active,ml_selftest_start,scan_busy,num_busy,scan_done,num_done,filter_busy,filter_done,ml_feat_request_ready,input [9:0] scan_count,filter_count,input [4:0] scan_reason,output scan_start_o,num_start_o,filter_go_o,live_pending_o,output [2:0] state_o,output [9:0] saved_o);
 reg scan_start, num_start, filter_go, live_pending;
 reg [9:0] saved_count;
 reg [11:0] sample_id;
 reg [2:0] live_state;
 always @(posedge cmos_pclk or negedge rstn_sys) begin
  if (!rstn_sys) begin scan_start<=0; num_start<=0; filter_go<=0; live_pending<=0; saved_count<=0; sample_id<=0; live_state<=0; end
  else begin
   scan_start<=0; num_start<=0; filter_go<=0;
   if (ml_selftest_clear || !ml_active) begin live_pending<=0; live_state<=0; end
   else case (live_state)
    0: if (ml_selftest_start && !scan_busy && !num_busy && !filter_busy) begin scan_start<=1; sample_id<=sample_id+1'b1; live_state<=1; end
    1: if (scan_busy) live_state<=4;
    4: if (scan_done) begin saved_count<=scan_count; if (scan_reason!=0) begin live_pending<=1; live_state<=3; end else if (scan_count==0) begin num_start<=1; live_state<=5; end else begin filter_go<=1; live_state<=6; end end
    6: if (filter_busy) live_state<=7;
    7: if (filter_done) begin saved_count<=filter_count; num_start<=1; live_state<=5; end
    5: if (num_busy) live_state<=2;
    2: if (num_done) begin live_pending<=1; live_state<=3; end
    3: if (live_pending && ml_feat_request_ready) begin live_pending<=0; live_state<=0; end
    default: live_state<=0;
   endcase
  end
 end
 assign scan_start_o=scan_start;assign num_start_o=num_start;assign filter_go_o=filter_go;assign live_pending_o=live_pending;assign state_o=live_state;assign saved_o=saved_count;endmodule
