`ifndef PLATE_LOCATOR_V
`define PLATE_LOCATOR_V
// Full-frame Canny edge-density components. 8x4 cells, horizontal gap closing,
// then bounded run/component merging. Two map banks allow the next source frame
// while the previous map is analysed; no full grayscale frame is required.
module plate_locator #(parameter WIDTH=848,HEIGHT=477,LABELS=24,MIN_W=96,MIN_H=16)(
 input clk,rst_n,enable,rearm,input in_valid,in_sop,in_eop,input [7:0] in_edge,
 input reject,input [10:0] reject_x,reject_w,input [10:0] reject_y,reject_h,
 output reg candidate_valid,output reg [10:0] candidate_x,candidate_w,
 output reg [10:0] candidate_y,candidate_h,output reg [1:0] diagnostic,
 output reg [31:0] frame_id,output reg [31:0] candidate_frame
);
 localparam GW=(WIDTH+7)/8,GH=(HEIGHT+3)/4;
 localparam IDLE=0,INIT=1,READ_ROW=2,WAIT_ROW=3,CLEAN=4,SCAN=5,MATCH=6,COMMIT=7,PUBLISH=8;
 reg [3:0] state;
 reg [10:0] px;reg [10:0] py;
 wire [10:0] sx=in_sop ? 0:px;wire [10:0] sy=in_sop ? 0:py;
 wire cell_end=sx[2:0]==7 || sx==WIDTH-1;
 wire band_end=sy[1:0]==3 || sy==HEIGHT-1;
 wire [7:0] cell_x=sx>>3;
 reg [5:0] counts[0:GW-1];
 wire [6:0] next_count=(in_sop ? 0:{1'b0,counts[cell_x]})+(in_edge!=0);
 wire hot=next_count>=2;
 reg [GW-1:0] hot_row;
 reg [GW-1:0] maps[0:2*GH-1];reg [GW-1:0] map_q,scan_row;
 reg capture_bank,process_bank;reg [31:0] process_frame;
 reg [8:0] row;reg [7:0] col,index;
 reg [LABELS-1:0] active;
 reg [7:0] left[0:LABELS-1],right[0:LABELS-1];
 reg [8:0] top[0:LABELS-1],bottom[0:LABELS-1];
 reg [15:0] cells[0:LABELS-1];
 reg run_active;reg [1:0] gap;
 reg [7:0] run_left,run_right,run_hits;
 reg [7:0] work_left,work_right;reg [8:0] work_top,work_bottom;
 reg [15:0] work_hits;
 reg match_found,free_found;reg [7:0] match_index,free_index;
 reg end_row;
 reg [18:0] best_score;
 reg [10:0] best_x,best_w;reg [10:0] best_y,best_h;
 reg small_found;
 reg [3:0] cooldown;
 reg [10:0] bad_x,bad_w;reg [10:0] bad_y,bad_h;
 wire overlap=active[index] && row<=bottom[index]+2 &&
  {1'b0,work_left}<={1'b0,right[index]}+1 && {1'b0,left[index]}<={1'b0,work_right}+1;
 wire [10:0] box_w=({3'd0,right[index]}-{3'd0,left[index]}+1)<<3;
 wire [10:0] box_h=({2'd0,bottom[index]}-{2'd0,top[index]}+1)<<2;
 wire [15:0] box_cells=(right[index]-left[index]+1)*(bottom[index]-top[index]+1);
 wire shape_ok=box_w>=2*box_h && box_w<=8*box_h && box_w<=WIDTH-16 && box_h<=HEIGHT/2;
 wire density_ok=cells[index]>=2*(right[index]-left[index]+1) && {cells[index],3'd0}>=box_cells;
 wire suppressed=cooldown!=0 && (({3'd0,left[index]}+{3'd0,right[index]}+1)<<2)>=bad_x &&
  (({3'd0,left[index]}+{3'd0,right[index]}+1)<<2)<bad_x+bad_w &&
  (({2'd0,top[index]}+{2'd0,bottom[index]}+1)<<1)>=bad_y &&
  (({2'd0,top[index]}+{2'd0,bottom[index]}+1)<<1)<bad_y+bad_h;
 wire [18:0] score={cells[index],3'd0}-{3'd0,box_cells};
 wire [10:0] x0=left[index]==0 ? 0:({3'd0,left[index]}<<3)-8;
 wire [10:0] y0=top[index]<2 ? 0:({2'd0,top[index]}<<2)-8;
 wire [10:0] x1=(({3'd0,right[index]}+1)<<3)+8>WIDTH ? WIDTH:(({3'd0,right[index]}+1)<<3)+8;
 wire [10:0] y1=(({2'd0,bottom[index]}+1)<<2)+8>HEIGHT ? HEIGHT:(({2'd0,bottom[index]}+1)<<2)+8;
 always @(posedge clk) begin
  if(enable && in_valid && cell_end && band_end && sx==WIDTH-1)
   maps[(capture_bank ? GH:0)+(sy>>2)]<={hot,hot_row[GW-2:0]};
  if(state==READ_ROW) map_q<=maps[(process_bank ? GH:0)+row];
 end
 integer k;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;px<=0;py<=0;hot_row<=0;capture_bank<=0;process_bank<=0;
   row<=0;col<=0;index<=0;active<=0;run_active<=0;gap<=0;
   run_left<=0;run_right<=0;run_hits<=0;work_left<=0;work_right<=0;work_top<=0;work_bottom<=0;work_hits<=0;
   match_found<=0;free_found<=0;match_index<=0;free_index<=0;end_row<=0;
   best_score<=0;best_x<=0;best_y<=0;best_w<=0;best_h<=0;small_found<=0;
   candidate_valid<=0;candidate_x<=0;candidate_y<=0;candidate_w<=0;candidate_h<=0;diagnostic<=0;
   frame_id<=0;candidate_frame<=0;process_frame<=0;cooldown<=0;bad_x<=0;bad_y<=0;bad_w<=0;bad_h<=0;
   for(k=0;k<GW;k=k+1) counts[k]<=0;
  end else if(!enable || rearm) begin
   state<=IDLE;px<=0;py<=0;active<=0;candidate_valid<=0;diagnostic<=0;cooldown<=0;run_active<=0;
   for(k=0;k<GW;k=k+1) counts[k]<=0;
  end else begin
   if(reject) begin
    bad_x<=reject_x;bad_y<=reject_y;bad_w<=reject_w;bad_h<=reject_h;
    cooldown<=8;candidate_valid<=0;diagnostic<=3;best_score<=0;
   end
   if(in_valid) begin
    if(in_sop) begin
     frame_id<=frame_id+1'b1;hot_row<=0;
     for(k=0;k<GW;k=k+1) counts[k]<=0;
    end
    counts[cell_x]<=cell_end && band_end ? 0:next_count[5:0];
    if(cell_end && band_end) hot_row[cell_x]<=hot;
    if(sx==WIDTH-1) begin px<=0;py<=sy+1'b1;end else begin px<=sx+1'b1;py<=sy;end
    if(in_eop) begin
     px<=0;py<=0;if(cooldown!=0 && !reject) cooldown<=cooldown-1'b1;
     if(state==IDLE) begin
      process_bank<=capture_bank;capture_bank<=!capture_bank;process_frame<=frame_id;
      state<=INIT;index<=0;best_score<=0;small_found<=0;
     end
    end
   end
   case(state)
    INIT:begin
     active[index]<=0;
     if(index==LABELS-1) begin index<=0;row<=0;state<=READ_ROW;end else index<=index+1'b1;
    end
    READ_ROW:state<=WAIT_ROW;
    WAIT_ROW:begin scan_row<=map_q;col<=0;run_active<=0;gap<=0;index<=0;state<=CLEAN;end
    CLEAN:begin
     if(active[index] && row>bottom[index]+2) begin
      active[index]<=0;
      if(shape_ok && density_ok) begin
       if(box_w<MIN_W || box_h<MIN_H) small_found<=1;
       else if(!reject && !suppressed && score>best_score) begin
        best_score<=score;best_x<=x0;best_y<=y0;best_w<=x1-x0;best_h<=y1-y0;
       end
      end
     end
     if(index==LABELS-1) begin index<=0;state<=row>=GH ? PUBLISH:SCAN;end else index<=index+1'b1;
    end
    SCAN:begin
     if(scan_row[col]) begin
      if(!run_active) begin run_left<=col;run_hits<=1;end else run_hits<=run_hits+1'b1;
      run_active<=1;run_right<=col;gap<=0;
     end else if(run_active) gap<=gap+1'b1;
     if((run_active && !scan_row[col] && (gap==2 || col==GW-1)) || (scan_row[col] && col==GW-1)) begin
      work_left<=run_active ? run_left:col;
      work_right<=scan_row[col] ? col:run_right;
      work_top<=row;work_bottom<=row;work_hits<=run_hits+(scan_row[col] ? 1:0);
      if(!run_active) work_hits<=1;
      run_active<=0;gap<=0;index<=0;match_found<=0;free_found<=0;end_row<=col==GW-1;
      col<=col+1'b1;state<=MATCH;
     end else if(col==GW-1) begin
      row<=row==GH-1 ? GH+3:row+1'b1;index<=0;state<=row==GH-1 ? CLEAN:READ_ROW;
     end else col<=col+1'b1;
    end
    MATCH:begin
     if(overlap) begin
      active[index]<=0;
      if(!match_found) begin match_found<=1;match_index<=index;end
      if(left[index]<work_left) work_left<=left[index];
      if(right[index]>work_right) work_right<=right[index];
      if(top[index]<work_top) work_top<=top[index];
      work_hits<=work_hits+cells[index];
     end else if(!active[index] && !free_found) begin free_found<=1;free_index<=index;end
     if(index==LABELS-1) state<=COMMIT;else index<=index+1'b1;
    end
    COMMIT:begin
     if(match_found || free_found) begin
      active[match_found ? match_index:free_index]<=1;
      left[match_found ? match_index:free_index]<=work_left;
      right[match_found ? match_index:free_index]<=work_right;
      top[match_found ? match_index:free_index]<=work_top;
      bottom[match_found ? match_index:free_index]<=work_bottom;
      cells[match_found ? match_index:free_index]<=work_hits;
     end
     if(end_row) begin row<=row==GH-1 ? GH+3:row+1'b1;index<=0;state<=row==GH-1 ? CLEAN:READ_ROW;end
     else state<=SCAN;
    end
    PUBLISH:begin
     if(!reject) begin
      candidate_valid<=best_score!=0;
      candidate_x<=best_x;candidate_y<=best_y;candidate_w<=best_w;candidate_h<=best_h;
      candidate_frame<=process_frame;diagnostic<=best_score!=0 ? 1:cooldown!=0 ? 3:small_found ? 2:0;
     end
     state<=IDLE;
    end
   endcase
  end
 end
endmodule
`endif
