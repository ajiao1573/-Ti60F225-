`ifndef TI60_CANNY_FRAME_V
`define TI60_CANNY_FRAME_V
// One accepted ROI at a time. Gray and edge streams belong to the SAME frame
// with gray during classification and edges two local-link windows later.
// DDR capture_ready remains low until both streams have committed to memory.
module canny_frame #(parameter WIDTH=848,HEIGHT=636,MEDIAN_ENABLE=1,CANNY_ENABLE=1,RUNTIME_MODES=0,SOBEL_MAX_ENABLE=0,ROBUST_NMS=0,LOW_TIGHTEN=0,BORDER_REFLECT=0,NMS_TOLERANCE=0,PROTECT_ENABLE=0,COHERENT_PROTECT=0,TEMPORAL_NMS=0)(
 input clk,input rst_n,input capture_ready,
 input in_valid,input in_sop,input in_eop,input [7:0] in_data,
 input [9:0] threshold,
 output frame_start,output busy,
 output gray_valid,output gray_sop,output gray_eop,output [7:0] gray_data,
 output edge_valid,output edge_sop,output edge_eop,output [7:0] edge_data,
 output [31:0] sweep_count,input [1:0] algorithm,output edge_protect
);
 reg occupied,accepting;
 reg [1:0] mode_latched;
 wire use_canny=CANNY_ENABLE && (!RUNTIME_MODES || mode_latched[1]);
 reg [10:0] low_latched,high_latched;
 // 5/8 = 0.625: shift/add only, with enough width at threshold=1023.
 wire [12:0] threshold_times5={3'b0,threshold}+({3'b0,threshold}<<2);
 wire [10:0] runtime_low=LOW_TIGHTEN ? threshold_times5[12:3] : {1'b0,threshold}/3;
 assign frame_start=in_valid && in_sop && !occupied && capture_ready;
 wire take=in_valid && (frame_start || accepting);
 wire [1:0] classification;wire classification_protect,hp;
 assign busy=occupied;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin occupied<=0;accepting<=0;low_latched<=10;high_latched<=20;mode_latched<=2'd3;end
  else begin
   if(frame_start) begin
    occupied<=1;accepting<=1;
    mode_latched<={CANNY_ENABLE && algorithm[1],MEDIAN_ENABLE && algorithm[0]};
    low_latched<=RUNTIME_MODES ? runtime_low : {1'b0,threshold};
    high_latched<=RUNTIME_MODES ? {1'b0,threshold} : (threshold==0 ? 11'd1 : {threshold,1'b0});
   end
   if(take && in_eop) accepting<=0;
   if(edge_valid && edge_eop) occupied<=0;
  end
 end
 canny_frontend #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.MEDIAN_ENABLE(MEDIAN_ENABLE),.CANNY_ENABLE(CANNY_ENABLE),.RUNTIME_MODES(RUNTIME_MODES),.SOBEL_MAX_ENABLE(SOBEL_MAX_ENABLE),.ROBUST_NMS(ROBUST_NMS),.BORDER_REFLECT(BORDER_REFLECT),.NMS_TOLERANCE(NMS_TOLERANCE),.PROTECT_ENABLE(PROTECT_ENABLE),.COHERENT_PROTECT(COHERENT_PROTECT),.TEMPORAL_NMS(TEMPORAL_NMS)) frontend(
  .clk(clk),.rst_n(rst_n),.in_valid(take),.in_sop(frame_start),.in_eop(in_eop && take),.in_data(in_data),
  .runtime_mode(frame_start ? algorithm : mode_latched),.low_threshold(low_latched),.high_threshold(high_latched),
  .out_valid(gray_valid),.out_sop(gray_sop),.out_eop(gray_eop),.out_gray(gray_data),.out_class(classification),.out_protect(classification_protect));
 wire hv,hs,he;wire [7:0] hd;
 generate if(CANNY_ENABLE) begin:tracking
 canny_local_link #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PASSES(2),.PROTECT_ENABLE(PROTECT_ENABLE)) local_link(
  .clk(clk),.rst_n(rst_n),.in_valid(gray_valid && use_canny),
  .in_sop(gray_sop && use_canny),.in_eop(gray_eop && use_canny),.in_class(classification),.in_protect(classification_protect),.out_protect(hp),
  .out_valid(hv),.out_sop(hs),.out_eop(he),.out_data(hd));
 assign sweep_count=0;
 end else begin:no_tracking
 assign hp=0;assign hv=0;assign hs=0;assign he=0;assign hd=0;assign sweep_count=0;
 end endgenerate
 assign edge_valid=use_canny ? hv : gray_valid;
 assign edge_sop=use_canny ? hs : gray_sop;
 assign edge_eop=use_canny ? he : gray_eop;
 assign edge_data=use_canny ? hd : {8{classification==2}};
assign edge_protect=PROTECT_ENABLE && use_canny && hp;
endmodule

`endif
