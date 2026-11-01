`ifndef AUTOPLATE_CORE_V
`define AUTOPLATE_CORE_V
`include "src/canny/canny_rtl.vh"
`include "src/plate_locator.v"
`include "src/plate_segmenter.v"
// Frame N proposes a box. A subsequent accepted frame locks that box, captures
// its GRAYSCALE pixels, then performs filled-glyph segmentation and NZ OCR.
// The preview plane stores original common-front-end gray, never Canny edges.
module autoplate_core #(parameter WIDTH=848,HEIGHT=477,TEMPORAL_HISTORY=(WIDTH*HEIGHT<=848*477),LENS_CORRECTION=0)(
 input clk,rst_n,input run_enable,rearm,input [9:0] edge_threshold,input [7:0] char_adjust,
 input in_valid,in_sop,in_eop,input [7:0] in_gray,input [10:0] in_x,input [10:0] in_y,
 input capture_ready,snapshot_ready,
 input pixel_clk,pixel_rst_n,pixel_vsync,
 output frame_start,frame_done,busy,source_take,
 output reg preview_valid,output reg [7:0] preview_data,
 output capture_hold,output [7:0] app_state,output [5:0] segment_state,
 output recognized_locked,recognized_valid,output [47:0] recognized_ascii,
 output [3:0] characters,output [7:0] binary_threshold,output low_contrast,overflow,
 output [2:0] reject_reason,output [1:0] locator_diagnostic,
 output box_valid,output [10:0] box_x,box_w,output [10:0] box_y,box_h,
 output [31:0] box_frame,output reg [31:0] captured_frame_id,
 output edge_frame_toggle
);
 wire ev,es,ee;wire [7:0] ed;
 canny_frame #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),
  .ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),
  .PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(TEMPORAL_HISTORY)) edges(
  .clk(clk),.rst_n(rst_n && !rearm),.capture_ready(capture_ready && !rearm),
  .in_valid(in_valid && !rearm),.in_sop(in_sop),.in_eop(in_eop),.in_data(in_gray),
  .threshold(edge_threshold),.algorithm(2'd3),.frame_start(frame_start),.busy(busy),
  .gray_valid(),.gray_sop(),.gray_eop(),.gray_data(),
  .edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed),.edge_protect(),.sweep_count());
 assign frame_done=ev && ee;
 wire located;
 reg accepting;reg [31:0] source_frame_id;
 assign source_take=in_valid && (frame_start || accepting);
 always @(posedge clk or negedge rst_n)
 if(!rst_n) begin accepting<=0;preview_valid<=0;preview_data<=0;source_frame_id<=0;captured_frame_id<=0;end
 else begin
  preview_valid<=source_take;preview_data<=in_gray;
  if(frame_start) begin
   accepting<=1;source_frame_id<=source_frame_id+1'b1;
   if(run_enable && segment_state==1 && located) captured_frame_id<=source_frame_id+1'b1;
  end
  if(source_take && in_eop) accepting<=0;
  if(rearm) begin accepting<=0;preview_valid<=0;end
 end
 reg edge_toggle;
 always @(posedge clk or negedge rst_n)
 if(!rst_n) edge_toggle<=0;else if(frame_done) edge_toggle<=!edge_toggle;
 assign edge_frame_toggle=edge_toggle;
 wire [10:0] lx,lw,cx,cw;wire [10:0] ly,lh,cy,ch;
 wire [31:0] locator_frame;
 wire result_toggle;reg result_previous;
 always @(posedge clk or negedge rst_n)
 if(!rst_n) result_previous<=0;else result_previous<=result_toggle;
 wire reject_event=(result_toggle!=result_previous) && reject_reason!=0;
 plate_locator #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) locator(
  .clk(clk),.rst_n(rst_n),.enable(1'b1),.rearm(rearm),
  .in_valid(ev),.in_sop(es),.in_eop(ee),.in_edge(ed),
  .reject(reject_event),.reject_x(cx),.reject_y(cy),.reject_w(cw),.reject_h(ch),
  .candidate_valid(located),.candidate_x(lx),.candidate_y(ly),.candidate_w(lw),.candidate_h(lh),
  .diagnostic(locator_diagnostic),.frame_id(),.candidate_frame(locator_frame));
 plate_segmenter #(.WIDTH(256),.HEIGHT(96),.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.ENABLE_NZ_OCR(1),
  .BLACK_INK(1),.ADAPTIVE_THRESHOLD(1),.NZ_BLACK_ONLY(1),.FLAT_TILE_FALLBACK(1),.LENS_CORRECTION(LENS_CORRECTION),.MIN_HEIGHT(12),.SHOW_RAW(0)) segmenter(
  .clk(clk),.rst_n(rst_n),.enable(run_enable && !rearm),
  .in_valid(source_take),.in_sop(in_sop),.in_eop(in_eop),.in_x(in_x),.in_y(in_y),.in_gray(in_gray),.adjust(char_adjust),
  .candidate_valid(located),.roi_x(lx),.roi_y(ly),.roi_width(lw),.roi_height(lh),
  .accept_frame(frame_start),.snapshot_ready(snapshot_ready),.capture_hold(capture_hold),
  .captured_x(cx),.captured_y(cy),.captured_width(cw),.captured_height(ch),
  .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.vsync(pixel_vsync),.x_pos(12'd0),.y_pos(12'd0),
  .pixel(),.ready(),.count(),.threshold(),.overflow(),.low_contrast(),.display_toggle(),
  .recognized_locked(),.recognized_valid(),.recognized_ascii(),.reject_reason(),
  .cam_state(segment_state),.cam_locked(recognized_locked),.cam_valid(recognized_valid),
  .cam_ascii(recognized_ascii),.cam_count(characters),.cam_threshold(binary_threshold),
  .cam_low(low_contrast),.cam_overflow(overflow),.cam_reject(reject_reason),.cam_result_toggle(result_toggle));
 assign box_valid=run_enable && (capture_hold ? cw!=0 && ch!=0:located);
 assign box_x=capture_hold ? cx:lx;assign box_y=capture_hold ? cy:ly;
 assign box_w=capture_hold ? cw:lw;assign box_h=capture_hold ? ch:lh;
 assign box_frame=capture_hold ? captured_frame_id:locator_frame;
 assign app_state=!run_enable ? 8'd6:recognized_locked ? 8'd5:
  segment_state==2 ? 8'd3:capture_hold ? 8'd4:located ? 8'd2:8'd1;
endmodule
`endif
