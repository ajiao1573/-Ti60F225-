`ifndef SHAPE_DETECT_V
`define SHAPE_DETECT_V
`include "src/shape_geometry.v"
// Four bounded scanline candidates isolate detached clutter. Shared DP/Hough
// geometry and polygon template fallback select the largest matched target.
// IDs: 0 unknown, 1 circle,
// 2 rectangle, 3 triangle. No motion gating or temporal differencing.
module shape_detect #(parameter WIDTH=848,HEIGHT=636,MIN_SIZE=20,
                      CONNECT_GAP=8,ROW_GAP=12,ENABLE_GEOMETRY=1)(
 input clk,rst_n,enable,input in_valid,in_sop,in_eop,input edge_pixel,
 output reg [1:0] shape,output reg result_valid,output busy);
 localparam IDLE=0,INIT=1,READ=2,SCORE=3,DECIDE=4,PUBLISH=5,GSTART=6,GWAIT=7;
 reg [2:0] state;
 reg accepting,previous_edge;
 reg [10:0] x;
 reg [9:0] y;
 wire [10:0] px=in_sop ? 11'd0 : x;
 wire [9:0] py=in_sop ? 10'd0 : y;
 wire first_pixel=in_sop || px==0;
 wire new_run=edge_pixel && (first_pixel || !previous_edge);
 wire capture=in_valid && (in_sop ? enable : accepting) && py<HEIGHT;
 reg [1:0] run_slot;
 reg run_owned;
 reg used[0:3],touches_border[0:3];
 reg [10:0] cxmin[0:3],cxmax[0:3];
 reg [10:0] track_left[0:3],track_right[0:3];
 reg [9:0] cymin[0:3],cymax[0:3];
 reg [21:0] ctop[0:3],cbottom[0:3];
 reg row_seen[0:3];
 reg [10:0] row_left[0:3],row_right[0:3];
 reg [9:0] row_count[0:3];
 reg [4:0] row_runs[0:3];
 reg [1:0] selected;
 reg selected_valid,allocate;
 integer k;
 always @* begin
  selected=run_slot;selected_valid=run_owned;allocate=0;
  if(new_run) begin
   selected=0;selected_valid=0;
   // Associate the two sides using the previous horizontal extent, allowing
   // small spatial/vertical gaps. Detached lines get their own candidate.
   for(k=0;k<4;k=k+1) begin
    if(!selected_valid && !in_sop && used[k] &&
       ((cymax[k]-cymin[k]<3 && {1'b0,px}+32>=cxmin[k] && px<={1'b0,cxmax[k]}+32) ||
        // Canny stair-step runs near a horizontal side need a little extra
        // horizontal reach. Only extend fresh row associations; retain the
        // original narrow window while bridging a longer occlusion.
        ({1'b0,py}<={1'b0,cymax[k]}+1 &&
         (({1'b0,px}+CONNECT_GAP+4>=track_left[k] && px<={1'b0,track_left[k]}+CONNECT_GAP+4) ||
          ({1'b0,px}+CONNECT_GAP+4>=track_right[k] && px<={1'b0,track_right[k]}+CONNECT_GAP+4))) ||
        ({1'b0,px}+CONNECT_GAP>=track_left[k] && px<={1'b0,track_left[k]}+CONNECT_GAP) ||
        ({1'b0,px}+CONNECT_GAP>=track_right[k] && px<={1'b0,track_right[k]}+CONNECT_GAP)) &&
       {1'b0,py}<={1'b0,cymax[k]}+ROW_GAP) begin
     selected=k;selected_valid=1;
    end
   end
   if(!selected_valid) begin
    for(k=0;k<4;k=k+1) begin
     if(!selected_valid && (in_sop || !used[k] ||
        ((cxmax[k]-cxmin[k]+1<MIN_SIZE || cymax[k]-cymin[k]+1<MIN_SIZE) &&
         {1'b0,py}>{1'b0,cymax[k]}+ROW_GAP))) begin
      selected=k;selected_valid=1;allocate=1;
     end
    end
   end
  end
 end
 wire [151:0] bank_outputs;
 reg [1:0] scan_slot;
 reg [9:0] scan_y;
 genvar b;
 generate for(b=0;b<4;b=b+1) begin:bank
  reg [37:0] rows[0:HEIGHT-1];
  reg [37:0] read_data;
  wire hit=edge_pixel && selected_valid && selected==b;
  wire seen_now=(!first_pixel && row_seen[b]) || hit;
  wire [10:0] left_now=hit && (first_pixel || !row_seen[b]) ? px : row_left[b];
  wire [10:0] right_now=hit ? px : row_right[b];
  wire [9:0] count_now=(first_pixel ? 10'd0 : row_count[b])+hit;
  wire [4:0] runs_now=first_pixel ? {4'd0,hit} : row_runs[b]==31 ? 5'd31 :
                      row_runs[b]+(hit && new_run);
  // Synchronous row-feature memory; no reset of the storage array.
  always @(posedge clk) begin
   if(capture && px==WIDTH-1) rows[py]<={seen_now,runs_now,count_now,right_now,left_now};
   if(state==READ) read_data<=rows[scan_y];
  end
  assign bank_outputs[b*38+:38]=read_data;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
    row_seen[b]<=0;row_left[b]<=0;row_right[b]<=0;row_count[b]<=0;row_runs[b]<=0;
    used[b]<=0;touches_border[b]<=0;cxmin[b]<=0;cxmax[b]<=0;cymin[b]<=0;cymax[b]<=0;
    ctop[b]<=0;cbottom[b]<=0;
    track_left[b]<=0;track_right[b]<=0;
   end else begin
    if(in_valid && in_sop) begin used[b]<=0;touches_border[b]<=0;end
    if(capture) begin
     row_seen[b]<=seen_now;row_left[b]<=left_now;row_right[b]<=right_now;
     row_count[b]<=count_now;row_runs[b]<=runs_now;
     if(hit) begin
      used[b]<=1;cymax[b]<=py;
      if(allocate) begin
       cxmin[b]<=px;cxmax[b]<=px;cymin[b]<=py;
       track_left[b]<=px;track_right[b]<=px;
       ctop[b]<=px*2;cbottom[b]<=px*2;
       touches_border[b]<=px==0 || px==WIDTH-1 || py==0 || py==HEIGHT-1;
      end else begin
       if(px<cxmin[b]) cxmin[b]<=px;
       if(px>cxmax[b]) cxmax[b]<=px;
       if(px==0 || px==WIDTH-1 || py==0 || py==HEIGHT-1) touches_border[b]<=1;
      end
     end
     if(px==WIDTH-1 && seen_now) begin
      if(py==cymin[b] || (hit && allocate)) ctop[b]<={11'd0,left_now}+{11'd0,right_now};
     cbottom[b]<={11'd0,left_now}+{11'd0,right_now};
      if(cymax[b]-cymin[b]<3 || runs_now>=2 || (hit && allocate)) begin
       track_left[b]<=left_now;track_right[b]<=right_now;
      end else begin
       // Keep the missing side's previous position through a short occlusion.
       if({1'b0,left_now}+CONNECT_GAP>=track_left[b] && left_now<={1'b0,track_left[b]}+CONNECT_GAP)
        track_left[b]<=left_now;
       if({1'b0,right_now}+CONNECT_GAP>=track_right[b] && right_now<={1'b0,track_right[b]}+CONNECT_GAP)
        track_right[b]<=right_now;
      end
     end
    end
   end
  end
 end endgenerate
 wire [37:0] row_read=bank_outputs[scan_slot*38+:38];
 reg found,clipped;
 reg [10:0] xmin,xmax,box_w,box_h;
 reg [9:0] ymin,ymax;
 reg [21:0] top_pair,bottom_pair;
 reg [14:0] phase;
 reg [14:0] geometry_phase;
 reg [4:0] geometry_bin;
 reg [3:0] band;
 reg [31:0] area,rect_error,circle_error,up_error,down_error;
 reg [10:0] bad_rows;
 reg top_closed,bottom_closed;
 reg [1:0] best_shape;
 reg [31:0] best_area;
 wire row_exists=row_read[37];
 wire [4:0] runs=row_read[36:32];
 wire [9:0] count=row_read[31:22];
 wire [10:0] right=row_read[21:11],left=row_read[10:0];
 wire [10:0] span=row_exists ? right-left+11'd1 : 11'd0;
 wire row_bad=!row_exists || count<2 ||
   (band>0 && band<15 && span>8 && (runs<2 || runs>8 || count>(span>>1)+(span>>2)+8));
 function [5:0] circle_width;
  input [3:0] v;
  begin case(v)
   0,15:circle_width=11;1,14:circle_width=19;2,13:circle_width=23;
   3,12:circle_width=26;4,11:circle_width=29;5,10:circle_width=30;
   6,9:circle_width=31;default:circle_width=32;
  endcase end
 endfunction
 function [31:0] distance;
  input [31:0] a,v;
  begin distance=a>v ? a-v : v-a;end
 endfunction
 wire [31:0] actual_l={15'd0,left,6'd0},actual_r={15'd0,right,6'd0};
 wire [31:0] rect_l={15'd0,xmin,6'd0},rect_r={15'd0,xmax,6'd0};
 wire [31:0] centre=({21'd0,xmin}+{21'd0,xmax})<<5;
 wire [31:0] radius=circle_width(band)*(box_w-11'd1);
 wire [5:0] q={1'b0,band,1'b1},inv_q=6'd32-q;
 wire [31:0] up_l=inv_q*top_pair+((q*xmin)<<1),up_r=inv_q*top_pair+((q*xmax)<<1);
 wire [31:0] down_l=q*bottom_pair+((inv_q*xmin)<<1),down_r=q*bottom_pair+((inv_q*xmax)<<1);
 wire [31:0] missing_penalty=box_w<<6;
 wire [31:0] re=row_exists ? distance(actual_l,rect_l)+distance(actual_r,rect_r) : missing_penalty;
 wire [31:0] ce=row_exists ? distance(actual_l,centre-radius)+distance(actual_r,centre+radius) : missing_penalty;
 wire [31:0] ue=row_exists ? distance(actual_l,up_l)+distance(actual_r,up_r) : missing_penalty;
 wire [31:0] de=row_exists ? distance(actual_l,down_l)+distance(actual_r,down_r) : missing_penalty;
 wire [31:0] bbox_area=box_w*box_h;
 // 50% more template error than v1; geometry and closure still reject noise.
 wire [31:0] error_limit=(bbox_area<<3)+(bbox_area<<2)+(box_h<<8);
 wire valid_contour=found && !clipped && box_w>=MIN_SIZE && box_h>=MIN_SIZE && bad_rows*4<=box_h;
 wire rectangle_match=top_closed && bottom_closed && area*100>=bbox_area*80 && rect_error<=error_limit;
 wire circle_match=area*100>=bbox_area*60 && area*100<=bbox_area*94 &&
                         box_w*4>=box_h*3 && box_h*4>=box_w*3 && circle_error<=error_limit;
 wire up_match=bottom_closed && up_error<=error_limit;
 wire down_match=top_closed && down_error<=error_limit;
 wire triangle_match=area*100>=bbox_area*28 && area*100<=bbox_area*72 && (up_match || down_match);
 wire [31:0] triangle_error=up_match && (!down_match || up_error<down_error) ? up_error : down_error;
 wire [1:0] template_shape=!valid_contour ? 0 :
    rectangle_match && (!circle_match || rect_error<=circle_error) &&
                      (!triangle_match || rect_error<=triangle_error) ? 2 :
    circle_match && (!triangle_match || circle_error<=triangle_error) ? 1 : triangle_match ? 3 : 0;
 wire geometry_done;wire [1:0] geometry_shape;
 generate if(ENABLE_GEOMETRY) begin:geometry
 shape_geometry u_geometry(.clk(clk),.rst_n(rst_n),.clear(state==INIT),
  .row_valid(state==SCORE && row_exists && count>=2),.row_bin(geometry_bin),
  .left(left),.right(right),.row_y({1'b0,scan_y}),.cap_supported(count*4>=span),
  .start(state==GSTART),.xmin(xmin),.xmax(xmax),.ymin({1'b0,ymin}),.ymax({1'b0,ymax}),
  .done(geometry_done),.shape(geometry_shape));
 end else begin:no_geometry
 assign geometry_done=1'b1;assign geometry_shape=2'd0;
 end endgenerate
 wire [1:0] candidate_shape=geometry_shape!=0 && found && !clipped && box_w>=MIN_SIZE && box_h>=MIN_SIZE ?
                          geometry_shape : (ENABLE_GEOMETRY && template_shape==1 ? 2'd0 : template_shape);
 assign busy=state!=IDLE;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;accepting<=0;previous_edge<=0;run_slot<=0;run_owned<=0;x<=0;y<=0;
   found<=0;clipped<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;top_pair<=0;bottom_pair<=0;
   box_w<=0;box_h<=0;scan_y<=0;scan_slot<=0;phase<=0;band<=0;
   geometry_phase<=0;geometry_bin<=0;
   area<=0;rect_error<=0;circle_error<=0;up_error<=0;down_error<=0;bad_rows<=0;
   top_closed<=0;bottom_closed<=0;best_shape<=0;best_area<=0;shape<=0;result_valid<=0;
  end else begin
   result_valid<=0;
   if(in_valid && in_sop) begin accepting<=enable;state<=IDLE;end
   if(in_valid) begin
    if(px==WIDTH-1) begin x<=0;y<=py+1'b1;end else begin x<=px+1'b1;y<=py;end
    previous_edge<=edge_pixel;
    if(new_run) begin run_slot<=selected;run_owned<=selected_valid;end
    if(in_eop) begin
     accepting<=0;
     if(in_sop ? enable : accepting) begin scan_slot<=0;best_shape<=0;best_area<=0;state<=INIT;end
     else begin shape<=0;result_valid<=1;end
    end
   end
   if(!(in_valid && in_sop)) case(state)
    INIT:begin
     found<=used[scan_slot];clipped<=touches_border[scan_slot];
     xmin<=cxmin[scan_slot];xmax<=cxmax[scan_slot];ymin<=cymin[scan_slot];ymax<=cymax[scan_slot];
     top_pair<=ctop[scan_slot];bottom_pair<=cbottom[scan_slot];
     box_w<=cxmax[scan_slot]-cxmin[scan_slot]+11'd1;
     box_h<={1'b0,cymax[scan_slot]}-{1'b0,cymin[scan_slot]}+11'd1;
     scan_y<=cymin[scan_slot];phase<=0;band<=0;area<=0;bad_rows<=0;
     geometry_phase<=0;geometry_bin<=0;
     rect_error<=0;circle_error<=0;up_error<=0;down_error<=0;top_closed<=0;bottom_closed<=0;
     state<=used[scan_slot] ? READ : DECIDE;
    end
    READ:state<=SCORE;
    SCORE:begin
     area<=area+span;bad_rows<=bad_rows+row_bad;
     // Permit a partly visible horizontal side anywhere in the end bands.
     if(band==0 && span*2>=box_w && count*4>=span) top_closed<=1;
     if(band==15 && span*2>=box_w && count*4>=span) bottom_closed<=1;
     rect_error<=rect_error+re;circle_error<=circle_error+ce;up_error<=up_error+ue;down_error<=down_error+de;
     if(scan_y==ymax) state<=ENABLE_GEOMETRY && !clipped && box_w>=MIN_SIZE && box_h>=MIN_SIZE ? GSTART : DECIDE;
     else begin
      scan_y<=scan_y+1'b1;
      if(phase+15'd16>=box_h) begin phase<=phase+15'd16-box_h;band<=band+1'b1;end
      else phase<=phase+15'd16;
      if(geometry_phase+15'd32>=box_h) begin geometry_phase<=geometry_phase+15'd32-box_h;geometry_bin<=geometry_bin+1'b1;end
      else geometry_phase<=geometry_phase+15'd32;
      state<=READ;
     end
    end
    GSTART:state<=GWAIT;
    GWAIT:if(geometry_done) state<=DECIDE;
    DECIDE:begin
     if(candidate_shape!=0 && bbox_area>best_area) begin best_shape<=candidate_shape;best_area<=bbox_area;end
     if(scan_slot==3) state<=PUBLISH;else begin scan_slot<=scan_slot+1'b1;state<=INIT;end
    end
    PUBLISH:begin shape<=best_shape;result_valid<=1;state<=IDLE;end
    default:begin end
   endcase
  end
 end
endmodule
`endif
