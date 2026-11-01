`ifndef SHAPE_HOUGH_V
`define SHAPE_HOUGH_V
// Sequential Hough transforms over sampled boundary points.
// Lines: 18 theta bins x 256 signed rho bins, Q8 trigonometry, 8px rho.
// Local peaks near each DP edge confirm every polygon side independently.
// Circles: 5x5 centre neighbourhood x 5 radii, annulus voting and octants.
module shape_hough(input clk,rst_n,input write_point,input [6:0] write_index,
 input [10:0] write_x,write_y,input start,input [6:0] point_count,
 input [1:0] polygon,input [175:0] vertices,
 input [10:0] xmin,xmax,ymin,ymax,output reg done,output reg [1:0] shape);
 reg [21:0] points[0:79];
 always @(posedge clk) if(write_point) points[write_index]<={write_y,write_x};
 reg [6:0] n,pindex;
 wire [21:0] point=points[pindex];
 wire [10:0] point_x=point[10:0],point_y=point[21:11];
 function signed [9:0] cosine;input [4:0] t;begin case(t)
  0:cosine=256;1:cosine=252;2:cosine=241;3:cosine=222;4:cosine=196;
  5:cosine=165;6:cosine=128;7:cosine=88;8:cosine=44;9:cosine=0;
  10:cosine=-44;11:cosine=-88;12:cosine=-128;13:cosine=-165;
  14:cosine=-196;15:cosine=-222;16:cosine=-241;default:cosine=-252;
 endcase end endfunction
 function signed [9:0] sine;input [4:0] t;begin case(t)
  0:sine=0;1,17:sine=44;2,16:sine=88;3,15:sine=128;
  4,14:sine=165;5,13:sine=196;6,12:sine=222;7,11:sine=241;
  8,10:sine=252;default:sine=256;
 endcase end endfunction
 function [11:0] abs12;input signed [11:0] v;begin abs12=v<0 ? -v : v;end endfunction
 function [22:0] abs23;input signed [22:0] v;begin abs23=v<0 ? -v : v;end endfunction
 function [3:0] popcount;input [7:0] v;integer j;begin popcount=0;for(j=0;j<8;j=j+1) popcount=popcount+v[j];end endfunction
 localparam IDLE=0,CLEAR=1,LPOINT=2,PROJECT=3,LREAD=4,LWRITE=5,
 EDGE=8,EDGE_MATH=9,EDGE_CHECK=10,
 CHYP=11,CRADIUS=12,CPOINT=13,CSQUARE=14,CVOTE=15,CCHECK=16,FINISH=17,LADDR=18,
 EDGE_BIN=19,EDGE_READ=20,EDGE_VOTE=21,PROOF_POINT=22,PROOF_MATH=23,PROOF_VOTE=24,PROOF_DONE=25;
 reg [4:0] state;
 reg signed [11:0] origin_x,origin_y,dx,dy;
 reg [10:0] size,base_radius,centre_step,radius_step,radius,tolerance;
 reg [6:0] accumulator[0:4607];
 reg [12:0] address;
 reg [6:0] acc_read;
 reg [4:0] theta;
 reg signed [22:0] projection;
 wire signed [22:0] rho_value=(projection>>>11)+23'sd128;
 reg [2:0] edge_index,peak_index;
 reg edge_found;
 reg [3:0] supported_edges;
 wire [2:0] next_vertex=edge_index==(polygon==3 ? 2 : 3) ? 0 : edge_index+1'b1;
 wire [21:0] va=vertices[edge_index*22+:22],vb=vertices[next_vertex*22+:22];
 reg signed [11:0] edge_dx,edge_dy,edge_x,edge_y;
 reg signed [22:0] tangent_projection,edge_projection;
 wire signed [22:0] expected_rho=(edge_projection>>>11)+23'sd128;
 wire local_support=acc_read>=3 && acc_read*16>=n;
 wire signed [23:0] edge_rho_bin=expected_rho+$signed({1'b0,peak_index})-24'sd2;
 reg [2:0] cx_index,cy_index,r_index;
 reg signed [11:0] cx,cy;
 reg [23:0] radius_sq,distance_sq,annulus_limit;
 reg [6:0] votes,best_votes;
 reg [7:0] octants,best_octants;
 wire [23:0] radius_error=distance_sq>radius_sq ? distance_sq-radius_sq : radius_sq-distance_sq;
 wire vote=radius_error<=annulus_limit;
 // Octants are direction/sign sectors; no atan is required.
 wire [2:0] octant={dx[11],dy[11],abs12(dx)>abs12(dy)};
 reg circle_found;
 reg signed [11:0] proof_dx,proof_dy;
 reg signed [24:0] proof_cross,proof_dot;
 reg [23:0] edge_length_sq;
 reg [6:0] interior_votes;
 wire [24:0] proof_abs=proof_cross<0 ? -proof_cross : proof_cross;
 wire [10:0] edge_tolerance=((xmax-xmin>ymax-ymin ? xmax-xmin : ymax-ymin)>>4)+2;
 wire interior=proof_abs<=edge_tolerance*(abs12(edge_dx)+abs12(edge_dy)) &&
        proof_dot>$signed({1'b0,edge_length_sq>>3}) &&
        proof_dot<$signed({1'b0,edge_length_sq-(edge_length_sq>>3)});
 always @(posedge clk) begin
  if(state==CLEAR) accumulator[address]<=0;
  if(state==LREAD) acc_read<=accumulator[address];
  if(state==LWRITE) accumulator[address]<=acc_read==127 ? 7'd127 : acc_read+1'b1;
  if(state==EDGE_READ) acc_read<=accumulator[address];
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;done<=0;shape<=0;n<=0;pindex<=0;origin_x<=0;origin_y<=0;dx<=0;dy<=0;
   size<=0;base_radius<=0;centre_step<=0;radius_step<=0;radius<=0;tolerance<=0;
   address<=0;theta<=0;projection<=0;
   edge_index<=0;peak_index<=0;edge_found<=0;supported_edges<=0;
   edge_dx<=0;edge_dy<=0;edge_x<=0;edge_y<=0;tangent_projection<=0;edge_projection<=0;
   cx_index<=0;cy_index<=0;r_index<=0;cx<=0;cy<=0;radius_sq<=0;distance_sq<=0;annulus_limit<=0;
   votes<=0;best_votes<=0;octants<=0;best_octants<=0;circle_found<=0;
   proof_dx<=0;proof_dy<=0;proof_cross<=0;proof_dot<=0;edge_length_sq<=0;interior_votes<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start) begin
     n<=point_count;shape<=0;address<=0;pindex<=0;theta<=0;circle_found<=0;
     origin_x<=({1'b0,xmin}+{1'b0,xmax})>>1;origin_y<=({1'b0,ymin}+{1'b0,ymax})>>1;
     size<=xmax-xmin<ymax-ymin ? xmax-xmin : ymax-ymin;
     base_radius<=(xmax-xmin<ymax-ymin ? xmax-xmin : ymax-ymin)>>1;
     centre_step<=((xmax-xmin<ymax-ymin ? xmax-xmin : ymax-ymin)>>4)+1;
     radius_step<=((xmax-xmin<ymax-ymin ? xmax-xmin : ymax-ymin)>>4)+1;
     best_votes<=0;best_octants<=0;cx_index<=0;cy_index<=0;r_index<=0;
     supported_edges<=0;
     if(point_count<12) state<=FINISH;
     else state<=polygon!=0 ? CLEAR : CHYP;
    end
    CLEAR:if(address==4607) begin pindex<=0;theta<=0;state<=LPOINT;end else address<=address+1'b1;
    LPOINT:begin dx<=$signed({1'b0,point_x})-origin_x;dy<=$signed({1'b0,point_y})-origin_y;state<=PROJECT;end
    PROJECT:begin projection<=dx*cosine(theta)+dy*sine(theta);state<=LADDR;end
    LADDR:begin
     if(rho_value>=0 && rho_value<=255) address<={theta,rho_value[7:0]};else address<=0;
     state<=LREAD;
    end
    LREAD:state<=LWRITE;
    LWRITE:begin
     if(theta==17) begin
      theta<=0;
      if(pindex==n-1) begin edge_index<=0;peak_index<=0;supported_edges<=0;edge_found<=0;state<=EDGE;end
      else begin pindex<=pindex+1'b1;state<=LPOINT;end
     end else begin theta<=theta+1'b1;state<=PROJECT;end
    end
    EDGE:begin
     edge_dx<=$signed({1'b0,vb[10:0]})-$signed({1'b0,va[10:0]});
     edge_dy<=$signed({1'b0,vb[21:11]})-$signed({1'b0,va[21:11]});
     edge_x<=$signed({1'b0,va[10:0]})-origin_x;edge_y<=$signed({1'b0,va[21:11]})-origin_y;state<=EDGE_MATH;
    end
    EDGE_MATH:begin
     tangent_projection<=edge_dx*cosine(theta)+edge_dy*sine(theta);
     edge_projection<=edge_x*cosine(theta)+edge_y*sine(theta);state<=EDGE_CHECK;
     edge_length_sq<=edge_dx*edge_dx+edge_dy*edge_dy;
    end
    EDGE_CHECK:begin
     if(abs23(tangent_projection)<=(abs12(edge_dx)+abs12(edge_dy))*48 && expected_rho>=2 && expected_rho<=253) begin
      peak_index<=0;state<=EDGE_BIN;
     end else if(theta==17) begin
      if(edge_index==(polygon==3 ? 2 : 3)) state<=FINISH;
      else begin edge_index<=edge_index+1'b1;theta<=0;state<=EDGE;end
     end else begin theta<=theta+1'b1;state<=EDGE_MATH;end
    end
    EDGE_BIN:begin address<={theta,edge_rho_bin[7:0]};state<=EDGE_READ;end
    EDGE_READ:state<=EDGE_VOTE;
    EDGE_VOTE:begin
     if(local_support) begin
      // Votes at just the two corners do not establish a polygon side.
      pindex<=0;interior_votes<=0;state<=PROOF_POINT;
     end else if(peak_index<4) begin peak_index<=peak_index+1'b1;state<=EDGE_BIN;end
     else if(theta==17) begin
      if(edge_index==(polygon==3 ? 2 : 3)) state<=FINISH;
      else begin edge_index<=edge_index+1'b1;theta<=0;peak_index<=0;state<=EDGE;end
     end else begin theta<=theta+1'b1;peak_index<=0;state<=EDGE_MATH;end
    end
    PROOF_POINT:begin
     proof_dx<=$signed({1'b0,point_x})-$signed({1'b0,va[10:0]});
     proof_dy<=$signed({1'b0,point_y})-$signed({1'b0,va[21:11]});state<=PROOF_MATH;
    end
    PROOF_MATH:begin proof_cross<=edge_dx*proof_dy-edge_dy*proof_dx;proof_dot<=edge_dx*proof_dx+edge_dy*proof_dy;state<=PROOF_VOTE;end
    PROOF_VOTE:begin
     if(interior) interior_votes<=interior_votes+1'b1;
     if(pindex==n-1) state<=PROOF_DONE;else begin pindex<=pindex+1'b1;state<=PROOF_POINT;end
    end
    PROOF_DONE:begin
     if(interior_votes>=1) supported_edges<=supported_edges+1'b1;
     if(edge_index==(polygon==3 ? 2 : 3)) state<=FINISH;
     else begin edge_index<=edge_index+1'b1;theta<=0;peak_index<=0;state<=EDGE;end
    end
    CHYP:begin
     cx<=origin_x+$signed({1'b0,cx_index})*$signed({1'b0,centre_step})-$signed({1'b0,centre_step,1'b0});
     cy<=origin_y+$signed({1'b0,cy_index})*$signed({1'b0,centre_step})-$signed({1'b0,centre_step,1'b0});
     radius<=base_radius+r_index*radius_step-2*radius_step;state<=CRADIUS;
    end
    CRADIUS:begin
     radius_sq<=radius*radius;tolerance<=(radius>>4)+2;
     annulus_limit<=2*radius*((radius>>4)+2)+((radius>>4)+2)*((radius>>4)+2);
     pindex<=0;votes<=0;octants<=0;state<=CPOINT;
    end
    CPOINT:begin dx<=$signed({1'b0,point_x})-cx;dy<=$signed({1'b0,point_y})-cy;state<=CSQUARE;end
    CSQUARE:begin distance_sq<=dx*dx+dy*dy;state<=CVOTE;end
    CVOTE:begin
     if(vote) begin votes<=votes+1'b1;octants[octant]<=1;end
     if(pindex==n-1) state<=CCHECK;else begin pindex<=pindex+1'b1;state<=CPOINT;end
    end
    CCHECK:begin
     if(votes>best_votes && popcount(octants)>=6) begin best_votes<=votes;best_octants<=octants;end
     if(votes*100>=n*70 && popcount(octants)>=6) circle_found<=1;
     if(r_index==4) begin
      r_index<=0;
      if(cx_index==4) begin
       cx_index<=0;
       if(cy_index==4) state<=FINISH;else begin cy_index<=cy_index+1'b1;state<=CHYP;end
      end else begin cx_index<=cx_index+1'b1;state<=CHYP;end
     end else begin r_index<=r_index+1'b1;state<=CHYP;end
    end
    FINISH:begin
     shape<=polygon!=0 ? (supported_edges==(polygon==3 ? 3 : 4) ? polygon : 0) :
       (circle_found && (xmax-xmin)*4>=(ymax-ymin)*3 && (ymax-ymin)*4>=(xmax-xmin)*3 ? 1 : 0);
     done<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`endif
