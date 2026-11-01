`ifndef LENS_ROI_WARP_V
`define LENS_ROI_WARP_V
`include "src/lens_grid_lookup.v"
// Rectify a captured 256x96 grayscale ROI before its histogram/segmentation.
// Capture and locator stay in native distorted coordinates. A separate output
// bank prevents a warp write from destroying a source pixel still to be read.
module lens_roi_warp #(parameter MAP_FILE="src/calibration/lens_map.hex")(
 input clk,rst_n,start,input [10:0] roi_x,roi_y,roi_width,roi_height,
 output read_enable,output [14:0] read_address,input [7:0] read_data,
 output write_enable,output [14:0] write_address,output [7:0] write_data,
 output reg done,success);
 localparam IDLE=0,BOX_START=1,BOX_WAIT=2,DIV_INIT=3,DIVIDE=4,
 MAP_START=5,MAP_WAIT=6,COORD=7,BOUNDS=8,R0=9,R1=10,R2=11,R3=12,R4=13,
 BLEND_X=14,BLEND_Y=15,WRITE=16,FINISH=17;
 reg [4:0] state;
 reg [10:0] rx,ry,rw,rh;
 reg [3:0] point_index;
 reg signed [20:0] min_x,max_x,min_y,max_y;
 reg signed [20:0] target_x,target_y;
 reg [7:0] ox;reg [6:0] oy;
 reg [20:0] x_step,y_step;
 reg [7:0] x_remainder,x_error;reg [6:0] y_remainder,y_error;
 reg [24:0] reciprocal_x,reciprocal_y;
 reg [1:0] division_index;
 reg [31:0] dividend,quotient;
 reg [32:0] remainder;
 reg [15:0] denominator;
 reg [5:0] division_bit;
 wire [32:0] shifted={remainder[31:0],dividend[31]};
 wire subtract=shifted>={17'd0,denominator};
 wire [32:0] next_remainder=subtract ? shifted-denominator : shifted;
 wire [31:0] next_quotient={quotient[30:0],subtract};
 wire [21:0] span_x=$signed(max_x)-$signed(min_x),span_y=$signed(max_y)-$signed(min_y);
 wire [8:0] next_x_error={1'b0,x_error}+{1'b0,x_remainder};
 wire [7:0] next_y_error={1'b0,y_error}+{1'b0,y_remainder};
 reg signed [47:0] product_x,product_y;
 wire signed [31:0] normalized_x=product_x>>>16,normalized_y=product_y>>>16;
 reg [7:0] ix,fx,fy;reg [6:0] iy;
 reg [7:0] p0,p1,p2,p3,pixel;
 reg [15:0] upper,lower;
 wire [23:0] blended=upper*(9'd256-{1'b0,fy})+lower*{1'b0,fy};
 wire [24:0] rounded={1'b0,blended}+25'd32768;
 wire [7:0] ix1=ix==255 ? ix:ix+1'b1;
 wire [6:0] iy1=iy==95 ? iy:iy+1'b1;
 assign read_enable=state>=R0 && state<=R3;
 assign read_address=state==R1 ? {iy,ix1} : state==R2 ? {iy1,ix} : state==R3 ? {iy1,ix1} : {iy,ix};
 assign write_enable=state==WRITE;
 assign write_address={oy,ox};
 assign write_data=pixel;
 wire map_done,map_valid;
 wire signed [20:0] mapped_x,mapped_y;
 wire [10:0] box_x=point_index==0 || point_index==3 || point_index==5 ? rx :
   point_index==1 || point_index==6 ? rx+(rw>>1) : rx+rw;
 wire [10:0] box_y=point_index<=2 ? ry : point_index<=4 ? ry+(rh>>1) : ry+rh;
 wire signed [20:0] lookup_x=state==BOX_START ? $signed({2'b0,box_x,8'b0}) : target_x;
 wire signed [20:0] lookup_y=state==BOX_START ? $signed({2'b0,box_y,8'b0}) : target_y;
 lens_grid_lookup #(.MAP_FILE(MAP_FILE)) lookup(.clk(clk),.rst_n(rst_n),
  .start(state==BOX_START || state==MAP_START),.inverse(state==BOX_START),.x(lookup_x),.y(lookup_y),
  .done(map_done),.valid(map_valid),.mapped_x(mapped_x),.mapped_y(mapped_y));
 wire signed [21:0] relative_x=$signed(mapped_x)-$signed({2'b0,rx,8'b0});
 wire signed [21:0] relative_y=$signed(mapped_y)-$signed({2'b0,ry,8'b0});
 always @(posedge clk or negedge rst_n)
 if(!rst_n)begin state<=IDLE;done<=0;success<=0;ox<=0;oy<=0;end
 else begin
  done<=0;
  case(state)
   IDLE:if(start)begin
    rx<=roi_x;ry<=roi_y;rw<=roi_width;rh<=roi_height;point_index<=0;success<=0;
    min_x<=21'sh0fffff;min_y<=21'sh0fffff;max_x<=-21'sh100000;max_y<=-21'sh100000;
    if(roi_width<2 || roi_height<2 || {1'b0,roi_x}+{1'b0,roi_width}>1920 || {1'b0,roi_y}+{1'b0,roi_height}>1080)state<=FINISH;
    else state<=BOX_START;
   end
   BOX_START:state<=BOX_WAIT;
   BOX_WAIT:if(map_done)begin
    if(!map_valid)state<=FINISH;
    else begin
     if(mapped_x<min_x)min_x<=mapped_x;if(mapped_x>max_x)max_x<=mapped_x;
     if(mapped_y<min_y)min_y<=mapped_y;if(mapped_y>max_y)max_y<=mapped_y;
     if(point_index==7)begin division_index<=0;state<=DIV_INIT;end
     else begin point_index<=point_index+1'b1;state<=BOX_START;end
    end
   end
   DIV_INIT:begin
    dividend<=division_index==0 ? 32'd16777216 : division_index==1 ? 32'd6291456 : {10'd0,span_y};
    denominator<=division_index==0 ? {5'd0,rw} : division_index==1 ? {5'd0,rh} : 16'd96;
    remainder<=0;quotient<=0;division_bit<=31;state<=DIVIDE;
   end
   DIVIDE:begin
    remainder<=next_remainder;dividend<=dividend<<1;quotient<=next_quotient;
    if(division_bit==0)begin
     if(division_index==0)reciprocal_x<=next_quotient[24:0];
     if(division_index==1)reciprocal_y<=next_quotient[24:0];
     if(division_index==2)begin
      y_step<=next_quotient[20:0];y_remainder<=next_remainder[6:0];
      x_step<=span_x[21:8];x_remainder<=span_x[7:0];x_error<=0;y_error<=0;
      target_x<=min_x;target_y<=min_y;ox<=0;oy<=0;state<=MAP_START;
     end else begin division_index<=division_index+1'b1;state<=DIV_INIT;end
    end else division_bit<=division_bit-1'b1;
   end
   MAP_START:state<=MAP_WAIT;
   MAP_WAIT:if(map_done)begin
    if(!map_valid)begin pixel<=255;state<=WRITE;end else state<=COORD;
   end
   COORD:begin
    product_x<=relative_x*$signed({1'b0,reciprocal_x});
    product_y<=relative_y*$signed({1'b0,reciprocal_y});state<=BOUNDS;
   end
   BOUNDS:begin
    if(normalized_x<0 || normalized_x>32'sd65280 || normalized_y<0 || normalized_y>32'sd24320)begin pixel<=255;state<=WRITE;end
    else begin ix<=normalized_x[15:8];iy<=normalized_y[14:8];fx<=normalized_x[7:0];fy<=normalized_y[7:0];state<=R0;end
   end
   R0:state<=R1;
   R1:begin p0<=read_data;state<=R2;end
   R2:begin p1<=read_data;state<=R3;end
   R3:begin p2<=read_data;state<=R4;end
   R4:begin p3<=read_data;state<=BLEND_X;end
   BLEND_X:begin
    upper<=p0*(9'd256-{1'b0,fx})+p1*{1'b0,fx};
    lower<=p2*(9'd256-{1'b0,fx})+p3*{1'b0,fx};state<=BLEND_Y;
   end
   BLEND_Y:begin pixel<=rounded[23:16];state<=WRITE;end
   WRITE:begin
    if(ox==255 && oy==95)begin success<=1;state<=FINISH;end
    else begin
     if(ox==255)begin
      ox<=0;oy<=oy+1'b1;target_x<=min_x;x_error<=0;
      target_y<=target_y+$signed(y_step)+(next_y_error>=96);
      y_error<=next_y_error>=96 ? next_y_error-96 : next_y_error;
     end else begin
      ox<=ox+1'b1;target_x<=target_x+$signed(x_step)+next_x_error[8];x_error<=next_x_error[7:0];
     end
     state<=MAP_START;
    end
   end
   FINISH:begin done<=1;state<=IDLE;end
  endcase
 end
endmodule
`endif
