`ifndef SHAPE_DP_V
`define SHAPE_DP_V
// Iterative closed-contour Ramer-Douglas-Peucker. Exact perpendicular-distance
// test cross^2 > epsilon^2 * segment_length^2; no division/square root.
module shape_dp(input clk,rst_n,input write_point,input [6:0] write_index,
 input [10:0] write_x,write_y,input start,input [6:0] point_count,
 input [10:0] epsilon,input [31:0] box_area,
 output reg done,output reg [1:0] polygon,output reg [5:0] vertex_count,
 output [175:0] vertices);
 reg [21:0] points[0:79];
 always @(posedge clk) if(write_point) points[write_index]<={write_y,write_x};
 reg [10:0] vx[0:7],vy[0:7];
 genvar g;generate for(g=0;g<8;g=g+1) begin:output_vertices
  assign vertices[g*22+:22]={vy[g],vx[g]};
 end endgenerate
 localparam IDLE=0,FAR=1,FAR_SQ=2,FAR_CHECK=3,SEED=4,POP=5,END_A=6,
 END_B=7,LENGTH=8,POINT=9,CROSS=10,MAXIMUM=11,TEST=12,SPLIT=13,
 COLLECT=14,CLOSE=15,CORNER=16,CORNER_MATH=17,CORNER_CHECK=18,FINISH=19;
 reg [4:0] state;
 reg [6:0] n,index,farthest,sa,sb,scan,max_index;
 reg [6:0] stack_a[0:79],stack_b[0:79];reg [6:0] stack_size;
 reg [79:0] keep;
 reg [10:0] ax,ay,bx,by;
 reg [10:0] last_kept_x,last_kept_y;
 reg signed [11:0] dx,dy,px,py;
 reg signed [24:0] cross_value;
 wire [24:0] cross_abs=cross_value[24] ? -cross_value : cross_value;
 reg [24:0] max_cross;
 reg [23:0] length_sq,distance_sq,max_distance;
 reg [21:0] epsilon_sq;
 wire [49:0] max_cross_sq=max_cross*max_cross;
 wire [45:0] distance_limit=epsilon_sq*length_sq;
 wire [21:0] point=points[index];
 wire [10:0] point_x=point[10:0],point_y=point[21:11];
 function [11:0] abs12;input signed [11:0] value;begin abs12=value<0 ? -value : value;end endfunction
 // Only eight coordinates are needed to classify triangles/rectangles, but
 // curved contours may retain more vertices. Keep their last coordinate
 // independently so collection never indexes past the eight output slots.
 wire [12:0] merge_distance=abs12($signed({1'b0,point_x})-$signed({1'b0,last_kept_x}))+
                            abs12($signed({1'b0,point_y})-$signed({1'b0,last_kept_y}));
 reg [2:0] corner;
 reg signed [11:0] ex1,ey1,ex2,ey2;
 reg signed [24:0] dot,turn;
 reg [25:0] norm_product;
 wire [24:0] dot_abs=dot<0 ? -dot : dot;
 reg orthogonal,convex,turn_sign;
 reg signed [33:0] twice_area;
 wire [33:0] area_abs=twice_area<0 ? -twice_area : twice_area;
 wire [2:0] prev=corner==0 ? vertex_count-1 : corner-1'b1;
 wire [2:0] next=corner==vertex_count-1 ? 0 : corner+1'b1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;done<=0;polygon<=0;vertex_count<=0;keep<=0;stack_size<=0;
   n<=0;index<=0;farthest<=0;sa<=0;sb<=0;scan<=0;max_index<=0;
   ax<=0;ay<=0;bx<=0;by<=0;dx<=0;dy<=0;px<=0;py<=0;
   last_kept_x<=0;last_kept_y<=0;
   cross_value<=0;max_cross<=0;length_sq<=0;distance_sq<=0;max_distance<=0;epsilon_sq<=0;
   corner<=0;ex1<=0;ey1<=0;ex2<=0;ey2<=0;dot<=0;turn<=0;norm_product<=0;
   orthogonal<=0;convex<=0;turn_sign<=0;twice_area<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start) begin
     n<=point_count;index<=0;keep<=0;vertex_count<=0;polygon<=0;max_distance<=0;farthest<=0;
     epsilon_sq<=epsilon*epsilon;
     if(point_count<6) state<=FINISH;else begin ax<=points[0][10:0];ay<=points[0][21:11];state<=FAR;end
    end
    FAR:begin px<=$signed({1'b0,point_x})-$signed({1'b0,ax});py<=$signed({1'b0,point_y})-$signed({1'b0,ay});state<=FAR_SQ;end
    FAR_SQ:begin distance_sq<=px*px+py*py;state<=FAR_CHECK;end
    FAR_CHECK:begin
     if(distance_sq>max_distance) begin max_distance<=distance_sq;farthest<=index;end
     if(index==n-1) state<=SEED;else begin index<=index+1'b1;state<=FAR;end
    end
    SEED:begin
     keep[0]<=1;keep[farthest]<=1;keep[n-1]<=1;
     stack_a[0]<=0;stack_b[0]<=farthest;stack_a[1]<=farthest;stack_b[1]<=n-1;
     stack_size<=2;state<=POP;
    end
    POP:if(stack_size==0) begin index<=0;vertex_count<=0;state<=COLLECT;end
     else begin sa<=stack_a[stack_size-1];sb<=stack_b[stack_size-1];stack_size<=stack_size-1'b1;state<=END_A;end
    END_A:begin ax<=points[sa][10:0];ay<=points[sa][21:11];state<=END_B;end
    END_B:begin bx<=points[sb][10:0];by<=points[sb][21:11];state<=LENGTH;end
    LENGTH:begin
     dx<=$signed({1'b0,bx})-$signed({1'b0,ax});dy<=$signed({1'b0,by})-$signed({1'b0,ay});
     index<=sa+1'b1;max_cross<=0;max_index<=sa;
     state<=sb<=sa+1 ? POP : POINT;
    end
    POINT:begin
     px<=$signed({1'b0,point_x})-$signed({1'b0,ax});py<=$signed({1'b0,point_y})-$signed({1'b0,ay});
     length_sq<=dx*dx+dy*dy;state<=CROSS;
    end
    CROSS:begin cross_value<=dx*py-dy*px;state<=MAXIMUM;end
    MAXIMUM:begin
     if(cross_abs>max_cross) begin max_cross<=cross_abs;max_index<=index;end
     if(index==sb-1) state<=TEST;else begin index<=index+1'b1;state<=POINT;end
    end
    TEST:if(max_cross_sq>distance_limit && stack_size<78 && max_index>sa && max_index<sb) state<=SPLIT;else state<=POP;
    SPLIT:begin
     keep[max_index]<=1;stack_a[stack_size]<=sa;stack_b[stack_size]<=max_index;
     stack_a[stack_size+1]<=max_index;stack_b[stack_size+1]<=sb;stack_size<=stack_size+2;state<=POP;
    end
    COLLECT:begin
     if(keep[index] && (vertex_count==0 || merge_distance>epsilon*2)) begin
      last_kept_x<=point_x;last_kept_y<=point_y;
      if(vertex_count<8) begin vx[vertex_count]<=point_x;vy[vertex_count]<=point_y;end
      if(vertex_count<63) vertex_count<=vertex_count+1'b1;
     end
     if(index==n-1) state<=CLOSE;else index<=index+1'b1;
    end
    CLOSE:begin
     if(vertex_count>1 && vertex_count<=8 &&
        abs12($signed({1'b0,vx[0]})-$signed({1'b0,vx[vertex_count-1]}))+
        abs12($signed({1'b0,vy[0]})-$signed({1'b0,vy[vertex_count-1]}))<=epsilon*2)
      vertex_count<=vertex_count-1'b1;
     corner<=0;orthogonal<=1;convex<=1;twice_area<=0;state<=CORNER;
    end
    CORNER:if(vertex_count!=3 && vertex_count!=4) state<=FINISH;
     else begin
      ex1<=$signed({1'b0,vx[corner]})-$signed({1'b0,vx[prev]});ey1<=$signed({1'b0,vy[corner]})-$signed({1'b0,vy[prev]});
      ex2<=$signed({1'b0,vx[next]})-$signed({1'b0,vx[corner]});ey2<=$signed({1'b0,vy[next]})-$signed({1'b0,vy[corner]});
      twice_area<=twice_area+$signed({1'b0,vx[corner]})*$signed({1'b0,vy[next]})-$signed({1'b0,vx[next]})*$signed({1'b0,vy[corner]});
      state<=CORNER_MATH;
     end
    CORNER_MATH:begin
     dot<=ex1*ex2+ey1*ey2;turn<=ex1*ey2-ey1*ex2;
     norm_product<=(abs12(ex1)+abs12(ey1))*(abs12(ex2)+abs12(ey2));state<=CORNER_CHECK;
    end
    CORNER_CHECK:begin
     if(dot_abs*6>norm_product) orthogonal<=0;
     if(corner==0) turn_sign<=turn[24];else if(turn[24]!=turn_sign || turn==0) convex<=0;
     if(corner==vertex_count-1) state<=FINISH;else begin corner<=corner+1'b1;state<=CORNER;end
    end
    FINISH:begin
     polygon<=convex && area_abs*2>=box_area ? (vertex_count==3 ? 3 : vertex_count==4 && orthogonal ? 2 : 0) : 0;
     done<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`endif
