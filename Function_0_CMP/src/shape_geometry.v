`ifndef SHAPE_GEOMETRY_V
`define SHAPE_GEOMETRY_V
`include "src/shape_dp.v"
`include "src/shape_hough.v"
// Ordered contour: left top-to-bottom, supported bottom cap, right reversed,
// supported top cap. Up to 79 points; RDP and Hough share this same contour.
module shape_geometry(input clk,rst_n,input clear,row_valid,
 input [4:0] row_bin,input [10:0] left,right,row_y,input cap_supported,
 input start,input [10:0] xmin,xmax,ymin,ymax,
 output reg done,output reg [1:0] shape);
 reg [10:0] left_x[0:31],right_x[0:31],sample_y[0:31];
 reg [31:0] valid_bins;
 reg [10:0] top_l,top_r,top_y,bottom_l,bottom_r,bottom_y;
 reg top_cap,bottom_cap;
 localparam IDLE=0,LEFT=1,BOTTOM=2,RIGHT=3,TOP=4,DP_START=5,DP_WAIT=6,HOUGH_START=7,HOUGH_WAIT=8;
 reg [3:0] state;
 reg [4:0] index;
 reg [3:0] cap_index;
 reg [6:0] point_count;
 reg write_point;
 reg [10:0] write_x,write_y;
 always @* begin
  write_point=0;write_x=0;write_y=0;
  case(state)
   LEFT:if(valid_bins[index]) begin write_point=1;write_x=left_x[index];write_y=sample_y[index];end
   RIGHT:if(valid_bins[index]) begin write_point=1;write_x=right_x[index];write_y=sample_y[index];end
   BOTTOM:if(bottom_cap && bottom_r-bottom_l>=12) begin
    write_point=1;write_x=bottom_l+(((bottom_r-bottom_l)*cap_index)>>3);write_y=bottom_y;
   end
   TOP:if(top_cap && top_r-top_l>=12) begin
    write_point=1;write_x=top_r-(((top_r-top_l)*cap_index)>>3);write_y=top_y;
   end
   default:begin end
  endcase
 end
 wire dp_done,hough_done;wire [1:0] dp_polygon,hough_shape;
 wire [5:0] dp_count;wire [175:0] vertices;
 wire [10:0] epsilon=((xmax-xmin>ymax-ymin ? xmax-xmin : ymax-ymin)>>4)+2;
 wire [31:0] bbox_area=(xmax-xmin+11'd1)*(ymax-ymin+11'd1);
 shape_dp u_dp(.clk(clk),.rst_n(rst_n),.write_point(write_point),.write_index(point_count),
  .write_x(write_x),.write_y(write_y),.start(state==DP_START),.point_count(point_count),
  .epsilon(epsilon),.box_area(bbox_area),.done(dp_done),.polygon(dp_polygon),.vertex_count(dp_count),.vertices(vertices));
 shape_hough u_hough(.clk(clk),.rst_n(rst_n),.write_point(write_point),.write_index(point_count),
  .write_x(write_x),.write_y(write_y),.start(state==HOUGH_START),.point_count(point_count),
  .polygon(dp_polygon),.vertices(vertices),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.done(hough_done),.shape(hough_shape));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;done<=0;shape<=0;valid_bins<=0;index<=0;cap_index<=1;point_count<=0;
   top_l<=0;top_r<=0;top_y<=0;bottom_l<=0;bottom_r<=0;bottom_y<=0;top_cap<=0;bottom_cap<=0;
  end else begin
   done<=0;
   if(clear) begin valid_bins<=0;top_cap<=0;bottom_cap<=0;shape<=0;end
   if(row_valid) begin
    if(!valid_bins[row_bin] || row_bin==31) begin
     left_x[row_bin]<=left;right_x[row_bin]<=right;sample_y[row_bin]<=row_y;valid_bins[row_bin]<=1;
    end
    if(valid_bins==0) begin top_l<=left;top_r<=right;top_y<=row_y;top_cap<=cap_supported;end
    bottom_l<=left;bottom_r<=right;bottom_y<=row_y;bottom_cap<=cap_supported;
   end
   case(state)
    IDLE:if(start) begin index<=0;point_count<=0;state<=LEFT;end
    LEFT:begin
     if(write_point) point_count<=point_count+1'b1;
     if(index==31) begin cap_index<=1;state<=BOTTOM;end else index<=index+1'b1;
    end
    BOTTOM:begin
     if(write_point) point_count<=point_count+1'b1;
     if(!write_point || cap_index==7) begin index<=31;state<=RIGHT;end else cap_index<=cap_index+1'b1;
    end
    RIGHT:begin
     if(write_point) point_count<=point_count+1'b1;
     if(index==0) begin cap_index<=1;state<=TOP;end else index<=index-1'b1;
    end
    TOP:begin
     if(write_point) point_count<=point_count+1'b1;
     if(!write_point || cap_index==8) state<=DP_START;else cap_index<=cap_index+1'b1;
    end
    DP_START:state<=DP_WAIT;
    DP_WAIT:if(dp_done) begin
     // A resolved 5/6-corner polygon should not be re-labelled as a circle.
     if(dp_polygon==0 && dp_count<7) begin shape<=0;done<=1;state<=IDLE;end
     else state<=HOUGH_START;
    end
    HOUGH_START:state<=HOUGH_WAIT;
    HOUGH_WAIT:if(hough_done) begin shape<=hough_shape;done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`endif
