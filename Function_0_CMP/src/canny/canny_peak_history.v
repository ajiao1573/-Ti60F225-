`ifndef TI60_CANNY_PEAK_HISTORY_V
`define TI60_CANNY_PEAK_HISTORY_V
// One prior strong/held NMS seed bit per pixel, packed into synchronous RAM.
// Reads precede feedback writes by the NMS window latency. RAM needs no reset:
// a complete matching configuration is required before any old bit is used.
module canny_peak_history #(parameter WIDTH=960,HEIGHT=720,DW=22)(
 input clk,rst_n,invalidate,
 input in_valid,in_sop,in_eop,input [DW-1:0] in_data,
 input [12:0] configuration,
 input feedback_valid,feedback_sop,feedback_eop,feedback_seed,
 output out_valid,out_sop,out_eop,output [DW:0] out_data
);
 localparam N=WIDTH*HEIGHT,WORDS=(N+31)/32;
 localparam IW=$clog2(N+1),AW=$clog2(WORDS+1);
 reg [31:0] seeds[0:WORDS-1];
 reg [IW-1:0] read_index,write_index;
 wire [IW-1:0] ri=in_sop ? 0:read_index;
 wire [IW-1:0] wi=feedback_sop ? 0:write_index;
 reg [31:0] word_q,write_pack;
 reg [4:0] bit_q;
 reg [DW-1:0] data_q;
 reg [2:0] control_q;
 reg complete,frame_history,history_q;
 reg [12:0] complete_configuration,write_configuration;
 wire matching=complete && complete_configuration==configuration && !invalidate;
 wire [31:0] packed_seed=(feedback_sop ? 32'd0:write_pack) |
                                  (feedback_seed ? (32'd1<<wi[4:0]):32'd0);
 // Separate synchronous read and write ports; infer packed block RAM.
 always @(posedge clk) begin
  if(in_valid) word_q<=seeds[ri>>5];
  if(feedback_valid && (wi[4:0]==31 || feedback_eop))
   seeds[wi>>5]<=packed_seed;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   read_index<=0;write_index<=0;write_pack<=0;data_q<=0;bit_q<=0;control_q<=0;
   complete<=0;frame_history<=0;history_q<=0;complete_configuration<=0;write_configuration<=0;
  end else begin
   control_q<={in_sop,in_eop,in_valid};
   if(invalidate) begin complete<=0;frame_history<=0;end
   if(in_valid) begin
    data_q<=in_data;bit_q<=ri[4:0];
    history_q<=in_sop ? matching:frame_history;
    if(in_sop) frame_history<=matching;
    read_index<=in_eop ? 0:ri+1'b1;
   end
   if(feedback_valid) begin
    if(feedback_sop) write_configuration<=configuration;
    write_pack<=(wi[4:0]==31 || feedback_eop) ? 0:packed_seed;
    write_index<=feedback_eop ? 0:wi+1'b1;
    if(feedback_eop && !invalidate) begin
     complete<=1;complete_configuration<=feedback_sop ? configuration:write_configuration;
    end
   end
  end
 end
 assign out_valid=control_q[0];assign out_sop=control_q[2];assign out_eop=control_q[1];
 assign out_data={history_q && word_q[bit_q],data_q};
endmodule
`endif
