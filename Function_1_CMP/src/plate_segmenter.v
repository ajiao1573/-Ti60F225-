`ifndef PLATE_SEGMENTER_V
`define PLATE_SEGMENTER_V
`include "src/nz_plate_ocr.v"
`include "src/lens_roi_warp.v"
// Fixed single-line plate ROI. Analysis is sequential and uses the camera RAM
// port only after capture. The other port serves HDMI. Two banks are exchanged
// with a frame-boundary acknowledge, so displayed pixels cannot be overwritten.
module plate_segmenter #(
 parameter WIDTH=256,HEIGHT=96,X_START=512,Y_START=312,MARGIN=4,
 parameter RAW_X=96,RAW_Y=208,BIN_X=672,BIN_Y=208,
 parameter MIN_HEIGHT=HEIGHT/4,MIN_WIDTH=3,MAX_CHARS=8,
 parameter SAMPLE_STEP=1,SHOW_RAW=1,THUMB_Y=512,ENABLE_NZ_OCR=0,BLACK_INK=0,ADAPTIVE_THRESHOLD=0,
 parameter SOURCE_WIDTH=WIDTH*SAMPLE_STEP,SOURCE_HEIGHT=HEIGHT*SAMPLE_STEP,DYNAMIC_ROI=0,SINGLE_BUFFER=0,
 parameter NZ_BLACK_ONLY=0,FLAT_TILE_FALLBACK=0,LENS_CORRECTION=0
)(input clk,rst_n,enable,input in_valid,in_sop,in_eop,input [10:0] in_x,
 input [10:0] in_y,input [7:0] in_gray,adjust,
 input pixel_clk,pixel_rst_n,vsync,input [11:0] x_pos,y_pos,
 output reg [23:0] pixel,output reg ready,output reg [3:0] count,
 output reg [7:0] threshold,output reg overflow,low_contrast,
 output reg display_toggle,
 input accept_frame,snapshot_ready,output capture_hold,
 output reg recognized_locked,recognized_valid,output reg [47:0] recognized_ascii,
 output reg [2:0] reject_reason,
 input candidate_valid,input [10:0] roi_x,roi_width,input [10:0] roi_y,roi_height,
 output [5:0] cam_state,output cam_locked,cam_valid,output [47:0] cam_ascii,
 output [3:0] cam_count,output [7:0] cam_threshold,output cam_low,cam_overflow,
 output [2:0] cam_reject,output cam_result_toggle,
 output reg [10:0] captured_x,captured_width,output reg [10:0] captured_y,captured_height);
 localparam PIXELS=WIDTH*HEIGHT,INNER=(WIDTH-2*MARGIN)*(HEIGHT-2*MARGIN);
 localparam THUMBS=MAX_CHARS*640;
 localparam [6:0] PANEL_EMPTY_TOP=HEIGHT-1;
 localparam CLEAR=0,WAIT_FRAME=1,CAPTURE=2,HIST=3,THRESH=4,COL_INIT=5,
 ROW_READ=6,ROW_ACC=7,COL_READ=8,COL_ACC=9,FIND=10,
 NCHAR=11,FIT=12,DIVIDE=13,MAP_X=14,ADV_X=15,MAP_Y=16,ADV_Y=17,
 NPIX=18,NREAD=19,NWRITE=20,PUBLISH=21,WAIT_ACK=22,FIND_READ=23,
 REFINE_START=24,REFINE_READ=25,REFINE_ACC=26,REFINE_ROW=27,REFINE_END=28,REFINE_COMMIT=29,SELECT_POLARITY=30,
 ERASE_RUN=31,ROW_NEXT=32,REFINE_INIT=33,SPLIT_READ=34,SPLIT_ACC=35,
 VALLEY_LEFT_READ=36,VALLEY_LEFT_ACC=37,VALLEY_RIGHT_READ=38,VALLEY_RIGHT_ACC=39,
 SPLIT_DECIDE=40,REFINE_SAVE=41,VALLEY_LEFT_FETCH=42,VALLEY_LEFT_SCAN=43,VALLEY_RIGHT_FETCH=44,PLATE_VALIDATE=45,OCR_START=46,OCR_WAIT=47,LOCKED=48,DYN_READ=49,DYN_WRITE=50,PANEL_INIT=51,PANEL_READ=52,PANEL_ACC=53,
 WARP_START=54,WARP_WAIT=55,WARP_CLEAR=56,WARP_READ=57,WARP_WRITE=58;
 reg [5:0] state;
 reg lens_applied,lens_retry;

 reg [7:0] roi_mem[0:(SINGLE_BUFFER ? PIXELS:2*PIXELS)-1];
 reg thumb_mem[0:2*THUMBS-1];
 reg [7:0] read_gray;
 reg mask_mem[0:(SINGLE_BUFFER ? 2*PIXELS:4*PIXELS)-1];
 reg mask_q,selected_mask;
 reg [8:0] row_run_length;
 reg [7:0] row_run_start,erase_x,erase_end;
 reg [15:0] histogram[0:31];

 reg [8:0] rows[0:HEIGHT-1];
 reg [7:0] columns[0:WIDTH-1];
 reg [6:0] col_top[0:WIDTH-1],col_bottom[0:WIDTH-1];
 // Flat box bank supports simultaneous geometry reads without RAM flattening.
 reg [MAX_CHARS*32-1:0] boxes;
 reg [15:0] group_boxes[0:15],split_stack[0:7];
 reg [4:0] group_count,group_index;
 reg [3:0] stack_count;
 reg [7:0] projection_peak;
 wire [3:0] projection_cut=projection_peak>=80 ? 8 : projection_peak>=70 ? 7 :
  projection_peak>=60 ? 6 : projection_peak>=50 ? 5 : projection_peak>=40 ? 4 : projection_peak>=30 ? 3 : 2;
 reg [6:0] refined_score,work_score,first_score;
 reg [15:0] vertical_area,best_area;
 reg [7:0] valley_x,valley_value,valley_left,valley_right;
 reg [8:0] row_q;
 reg [7:0] column_q;
 reg [6:0] top_q,bottom_q;
 reg bank;
 reg request_toggle;
 reg [2:0] ack_sync;
 reg [1:0] bank_sync;
 reg [4:0] hi;
 reg [15:0] cumulative,peak_count;
 reg [4:0] lower_bin,upper_bin,peak_bin;
 reg lower_found,upper_found;
 reg [7:0] work_threshold;
 reg [7:0] panel_white,panel_left,panel_right;
 reg [15:0] row_bounds[0:HEIGHT-1];
 reg [13:0] column_bounds[0:WIDTH-1];
 reg [15:0] row_bound_q;
 reg [13:0] column_bound_q;
 reg dark,work_low,work_overflow;
 reg [3:0] work_count;
 reg second_polarity,first_dark,first_overflow;
 reg [3:0] first_count;
 reg [255:0] first_boxes;
 reg [7:0] ax;
 reg [6:0] ay;
 reg [8:0] row_sum;
 reg running;
 reg [1:0] gap;
 reg [7:0] run_start,run_end;
 reg [6:0] run_top,run_bottom;
 reg [15:0] run_area;
 reg [3:0] refined_count;
 reg vertical_active,vertical_gap;
 reg [6:0] vertical_start,vertical_end,best_top,best_bottom;
 reg [7:0] best_height;
 wire [7:0] vertical_height={1'b0,vertical_end}-{1'b0,vertical_start}+1'b1;
 wire [8:0] run_width={1'b0,run_end}-{1'b0,run_start}+1'b1;
 wire [7:0] run_height={1'b0,run_bottom}-{1'b0,run_top}+1'b1;
 wire accept_run=run_width>=MIN_WIDTH &&
  run_height>=MIN_HEIGHT && run_area>=MIN_HEIGHT*2 &&
  ((run_start>MARGIN+2 && run_end<WIDTH-MARGIN-3) || run_width>WIDTH/4);

 // Nearest-neighbour source grid floor(index*source_size/output_size).
 // Accumulators permit a slightly larger ROI without per-pixel dividers.
 reg [10:0] sample_x;
 reg [10:0] sample_y;
 reg [7:0] sample_col,x_error;
 reg [6:0] sample_row,y_error;
 reg [8:0] capture_width;
 reg [6:0] capture_height;
 reg [10:0] x_step;
 reg [10:0] y_step;
 reg [7:0] x_remainder;
 reg [6:0] y_remainder;
 wire [8:0] next_x_error={1'b0,x_error}+(DYNAMIC_ROI ? x_remainder:SOURCE_WIDTH%WIDTH);
 wire [7:0] next_y_error={1'b0,y_error}+(DYNAMIC_ROI ? y_remainder:SOURCE_HEIGHT%HEIGHT);
 wire crop=in_valid && in_x==(DYNAMIC_ROI ? captured_x:X_START)+sample_x &&
                              in_y==(DYNAMIC_ROI ? captured_y:Y_START)+sample_y;
 wire start_capture=state==WAIT_FRAME && in_valid && in_sop &&
                   (!ENABLE_NZ_OCR || accept_frame) && (SINGLE_BUFFER || ack_sync[2]==request_toggle) &&
                   (!DYNAMIC_ROI || (candidate_valid && roi_width!=0 && roi_height!=0));
 wire first_crop=DYNAMIC_ROI && start_capture && in_x==roi_x && in_y==roi_y;
 wire [8:0] incoming_width=roi_width<WIDTH ? roi_width:WIDTH;
 wire [6:0] incoming_height=roi_height<HEIGHT ? roi_height:HEIGHT;
 wire capture_last=sample_col==(DYNAMIC_ROI ? capture_width-1:WIDTH-1) &&
                   sample_row==(DYNAMIC_ROI ? capture_height-1:HEIGHT-1);
 wire [7:0] cx=sample_col;
 wire [6:0] cy=sample_row;
 // Per-32x32-cell extrema are collected from the SAME captured frame.
 // Flat banks avoid small multi-read memory elaboration bugs.
 reg [255:0] tile_min,tile_max;
 reg frame_contrast;
 wire [7:0] stats_x=DYNAMIC_ROI ? ax:cx;
 wire [6:0] stats_y=DYNAMIC_ROI ? ay:cy;
 wire [7:0] warp_gray;
 wire [7:0] stats_gray=LENS_CORRECTION && state==WARP_WRITE ? warp_gray : DYNAMIC_ROI ? read_gray:in_gray;
 wire stats_inner=stats_x>=MARGIN && stats_x<WIDTH-MARGIN && stats_y>=MARGIN && stats_y<HEIGHT-MARGIN;
 wire [4:0] capture_tile={stats_y[6:5],stats_x[7:5]};
 wire [7:0] capture_min=tile_min[capture_tile*8+:8];
 wire [7:0] capture_max=tile_max[capture_tile*8+:8];
 wire [7:0] next_min=stats_gray<capture_min ? stats_gray : capture_min;
 wire [7:0] next_max=stats_gray>capture_max ? stats_gray : capture_max;
 wire [4:0] analysis_tile={ay[6:5],ax[7:5]};
 wire [7:0] local_min=tile_min[analysis_tile*8+:8];
 wire [7:0] local_max=tile_max[analysis_tile*8+:8];
 wire local_contrast={1'b0,local_max}>={1'b0,local_min}+9'd24;
 wire [8:0] local_mid=({1'b0,local_min}+{1'b0,local_max})>>1;
 wire signed [9:0] local_adjusted=$signed({1'b0,local_mid})+$signed({2'b0,adjust})-10'sd128;
 wire [7:0] local_threshold=local_adjusted<0 ? 0 : local_adjusted>255 ? 255 : local_adjusted[7:0];
 // A uniform tile can be the INTERIOR of a thick stroke. Its own min/max
 // cannot separate ink from paper; use the same ROI's global threshold.
 wire adaptive_ink=local_contrast ? (dark ? read_gray<local_threshold : read_gray>local_threshold) :
   (FLAT_TILE_FALLBACK && !work_low && (dark ? read_gray<work_threshold : read_gray>work_threshold));
 wire raw_ink=ADAPTIVE_THRESHOLD ? adaptive_ink :
   (!work_low && (dark ? read_gray<work_threshold : read_gray>work_threshold));
 // A character must lie inside white plate material in both directions.
 // Strict per-row/per-column bounds exclude dark surround and plate rims
 // without eroding the filled character strokes or changing OCR limits.
 wire white_enclosed=!DYNAMIC_ROI ||
  (ax>row_bound_q[7:0] && ax<row_bound_q[15:8] &&
   ay>column_bound_q[6:0] && ay<column_bound_q[13:7]);
 wire ink=raw_ink && white_enclosed;
 wire panel_bright=read_gray>=panel_white;
 wire [7:0] panel_next_left=panel_bright && ax<panel_left ? ax:panel_left;
 wire [7:0] panel_next_right=panel_bright && ax>panel_right ? ax:panel_right;
 wire [6:0] panel_next_top=ay<column_bound_q[6:0] ? ay:column_bound_q[6:0];
 wire [6:0] panel_next_bottom=ay>column_bound_q[13:7] ? ay:column_bound_q[13:7];
 wire [9:0] panel_low={2'b0,lower_bin,3'b0},panel_high={2'b0,upper_bin,3'b0};
 wire [9:0] panel_white_sum=panel_low+panel_high+(panel_high<<1);
 wire inner=cx>=MARGIN && cx<WIDTH-MARGIN && cy>=MARGIN && cy<HEIGHT-MARGIN;
 wire [15:0] bank_offset=(!SINGLE_BUFFER && bank) ? PIXELS:0;
 wire [15:0] crop_addr=bank_offset+cy*WIDTH+cx;
 reg [15:0] analysis_addr;
 wire read_en=state==ROW_READ || state==COL_READ || state==NREAD || state==REFINE_READ || (DYNAMIC_ROI && state==PANEL_READ) || (LENS_CORRECTION && state==WARP_READ);
 wire capture_write=(state==CAPTURE && crop) || first_crop;
 wire normalize_read=DYNAMIC_ROI && state==DYN_READ;
 wire normalize_write=DYNAMIC_ROI && state==DYN_WRITE;
 wire [16:0] normalize_x_product=ax*capture_width;
 wire [13:0] normalize_y_product=ay*capture_height;
 wire [7:0] normalize_source_x=normalize_x_product/WIDTH;
 wire [6:0] normalize_source_y=normalize_y_product/HEIGHT;
 wire [15:0] normalize_source_addr=bank_offset+normalize_source_y*WIDTH+normalize_source_x;
 wire [15:0] normalize_dest_addr=bank_offset+ay*WIDTH+ax;
 wire warp_read_enable,warp_write_enable,warp_done,warp_success;
 wire [14:0] warp_read_address,warp_write_address;
 wire [7:0] warp_write_data;
 generate if(LENS_CORRECTION && DYNAMIC_ROI)begin:calibrated_lens
  reg [7:0] corrected_roi[0:PIXELS-1];reg [7:0] corrected_q;
  wire [14:0] corrected_write_address=warp_write_enable ? warp_write_address : ay*WIDTH+ax;
  wire [7:0] corrected_write_data=warp_write_enable ? warp_write_data : read_gray;
  always @(posedge clk)begin
   // Swap banks on copyback: retain the unmodified capture for one bounded
   // retry if rectification changes a border/stroke enough to reject OCR.
   if(warp_write_enable || state==WARP_WRITE)corrected_roi[corrected_write_address]<=corrected_write_data;
   if(state==WARP_READ)corrected_q<=corrected_roi[ay*WIDTH+ax];
  end
  assign warp_gray=corrected_q;
  lens_roi_warp correction(.clk(clk),.rst_n(rst_n && enable),.start(state==WARP_START),
   .roi_x(captured_x),.roi_y(captured_y),.roi_width(captured_width),.roi_height(captured_height),
   .read_enable(warp_read_enable),.read_address(warp_read_address),.read_data(read_gray),
   .write_enable(warp_write_enable),.write_address(warp_write_address),.write_data(warp_write_data),
   .done(warp_done),.success(warp_success));
 end else begin:uncorrected_lens
  assign warp_gray=0;assign warp_read_enable=0;assign warp_write_enable=0;
  assign warp_done=0;assign warp_success=0;assign warp_read_address=0;
  assign warp_write_address=0;assign warp_write_data=0;
 end endgenerate
 wire warp_copy=LENS_CORRECTION && state==WARP_WRITE;
 wire [15:0] camera_addr=first_crop ? ((!SINGLE_BUFFER && !bank_sync[1]) ? PIXELS:0) :
   capture_write ? crop_addr : normalize_read ? normalize_source_addr :
   normalize_write || warp_copy ? normalize_dest_addr : warp_read_enable ? bank_offset+warp_read_address : analysis_addr;
 always @(posedge clk) begin
  if(capture_write || read_en || normalize_read || normalize_write || warp_read_enable || warp_copy) begin
   if(capture_write) roi_mem[camera_addr]<=in_gray;
   else if(normalize_write) roi_mem[camera_addr]<=read_gray;
   else if(warp_copy)roi_mem[camera_addr]<=warp_gray;
   read_gray<=roi_mem[camera_addr];
  end
  if(state==COL_READ || state==FIND_READ || state==SPLIT_READ ||
     state==VALLEY_LEFT_FETCH || state==VALLEY_RIGHT_FETCH) begin
   column_q<=columns[ax];top_q<=col_top[ax];bottom_q<=col_bottom[ax];
  end
  if(state==COL_READ || state==REFINE_READ) row_q<=rows[ay];
 end
 // Synchronous one-read/one-write boundary memories. The PANEL_READ /
 // PANEL_ACC pair supplies the old column bound before its update; ROW_READ
 // aligns both bound outputs with the gray read used on the next ROW_ACC.
 generate if(DYNAMIC_ROI) begin:white_panel_storage
  always @(posedge clk) begin
   if(state==PANEL_INIT)column_bounds[ax]<={7'd0,PANEL_EMPTY_TOP};
   else if(state==PANEL_ACC && panel_bright)column_bounds[ax]<={panel_next_bottom,panel_next_top};
   if(state==PANEL_ACC && ax==WIDTH-1)row_bounds[ay]<={panel_next_right,panel_next_left};
   if(state==PANEL_READ || state==ROW_READ)column_bound_q<=column_bounds[ax];
   if(state==ROW_READ)row_bound_q<=row_bounds[ay];
  end
 end endgenerate
 reg [3:0] ni;
 reg [7:0] bx,bw;
 wire [7:0] refined_right=bx+bw-1'b1;
 wire [7:0] split_center=bx+((bw-1'b1)>>1);
 wire [7:0] split_distance=ax>split_center ? ax-split_center : split_center-ax;
 wire [7:0] valley_distance=valley_x>split_center ? valley_x-split_center : split_center-valley_x;
 wire [7:0] valley_limit=best_height/6<3 ? 3 : best_height/6;
 wire [15:0] refined_box_area=bw*best_height;
 wire solid_fragment=({best_area,2'b0}>refined_box_area*3) && ({bw,2'b0}>best_height);
 wire [6:0] trial_score=work_overflow ? refined_score : work_score;
 // Strokes fill their boxes less than the background gaps between glyphs do.
 reg [16:0] ink_total,box_total,first_ink,first_box;
 wire [33:0] first_fill=first_ink*box_total,second_fill=ink_total*first_box;
 wire fill_valid=!first_overflow && !work_overflow && first_count>=2 && work_count>=2;
 wire first_thinner=fill_valid && first_fill<second_fill && {1'b0,first_count}+5'd2>={1'b0,work_count};
 wire second_thinner=fill_valid && second_fill<first_fill && {1'b0,work_count}+5'd2>={1'b0,first_count};
 wire keep_first=first_thinner || (!second_thinner && (first_score>trial_score ||
  (first_score==trial_score && first_count>=(work_overflow ? 0 : work_count))));
 reg [6:0] by,bh;
 reg [5:0] fit_w,fit_h;
 reg wide;
 reg [12:0] numerator;
 reg [8:0] denominator;
 reg [5:0] quotient;
 reg [5:0] mi;
 reg [8:0] map_source;
 reg [9:0] map_error;
 reg [7:0] xmap[0:19];
 reg [6:0] ymap[0:31];
 reg [4:0] nx,ny;
 wire [5:0] pad_x=(20-fit_w)>>1,pad_y=(32-fit_h)>>1;
 wire inside_fit=nx>=pad_x && nx<pad_x+fit_w && ny>=pad_y && ny<pad_y+fit_h;
 wire [13:0] thumb_addr=(!SINGLE_BUFFER && bank ? THUMBS : 0)+ni*640+ny*20+nx;
 wire [16:0] mask_addr=(!SINGLE_BUFFER && bank ? 2*PIXELS : 0)+((state==NREAD ? selected_mask : second_polarity) ? PIXELS : 0)+
  (state==NREAD ? ymap[ny-pad_y]*WIDTH+xmap[nx-pad_x] : ay*WIDTH+(state==ERASE_RUN ? erase_x : ax));
 wire mask_write=state==ROW_ACC || state==ERASE_RUN;
 wire mask_read=state==COL_READ || state==REFINE_READ || state==NREAD;
 always @(posedge clk) begin
  if(mask_write || mask_read) begin
   if(mask_write) mask_mem[mask_addr]<=state==ROW_ACC && ink;
   mask_q<=mask_mem[mask_addr];
  end
 end
 generate if(!SINGLE_BUFFER) begin:thumbnail_storage
 always @(posedge clk) begin
  if(state==NPIX && !inside_fit) thumb_mem[thumb_addr]<=0;
  else if(state==NWRITE) thumb_mem[thumb_addr]<=mask_q;
 end
 end endgenerate
 always @* begin
  analysis_addr=bank_offset+ay*WIDTH+ax;
  if(state==NREAD) analysis_addr=bank_offset+ymap[ny-pad_y]*WIDTH+xmap[nx-pad_x];
 end
 reg publish_bank;
 reg [255:0] publish_boxes;
 reg [3:0] publish_count;
 reg [7:0] publish_threshold;
 reg publish_dark,publish_overflow,publish_low,publish_mask;
 reg [2:0] publish_reject;
 reg publish_candidate,publish_ocr_valid,publish_epoch;reg [47:0] publish_ascii;
 assign cam_state=state;
 assign cam_locked=state==LOCKED;
 assign cam_valid=cam_locked && publish_ocr_valid;
 assign cam_ascii=cam_valid ? publish_ascii:48'h3f3f3f3f3f3f;
 assign cam_count=publish_count;
 assign cam_threshold=publish_threshold;
 assign cam_low=publish_low;
 assign cam_overflow=publish_overflow;
 assign cam_reject=publish_reject;
 assign cam_result_toggle=request_toggle;
 reg enable_d,clear_request;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin enable_d<=0;clear_request<=0;end
  else begin enable_d<=enable;if(ENABLE_NZ_OCR && enable_d && !enable) clear_request<=!clear_request;end
 reg acknowledge;
 reg display_bank;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin ack_sync<=0;bank_sync<=0;end
  else begin ack_sync<={ack_sync[1:0],acknowledge};bank_sync<={bank_sync[0],display_bank};end
 wire [16:0] hist_total={1'b0,cumulative}+histogram[hi];
 wire [8:0] auto_threshold=({1'b0,lower_bin,3'b0}+{1'b0,upper_bin,3'b0}+9'd7)>>1;
 wire signed [9:0] adjusted=$signed({1'b0,auto_threshold})+$signed({2'b0,adjust})-10'sd128;
 // Hold new DDR captures throughout this transaction. The accepted frame is
 // allowed to finish, so the original preview and OCR share one source SOP.
 assign capture_hold=ENABLE_NZ_OCR && enable && state!=CLEAR && state!=WAIT_FRAME;
 reg work_candidate,geometry_ok;
 reg [7:0] geometry_min_height,geometry_max_height,geometry_min_bottom,geometry_max_bottom;
 reg [7:0] geometry_height;reg [8:0] geometry_width;reg [31:0] geometry_box;
 integer gi;
 always @* begin
  geometry_ok=work_count==6 && !work_overflow && !work_low && dark;
  geometry_min_height=255;geometry_max_height=0;
  geometry_min_bottom=255;geometry_max_bottom=0;geometry_height=0;geometry_box=0;
  geometry_width={1'b0,boxes[5*32+8+:8]}-{1'b0,boxes[0*32+0+:8]}+1'b1;
  for(gi=0;gi<6;gi=gi+1) begin
   geometry_box=boxes[gi*32+:32];geometry_height={1'b0,geometry_box[29:23]}-{1'b0,geometry_box[22:16]}+1'b1;
   if(geometry_height<geometry_min_height) geometry_min_height=geometry_height;
   if(geometry_height>geometry_max_height) geometry_max_height=geometry_height;
   if(geometry_box[29:23]<geometry_min_bottom) geometry_min_bottom=geometry_box[29:23];
   if(geometry_box[29:23]>geometry_max_bottom) geometry_max_bottom=geometry_box[29:23];
  end
  if(geometry_min_height*2<geometry_max_height ||
     geometry_max_bottom-geometry_min_bottom>geometry_max_height/3+2 ||
     geometry_width<geometry_max_height*2 || geometry_width>geometry_max_height*7)
   geometry_ok=0;
 end
 wire norm_valid=(state==NPIX && !inside_fit) || state==NWRITE;
 wire ocr_done,ocr_valid;wire [47:0] ocr_ascii;
 generate if(ENABLE_NZ_OCR) begin:nz_ocr
  nz_plate_ocr classifier(.clk(clk),.rst_n(rst_n && enable),
   .glyph_valid(norm_valid),.glyph_char(ni),.glyph_x(nx),.glyph_y(ny),
   .glyph_bit(state==NWRITE && mask_q),.start(state==OCR_START),
   .done(ocr_done),.valid(ocr_valid),.ascii(ocr_ascii),.busy());
 end else begin:no_nz_ocr
  assign ocr_done=1'b1;assign ocr_valid=1'b0;assign ocr_ascii=48'h3f3f3f3f3f3f;
 end endgenerate
 integer k;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=CLEAR;lens_applied<=0;lens_retry<=0;hi<=0;bank<=SINGLE_BUFFER ? 0:1;publish_reject<=0;frame_contrast<=0;work_candidate<=0;publish_candidate<=0;publish_ocr_valid<=0;publish_epoch<=0;publish_ascii<=48'h3f3f3f3f3f3f;work_count<=0;work_threshold<=128;
   work_low<=1;work_overflow<=0;dark<=1;ax<=0;ay<=0;row_sum<=0;panel_white<=0;panel_left<=WIDTH-1;panel_right<=0;
   cumulative<=0;peak_count<=0;peak_bin<=0;lower_bin<=0;upper_bin<=31;
   lower_found<=0;upper_found<=0;running<=0;gap<=0;run_area<=0;
   run_start<=0;run_end<=0;run_top<=0;run_bottom<=0;
   ni<=0;nx<=0;ny<=0;bx<=0;by<=0;bw<=0;bh<=0;fit_w<=0;fit_h<=0;
   numerator<=0;denominator<=1;quotient<=0;wide<=0;mi<=0;map_source<=0;map_error<=0;
   request_toggle<=0;publish_bank<=0;publish_boxes<=0;publish_count<=0;
   publish_threshold<=128;publish_dark<=1;publish_overflow<=0;publish_low<=1;publish_mask<=0;
   refined_count<=0;vertical_active<=0;vertical_gap<=0;
   vertical_start<=0;vertical_end<=0;best_top<=0;best_bottom<=0;best_height<=0;
   sample_x<=0;sample_y<=0;sample_col<=0;sample_row<=0;x_error<=0;y_error<=0;
   captured_x<=X_START;captured_y<=Y_START;captured_width<=SOURCE_WIDTH;captured_height<=SOURCE_HEIGHT;
   capture_width<=WIDTH;capture_height<=HEIGHT;x_step<=SOURCE_WIDTH/WIDTH;y_step<=SOURCE_HEIGHT/HEIGHT;
   x_remainder<=SOURCE_WIDTH%WIDTH;y_remainder<=SOURCE_HEIGHT%HEIGHT;
   second_polarity<=0;first_dark<=1;first_overflow<=0;first_count<=0;first_boxes<=0;
   row_run_length<=0;row_run_start<=0;erase_x<=0;erase_end<=0;selected_mask<=0;
   group_count<=0;group_index<=0;stack_count<=0;projection_peak<=0;
   refined_score<=0;work_score<=0;first_score<=0;vertical_area<=0;best_area<=0;
   ink_total<=0;box_total<=0;first_ink<=0;first_box<=0;
   valley_x<=0;valley_value<=0;valley_left<=0;valley_right<=0;
  end else if(!enable) begin state<=CLEAR;hi<=0;work_candidate<=0;end
  // A completed source frame cannot supply a missing ROI sample later.
  // Release the reservation and clear statistics before accepting another SOP.
  else if(state==CAPTURE && in_valid && in_eop && !(crop && capture_last)) begin
   state<=CLEAR;hi<=0;work_candidate<=0;
  end
  else case(state)
   CLEAR:begin
    histogram[hi]<=0;tile_min[hi*8+:8]<=255;tile_max[hi*8+:8]<=0;
    if(hi==31) begin hi<=0;state<=WAIT_FRAME;end else hi<=hi+1'b1;
   end
   WAIT_FRAME:if(start_capture) begin
    lens_applied<=0;lens_retry<=0;
    work_candidate<=0;frame_contrast<=0;
    bank<=SINGLE_BUFFER ? 0:!bank_sync[1];work_count<=0;work_overflow<=0;state<=CAPTURE;
    second_polarity<=0;group_count<=0;
    sample_x<=0;sample_y<=0;sample_col<=0;sample_row<=0;x_error<=0;y_error<=0;
    if(DYNAMIC_ROI) begin
     captured_x<=roi_x;captured_y<=roi_y;captured_width<=roi_width;captured_height<=roi_height;
     capture_width<=incoming_width;capture_height<=incoming_height;
     x_step<=roi_width<WIDTH ? 1:roi_width/WIDTH;
     y_step<=roi_height<HEIGHT ? 1:roi_height/HEIGHT;
     x_remainder<=roi_width<WIDTH ? 0:roi_width%WIDTH;
     y_remainder<=roi_height<HEIGHT ? 0:roi_height%HEIGHT;
     // When the ROI starts at the source SOP, capture its first pixel now;
     // waiting for CAPTURE would otherwise miss (0,0) permanently.
     if(first_crop) begin
      if(incoming_width==1) begin
       sample_row<=1;sample_y<=roi_height<HEIGHT ? 1:roi_height/HEIGHT;
       y_error<=roi_height<HEIGHT ? 0:roi_height%HEIGHT;
      end else begin
       sample_col<=1;sample_x<=roi_width<WIDTH ? 1:roi_width/WIDTH;
       x_error<=roi_width<WIDTH ? 0:roi_width%WIDTH;
      end
      if(incoming_width==1 && incoming_height==1) begin ax<=WIDTH-1;ay<=HEIGHT-1;state<=DYN_READ;end
     end
     if(in_eop && !(first_crop && incoming_width==1 && incoming_height==1)) begin state<=CLEAR;hi<=0;end
    end
   end
   CAPTURE:if(crop) begin
    if(cx==(DYNAMIC_ROI ? capture_width-1:WIDTH-1)) begin
     sample_x<=0;sample_col<=0;x_error<=0;
     sample_row<=sample_row+1'b1;
     sample_y<=sample_y+(DYNAMIC_ROI ? y_step:SOURCE_HEIGHT/HEIGHT)+(next_y_error>=HEIGHT);
     y_error<=next_y_error>=HEIGHT ? next_y_error-HEIGHT : next_y_error;
    end else begin
     sample_col<=sample_col+1'b1;
     sample_x<=sample_x+(DYNAMIC_ROI ? x_step:SOURCE_WIDTH/WIDTH)+(next_x_error>=WIDTH);
     x_error<=next_x_error>=WIDTH ? next_x_error-WIDTH : next_x_error;
    end
    if(!DYNAMIC_ROI && inner) begin
     histogram[in_gray[7:3]]<=histogram[in_gray[7:3]]+1'b1;
     tile_min[capture_tile*8+:8]<=next_min;tile_max[capture_tile*8+:8]<=next_max;
     if({1'b0,next_max}>={1'b0,next_min}+9'd24) frame_contrast<=1;
    end
    if(capture_last) begin
     hi<=0;cumulative<=0;peak_count<=0;peak_bin<=0;lower_found<=0;upper_found<=0;
     lower_bin<=0;upper_bin<=31;
     if(DYNAMIC_ROI) begin ax<=WIDTH-1;ay<=HEIGHT-1;state<=DYN_READ;end
     else state<=HIST;
    end
   end
   DYN_READ:state<=DYN_WRITE;
   DYN_WRITE:begin
    // Upsample in reverse address order inside the capture bank. Every
    // normalized source index is <= its destination index, so future reads
    // cannot be overwritten. Statistics belong to the normalized image.
    if(stats_inner) begin
     histogram[read_gray[7:3]]<=histogram[read_gray[7:3]]+1'b1;
     tile_min[capture_tile*8+:8]<=next_min;tile_max[capture_tile*8+:8]<=next_max;
     if({1'b0,next_max}>={1'b0,next_min}+9'd24) frame_contrast<=1;
    end
    if(ax==0 && ay==0) begin hi<=0;cumulative<=0;peak_count<=0;lower_found<=0;upper_found<=0;state<=LENS_CORRECTION ? WARP_START:HIST;end
    else begin
     if(ax==0) begin ax<=WIDTH-1;ay<=ay-1'b1;end else ax<=ax-1'b1;
     state<=DYN_READ;
    end
   end
   WARP_START:state<=WARP_WAIT;
   WARP_WAIT:if(warp_done)begin
    if(warp_success)begin lens_applied<=1;hi<=0;frame_contrast<=0;state<=WARP_CLEAR;end
    else state<=HIST;
   end
   WARP_CLEAR:begin
    histogram[hi]<=0;tile_min[hi*8+:8]<=255;tile_max[hi*8+:8]<=0;
    if(hi==31)begin hi<=0;ax<=0;ay<=0;state<=WARP_READ;end else hi<=hi+1'b1;
   end
   WARP_READ:state<=WARP_WRITE;
   WARP_WRITE:begin
    if(stats_inner)begin
     histogram[warp_gray[7:3]]<=histogram[warp_gray[7:3]]+1'b1;
     tile_min[capture_tile*8+:8]<=next_min;tile_max[capture_tile*8+:8]<=next_max;
     if({1'b0,next_max}>={1'b0,next_min}+9'd24)frame_contrast<=1;
    end
    if(ax==WIDTH-1 && ay==HEIGHT-1)begin
     hi<=0;cumulative<=0;peak_count<=0;peak_bin<=0;lower_found<=0;upper_found<=0;lower_bin<=0;upper_bin<=31;state<=HIST;
    end else begin
     if(ax==WIDTH-1)begin ax<=0;ay<=ay+1'b1;end else ax<=ax+1'b1;
     state<=WARP_READ;
    end
   end
   HIST:begin
    cumulative<=hist_total[15:0];
    if(histogram[hi]>peak_count) begin peak_count<=histogram[hi];peak_bin<=hi;end
    if(!lower_found && hist_total>=INNER/20) begin lower_bin<=hi;lower_found<=1;end
    if(!upper_found && hist_total>=INNER*19/20) begin upper_bin<=hi;upper_found<=1;end
    if(hi==31) state<=THRESH;else hi<=hi+1'b1;
   end
   THRESH:begin
    work_threshold<=adjusted<0 ? 0 : adjusted>255 ? 255 : adjusted[7:0];
    dark<=ENABLE_NZ_OCR && NZ_BLACK_ONLY ? 1'b1 : {peak_bin,3'b100}>=auto_threshold;
    work_low<=ADAPTIVE_THRESHOLD ? !frame_contrast : upper_bin<=lower_bin+1;
    ax<=0;
    if(DYNAMIC_ROI)begin panel_white<=panel_white_sum[9:2];state<=PANEL_INIT;end
    else state<=COL_INIT;
   end
   PANEL_INIT:begin
    if(ax==WIDTH-1)begin ax<=0;ay<=0;panel_left<=WIDTH-1;panel_right<=0;state<=PANEL_READ;end
    else ax<=ax+1'b1;
   end
   PANEL_READ:state<=PANEL_ACC;
   PANEL_ACC:begin
    if(ax==WIDTH-1)begin
     ax<=0;panel_left<=WIDTH-1;panel_right<=0;
     if(ay==HEIGHT-1)state<=COL_INIT;
     else begin ay<=ay+1'b1;state<=PANEL_READ;end
    end else begin ax<=ax+1'b1;panel_left<=panel_next_left;panel_right<=panel_next_right;state<=PANEL_READ;end
   end
   COL_INIT:begin
    columns[ax]<=0;col_top[ax]<=HEIGHT-1;col_bottom[ax]<=0;
    if(ax==WIDTH-1) begin ax<=MARGIN;ay<=MARGIN;row_sum<=0;row_run_length<=0;projection_peak<=0;state<=ROW_READ;end
    else ax<=ax+1'b1;
   end
   ROW_READ:state<=ROW_ACC;
   ROW_ACC:begin
    state<=ROW_NEXT;
    if(ink) begin
     if(row_run_length==0) row_run_start<=ax;
     row_run_length<=row_run_length+1'b1;
    end
    if(!ink || ax==WIDTH-MARGIN-1) begin
     row_run_length<=0;
     if(row_run_length+ink>WIDTH/4) begin
      // A stroke wider than any accepted glyph is a border/background bridge.
      erase_x<=row_run_length==0 ? ax : row_run_start;
      erase_end<=ink ? ax : ax-1'b1;state<=ERASE_RUN;
     end else row_sum<=row_sum+row_run_length+ink;
    end
   end
   ERASE_RUN:if(erase_x==erase_end) state<=ROW_NEXT;else erase_x<=erase_x+1'b1;
   ROW_NEXT:begin
    if(ax==WIDTH-MARGIN-1) begin
     rows[ay]<=row_sum;row_sum<=0;ax<=MARGIN;
     if(ay==HEIGHT-MARGIN-1) begin ay<=MARGIN;state<=COL_READ;end
     else begin ay<=ay+1'b1;state<=ROW_READ;end
    end else begin ax<=ax+1'b1;state<=ROW_READ;end
   end
   COL_READ:state<=COL_ACC;
   COL_ACC:begin
    if(mask_q && row_q<(WIDTH-2*MARGIN)*3/4) begin
     // The central height band avoids top/bottom plate edges joining glyphs.
     if(ay>=HEIGHT/6 && ay<HEIGHT*5/6) begin
      columns[ax]<=column_q+1'b1;
      if(ax>=WIDTH/4 && ax<WIDTH*3/4 && column_q+1'b1>projection_peak) projection_peak<=column_q+1'b1;
     end
     if(ay<top_q) col_top[ax]<=ay;
     col_bottom[ax]<=ay;
    end
    if(ax==WIDTH-MARGIN-1) begin
     ax<=MARGIN;
     if(ay==HEIGHT-MARGIN-1) begin running<=0;gap<=0;run_area<=0;state<=FIND_READ;end
     else begin ay<=ay+1'b1;state<=COL_READ;end
    end else begin ax<=ax+1'b1;state<=COL_READ;end
   end
   FIND_READ:state<=FIND;
   FIND:begin
    if(ax==WIDTH-MARGIN+2) begin group_index<=0;stack_count<=0;refined_count<=0;refined_score<=0;ink_total<=0;box_total<=0;state<=REFINE_START;end
    else begin
     if(column_q>=projection_cut) begin
      run_end<=ax;gap<=0;
      if(!running) begin
       running<=1;run_start<=ax;run_top<=top_q;run_bottom<=bottom_q;run_area<=column_q;
      end else begin
       if(top_q<run_top) run_top<=top_q;
       if(bottom_q>run_bottom) run_bottom<=bottom_q;
       run_area<=run_area+column_q;
      end
     end else if(running) begin
      if(gap==0) gap<=1;
      else begin
       running<=0;gap<=0;
       if(accept_run) begin
        if(group_count<16) begin
         group_boxes[group_count]<={run_end,run_start};group_count<=group_count+1'b1;
        end else work_overflow<=1;
       end
      end
     end
     ax<=ax+1'b1;state<=FIND_READ;
    end
   end
   REFINE_START:if(work_overflow) state<=SELECT_POLARITY;
    else if(stack_count!=0) begin
     bx<=split_stack[stack_count-1'b1][7:0];
     bw<=split_stack[stack_count-1'b1][15:8]-split_stack[stack_count-1'b1][7:0]+1'b1;
     stack_count<=stack_count-1'b1;state<=REFINE_INIT;
    end
    else if(group_index>=group_count) begin work_count<=refined_count;work_score<=refined_score;state<=SELECT_POLARITY;end
    else begin
     bx<=group_boxes[group_index][7:0];bw<=group_boxes[group_index][15:8]-group_boxes[group_index][7:0]+1'b1;
     group_index<=group_index+1'b1;state<=REFINE_INIT;
    end
   REFINE_INIT:begin
     ax<=bx;ay<=MARGIN;row_sum<=0;vertical_area<=0;best_area<=0;
     vertical_active<=0;vertical_gap<=0;best_height<=0;best_top<=0;best_bottom<=0;
     state<=REFINE_READ;
    end
   REFINE_READ:state<=REFINE_ACC;
   REFINE_ACC:begin
    row_sum<=row_sum+mask_q;
    if(ax==bx+bw-1) state<=REFINE_ROW;
    else begin ax<=ax+1'b1;state<=REFINE_READ;end
   end
   REFINE_ROW:begin
    if(row_sum>=2 && row_q<(WIDTH-2*MARGIN)*3/4) begin
     vertical_end<=ay;vertical_gap<=0;
     if(!vertical_active) begin vertical_active<=1;vertical_start<=ay;vertical_area<=row_sum;end
     else vertical_area<=vertical_area+row_sum;
    end else if(vertical_active) begin
     if(!vertical_gap) vertical_gap<=1;
     else begin
      vertical_active<=0;vertical_gap<=0;
      if(vertical_height>best_height) begin
       best_height<=vertical_height;best_top<=vertical_start;best_bottom<=vertical_end;best_area<=vertical_area;
      end
     end
    end
    row_sum<=0;ax<=bx;
    if(ay==HEIGHT-MARGIN-1) state<=REFINE_END;
    else begin ay<=ay+1'b1;state<=REFINE_READ;end
   end
   REFINE_END:begin
    if(vertical_active && vertical_height>best_height) begin
     best_height<=vertical_height;best_top<=vertical_start;best_bottom<=vertical_end;best_area<=vertical_area;
    end
    state<=REFINE_COMMIT;
   end
   REFINE_COMMIT:begin
    if(best_height<MIN_HEIGHT) state<=REFINE_START;
    else if({bw,2'b0}>best_height*3 && bw>=12) begin
     ax<=bx+(bw>>2);valley_value<=255;valley_x<=split_center;state<=SPLIT_READ;
    end else state<=REFINE_SAVE;
   end
   SPLIT_READ:state<=SPLIT_ACC;
   SPLIT_ACC:begin
    if(column_q<valley_value || (column_q==valley_value && split_distance<valley_distance)) begin
     valley_value<=column_q;valley_x<=ax;
    end
    if(ax==refined_right-(bw>>2)) begin state<=VALLEY_LEFT_READ;end
    else begin ax<=ax+1'b1;state<=SPLIT_READ;end
   end
   VALLEY_LEFT_READ:begin
    // First cycle selects the winning valley after the final minimum update.
    ax<=valley_x;valley_left<=valley_x;valley_right<=valley_x;state<=VALLEY_LEFT_ACC;
   end
   VALLEY_LEFT_ACC:begin
    if({valley_value,2'b0}>projection_peak) state<=REFINE_SAVE;
    else if(ax==bx) begin ax<=valley_x;state<=VALLEY_RIGHT_READ;end
    else begin ax<=ax-1'b1;state<=VALLEY_LEFT_FETCH;end
   end
   VALLEY_LEFT_FETCH:state<=VALLEY_LEFT_SCAN;
   VALLEY_LEFT_SCAN:begin
    if(column_q<=valley_value+1'b1) begin valley_left<=ax;state<=VALLEY_LEFT_ACC;end
    else begin ax<=valley_x;state<=VALLEY_RIGHT_READ;end
   end
   VALLEY_RIGHT_READ:begin
    if(ax==refined_right) state<=SPLIT_DECIDE;
    else begin ax<=ax+1'b1;state<=VALLEY_RIGHT_FETCH;end
   end
   VALLEY_RIGHT_FETCH:state<=VALLEY_RIGHT_ACC;
   VALLEY_RIGHT_ACC:begin
    if(column_q<=valley_value+1'b1) begin valley_right<=ax;state<=VALLEY_RIGHT_READ;end
    else state<=SPLIT_DECIDE;
   end
   SPLIT_DECIDE:begin
    if(valley_right-valley_left+1'b1<=valley_limit) begin
     if(stack_count<8) begin
      split_stack[stack_count]<={refined_right,(valley_x+8'd1)};stack_count<=stack_count+1'b1;
      bw<=valley_x-bx+1'b1;state<=REFINE_INIT;
     end else begin work_overflow<=1;state<=REFINE_START;end
    end else state<=REFINE_SAVE;
   end
   REFINE_SAVE:begin
    if(bw>=MIN_WIDTH && bw<=WIDTH/4 && best_area>=MIN_HEIGHT*2 && bx>MARGIN+2 && refined_right<WIDTH-MARGIN-3) begin
     if(!solid_fragment) refined_score<=refined_score+7'd4;
     ink_total<=ink_total+best_area;box_total<=box_total+refined_box_area;
     if(refined_count<MAX_CHARS) begin
      boxes[refined_count*32+:32]<={2'b0,best_bottom,best_top,refined_right,bx};refined_count<=refined_count+1'b1;
     end else work_overflow<=1;
    end
    state<=REFINE_START;
   end
   SELECT_POLARITY:begin
    // Evaluate both polarities on the SAME captured frame. A black surround
    // must not force a white plate's background to become the foreground.
    if(ENABLE_NZ_OCR && NZ_BLACK_ONLY) begin
     // Geometry already requires dark ink. Do not spend another full scan
     // choosing a white-ink interpretation that can never pass validation.
     selected_mask<=0;ni<=0;state<=PLATE_VALIDATE;
    end else if(!second_polarity) begin
     first_dark<=dark;first_count<=work_overflow ? 0 : work_count;first_overflow<=work_overflow;
     first_score<=trial_score;first_ink<=ink_total;first_box<=box_total;
     for(k=0;k<MAX_CHARS;k=k+1) first_boxes[k*32+:32]<=boxes[k*32+:32];
     second_polarity<=1;dark<=!dark;work_count<=0;work_overflow<=0;group_count<=0;ax<=0;state<=COL_INIT;
    end else begin
     selected_mask<=1;
     if(keep_first) begin
      dark<=first_dark;work_count<=first_count;work_overflow<=first_overflow;selected_mask<=0;
      for(k=0;k<MAX_CHARS;k=k+1) boxes[k*32+:32]<=first_boxes[k*32+:32];
     end
     ni<=0;state<=ENABLE_NZ_OCR ? PLATE_VALIDATE : NCHAR;
    end
   end
   PLATE_VALIDATE:begin work_candidate<=geometry_ok;state<=NCHAR;end
   NCHAR:if(ni>=work_count || work_overflow) state<=ENABLE_NZ_OCR && work_candidate ? OCR_START : PUBLISH;
    else begin bx<=boxes[ni*32+0+:8];by<=boxes[ni*32+16+:7];
     bw<=boxes[ni*32+8+:8]-boxes[ni*32+0+:8]+1'b1;bh<=boxes[ni*32+23+:7]-boxes[ni*32+16+:7]+1'b1;state<=FIT;end
   FIT:begin
    quotient<=0;wide<=({bw,5'b0}>bh*20);
    if({bw,5'b0}>bh*20) begin fit_w<=20;numerator<=bh*20;denominator<=bw;end
    else begin fit_h<=32;numerator<={bw,5'b0};denominator<=bh;end
    state<=DIVIDE;
   end
   DIVIDE:if(numerator>=denominator) begin numerator<=numerator-denominator;quotient<=quotient+1'b1;end
    else begin
     if(wide) fit_h<=quotient==0 ? 1 : quotient;else fit_w<=quotient==0 ? 1 : quotient;
     mi<=0;map_source<=bx;map_error<=0;state<=MAP_X;
    end
   MAP_X:begin xmap[mi]<=map_source[7:0];map_error<=map_error+bw;state<=ADV_X;end
   ADV_X:if(map_error>=fit_w) begin map_error<=map_error-fit_w;map_source<=map_source+1'b1;end
    else if(mi==fit_w-1) begin mi<=0;map_source<=by;map_error<=0;state<=MAP_Y;end
    else begin mi<=mi+1'b1;state<=MAP_X;end
   MAP_Y:begin ymap[mi]<=map_source[6:0];map_error<=map_error+bh;state<=ADV_Y;end
   ADV_Y:if(map_error>=fit_h) begin map_error<=map_error-fit_h;map_source<=map_source+1'b1;end
    else if(mi==fit_h-1) begin nx<=0;ny<=0;state<=NPIX;end
    else begin mi<=mi+1'b1;state<=MAP_Y;end
   NPIX:if(inside_fit) state<=NREAD;
    else if(nx==19) begin nx<=0;if(ny==31) begin ni<=ni+1'b1;state<=NCHAR;end else ny<=ny+1'b1;end
    else nx<=nx+1'b1;
   NREAD:state<=NWRITE;
   NWRITE:begin
    state<=NPIX;
    if(nx==19) begin nx<=0;if(ny==31) begin ni<=ni+1'b1;state<=NCHAR;end else ny<=ny+1'b1;end
    else nx<=nx+1'b1;
   end
   OCR_START:state<=OCR_WAIT;
   OCR_WAIT:if(ocr_done) state<=PUBLISH;
   LOCKED:state<=LOCKED;
   PUBLISH:if(ENABLE_NZ_OCR && LENS_CORRECTION && lens_applied && !lens_retry && !(work_candidate && ocr_valid))begin
    // Do not weaken confidence gates to accept a resampling regression.
    // Restore the SAME frame once and run the original segmentation path.
    lens_retry<=1;hi<=0;frame_contrast<=0;work_candidate<=0;work_count<=0;work_overflow<=0;
    second_polarity<=0;group_count<=0;state<=WARP_CLEAR;
   end else if(!ENABLE_NZ_OCR || !work_candidate || snapshot_ready) begin
    // Report the first failed stage. An OCR rejection resumes acquisition.
    publish_reject<=work_low ? 3'd1 : work_overflow ? 3'd2 : work_count!=6 ? 3'd3 :
                    !work_candidate ? 3'd4 : !ocr_valid ? 3'd5 : 3'd0;
    publish_epoch<=clear_request;publish_candidate<=work_candidate && ocr_valid;publish_ocr_valid<=work_candidate && ocr_valid;publish_ascii<=ocr_ascii;
    publish_bank<=bank;publish_count<=work_overflow ? 0 : work_count;
    publish_threshold<=work_threshold;publish_dark<=dark;publish_low<=work_low;publish_overflow<=work_overflow;
    publish_mask<=selected_mask;
    for(k=0;k<MAX_CHARS;k=k+1) publish_boxes[k*32+:32]<=boxes[k*32+:32];
    request_toggle<=!request_toggle;state<=WAIT_ACK;
   end
   WAIT_ACK:if(SINGLE_BUFFER || ack_sync[2]==request_toggle) begin hi<=0;state<=ENABLE_NZ_OCR && work_candidate && ocr_valid ? LOCKED : CLEAR;end
   default:state<=CLEAR;
  endcase
 end

 // Result bus is held while the synchronized request is acknowledged.
 reg [2:0] req_sync;
 reg req_seen,vsync_d;
 reg [2:0] clear_sync;reg clear_seen;
 reg [255:0] display_boxes;
 reg display_dark,display_mask;
 always @(posedge pixel_clk or negedge pixel_rst_n) begin
  if(!pixel_rst_n) begin
   req_sync<=0;req_seen<=0;acknowledge<=0;clear_sync<=0;clear_seen<=0;
   recognized_locked<=0;recognized_valid<=0;recognized_ascii<=48'h3f3f3f3f3f3f;reject_reason<=0;vsync_d<=0;display_bank<=0;
   display_boxes<=0;display_dark<=1;display_mask<=0;ready<=0;count<=0;threshold<=128;
   overflow<=0;low_contrast<=1;display_toggle<=0;
  end else begin
   req_sync<={req_sync[1:0],request_toggle};clear_sync<={clear_sync[1:0],clear_request};vsync_d<=vsync;
   if(vsync_d && !vsync && req_sync[2]!=req_seen) begin
    req_seen<=req_sync[2];acknowledge<=req_sync[2];display_bank<=publish_bank;
    if(!ENABLE_NZ_OCR || publish_epoch==clear_sync[2]) begin
    display_boxes<=publish_boxes;count<=publish_count;reject_reason<=publish_reject;
    recognized_locked<=publish_candidate;recognized_valid<=publish_ocr_valid;recognized_ascii<=publish_ascii;threshold<=publish_threshold;
    display_dark<=publish_dark;overflow<=publish_overflow;low_contrast<=publish_low;
    display_mask<=publish_mask;
    ready<=1;display_toggle<=!display_toggle;
    end
   end
   if(ENABLE_NZ_OCR && vsync_d && !vsync && clear_sync[2]!=clear_seen) begin
    clear_seen<=clear_sync[2];
    if(!(req_sync[2]!=req_seen && publish_epoch==clear_sync[2])) begin
     ready<=0;reject_reason<=0;recognized_locked<=0;recognized_valid<=0;recognized_ascii<=48'h3f3f3f3f3f3f;
    end
   end
  end
 end
 wire raw_area=!SINGLE_BUFFER && SHOW_RAW && x_pos>=RAW_X && x_pos<RAW_X+2*WIDTH && y_pos>=RAW_Y && y_pos<RAW_Y+2*HEIGHT;
 wire bin_area=!SINGLE_BUFFER && x_pos>=BIN_X && x_pos<BIN_X+2*WIDTH && y_pos>=BIN_Y && y_pos<BIN_Y+2*HEIGHT;
 wire thumb_area=!SINGLE_BUFFER && x_pos>=264 && x_pos<264+8*96 && y_pos>=THUMB_Y && y_pos<THUMB_Y+128;
 wire [9:0] tx=x_pos-264;
 wire [3:0] slot=tx/96;
 wire [6:0] within_slot=tx%96;
 wire thumb_visible=thumb_area && slot<count && within_slot<80;
 wire [7:0] rx=(x_pos-(bin_area ? BIN_X : RAW_X))>>1;
 wire [6:0] ry=(y_pos-(bin_area ? BIN_Y : RAW_Y))>>1;
 wire [15:0] display_roi_addr=(!SINGLE_BUFFER && display_bank ? PIXELS : 0)+((raw_area||bin_area) ? ry*WIDTH+rx : 0);
 wire [13:0] display_thumb_addr=(!SINGLE_BUFFER && display_bank ? THUMBS : 0)+(thumb_visible ? slot*640+((y_pos-THUMB_Y)>>2)*20+(within_slot>>2) : 0);
 wire [7:0] roi_pixel;
 wire thumb_pixel;
 wire mask_pixel;
 wire [16:0] display_mask_addr=(!SINGLE_BUFFER && display_bank ? 2*PIXELS : 0)+(display_mask ? PIXELS : 0)+(bin_area ? ry*WIDTH+rx : 0);
 // lcd_driver publishes the next pixel on the rising edge. RAM reads on the
 // falling edge settle before its following RGB register samples the data.
 generate if(!SINGLE_BUFFER) begin:roi_display_ports
  reg [7:0] roi_q;reg thumb_q,mask_q;
  always @(negedge pixel_clk) begin
   roi_q<=roi_mem[display_roi_addr];thumb_q<=thumb_mem[display_thumb_addr];
   mask_q<=mask_mem[display_mask_addr];
  end
  assign roi_pixel=roi_q;assign thumb_pixel=thumb_q;assign mask_pixel=mask_q;
 end else begin:no_roi_display_ports
  assign roi_pixel=0;assign thumb_pixel=0;assign mask_pixel=0;
 end endgenerate
 // Internal masks stay ink=1 for segmentation/OCR. Presentation polarity is
 // independent: NZ plates use black glyphs on a white panel.
 wire display_ink=!low_contrast && rx>=MARGIN && rx<WIDTH-MARGIN &&
                  ry>=MARGIN && ry<HEIGHT-MARGIN && mask_pixel;
 wire binary_white=BLACK_INK ? !display_ink : display_ink;
 wire thumb_white=BLACK_INK ? !thumb_pixel : thumb_pixel;
 reg on_box;reg [31:0] box;
 integer b;
 always @* begin
  on_box=0;box=0;
  for(b=0;b<MAX_CHARS;b=b+1) begin
   box=display_boxes[b*32+:32];
   if(b<count && rx>=box[7:0] && rx<=box[15:8] && ry>=box[22:16] && ry<=box[29:23] &&
    (rx==box[7:0] || rx==box[15:8] || ry==box[22:16] || ry==box[29:23])) on_box=1;
  end
  pixel=0;
  if(!SINGLE_BUFFER && ready) begin
   if(raw_area) pixel=on_box ? 24'h00ff00 : {3{roi_pixel}};
   else if(bin_area) pixel=on_box ? 24'h00ff00 : {24{binary_white}};
   else if(thumb_visible) pixel={24{thumb_white}};
  end
 end
endmodule
`endif
