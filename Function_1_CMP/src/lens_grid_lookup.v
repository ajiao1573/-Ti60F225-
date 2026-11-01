`ifndef LENS_GRID_LOOKUP_V
`define LENS_GRID_LOOKUP_V
// Measured camera map, 64-native-pixel nodes, signed Q8 coordinates.
// Both directions share the ROM; two multipliers are reused for interpolation.
module lens_grid_lookup #(parameter MAP_FILE="src/calibration/lens_map.hex")(
 input clk,rst_n,start,inverse,input signed [20:0] x,y,
 output reg done,valid,output reg signed [20:0] mapped_x,mapped_y);
 localparam IDLE=0,R0=1,R1=2,R2=3,R3=4,TAKE=5,H0=6,H1=7,V=8,FINISH=9;
 reg [3:0] state;
 reg [83:0] rom[0:1013];
 initial $readmemh(MAP_FILE,rom);
 reg [83:0] rom_q;
 reg [9:0] base;
 wire [9:0] address=state==R1 ? base+10'd1 : state==R2 ? base+10'd39 : state==R3 ? base+10'd40 : base;
 always @(posedge clk) if(state>=R0 && state<=R3)rom_q<=rom[address];
 reg inv;
 wire [41:0] node=inv ? rom_q[83:42] : rom_q[41:0];
 reg [41:0] a,b,c,d;
 reg [13:0] fx,fy;
 reg signed [20:0] hx0,hy0,hx1,hy1;
 wire signed [21:0] local_x=$signed(x)+22'sd65536;
 wire signed [21:0] local_y=$signed(y)+22'sd65536;
 function signed [20:0] interpolate;
  input signed [20:0] p,q;
  input [13:0] f;
  reg signed [21:0] delta;
  reg signed [36:0] product;
  begin delta=$signed(q)-$signed(p);product=delta*$signed({1'b0,f});
   interpolate=$signed(p)+(product>>>14);end
 endfunction
 always @(posedge clk or negedge rst_n)
 if(!rst_n) begin state<=IDLE;done<=0;valid<=0;base<=0;inv<=0;fx<=0;fy<=0;mapped_x<=0;mapped_y<=0;end
 else begin
  done<=0;
  case(state)
   IDLE:if(start) begin
    valid<=local_x>=0 && local_x<22'sd622592 && local_y>=0 && local_y<22'sd409600;
    if(local_x<0 || local_x>=22'sd622592 || local_y<0 || local_y>=22'sd409600)state<=FINISH;
    else begin
     base<=local_y[20:14]*10'd39+local_x[20:14];fx<=local_x[13:0];fy<=local_y[13:0];inv<=inverse;state<=R0;
    end
   end
   R0:state<=R1;
   R1:begin a<=node;state<=R2;end
   R2:begin b<=node;state<=R3;end
   R3:begin c<=node;state<=TAKE;end
   TAKE:begin d<=node;state<=H0;end
   H0:begin hx0<=interpolate(a[20:0],b[20:0],fx);hy0<=interpolate(a[41:21],b[41:21],fx);state<=H1;end
   H1:begin hx1<=interpolate(c[20:0],d[20:0],fx);hy1<=interpolate(c[41:21],d[41:21],fx);state<=V;end
   V:begin mapped_x<=interpolate(hx0,hx1,fy);mapped_y<=interpolate(hy0,hy1,fy);state<=FINISH;end
   FINISH:begin done<=1;state<=IDLE;end
  endcase
 end
endmodule
`endif
