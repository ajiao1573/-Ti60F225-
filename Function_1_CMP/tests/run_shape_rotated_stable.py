"""Actual grayscale/Canny pipeline integration for rotated polygons."""
from pathlib import Path
import math, subprocess
from run_canny import simulate, OUT

W,H=160,128
def polygon(vertices,angle):
    c,s=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    vertices=[(80+x*c-y*s,64+x*s+y*c) for x,y in vertices]
    def fill(x,y):
        signs=[(b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0])
               for a,b in zip(vertices,vertices[1:]+vertices[:1])]
        return all(v>=0 for v in signs) or all(v<=0 for v in signs)
    return fill

frames=[]
for angle in (15,30,45,75):
    frames.append((f'rectangle_{angle}',2,polygon([(-44,-24),(44,-24),(44,24),(-44,24)],angle)))
for angle in (20,110,150):
    frames.append((f'triangle_{angle}',3,polygon([(0,-43),(42,30),(-42,30)],angle)))
gray=[160 if fill(x,y) else 32 for _,_,fill in frames for y in range(H) for x in range(W)]
OUT.joinpath('shape_rotated_pipeline.hex').write_text(''.join(f'{p:02x}\n' for p in gray))
init='\n'.join(f" expected[{i}]=2'd{expected};" for i,(_,expected,_) in enumerate(frames))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,sop=0,eop=0;reg [7:0] data=0;
 wire ev,es,ee,busy;wire [7:0] edge_data;wire [1:0] shape;wire done;
 canny_frame #(.WIDTH({W}),.HEIGHT({H}),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1)) engine(
  .clk(clk),.rst_n(rst),.capture_ready(!busy),.in_valid(valid),.in_sop(sop),.in_eop(eop),.in_data(data),
  .threshold(10'd62),.algorithm(2'd3),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(edge_data));
 shape_detect #(.WIDTH({W}),.HEIGHT({H})) dut(clk,rst,1'b1,ev,es,ee,edge_data!=0,shape,done,busy);
 reg [7:0] gray[0:{len(gray)-1}];reg [1:0] expected[0:{len(frames)-1}];integer f,i,n=0,t;
 always @(negedge clk) if(rst && dut.state==4 && dut.found)
  $display("GEOMETRY f=%0d box=%0d,%0d n=%0d DP=%0d vertices=%0d lines=%0d shape=%0d",f,dut.box_w,dut.box_h,dut.geometry.u_geometry.point_count,dut.geometry.u_geometry.dp_polygon,dut.geometry.u_geometry.dp_count,dut.geometry.u_geometry.u_hough.supported_edges,dut.geometry_shape);
 initial begin
  $readmemh("tests/generated/shape_rotated_pipeline.hex",gray);
{init}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(frames)};f=f+1) begin
   for(i=0;i<{W*H};i=i+1) begin
    @(negedge clk);valid=1;sop=i==0;eop=i=={W*H-1};data=gray[n];n=n+1;
   end
   @(negedge clk);valid=0;sop=0;eop=0;t=0;
   while(!done && t<300000) begin @(negedge clk);t=t+1;end
   if(!done || shape!==expected[f])
    $fatal(1,"rotated grayscale frame=%0d got=%0d expected=%0d done=%0d DP=%0d",f,shape,expected[f],done,dut.geometry.u_geometry.dp_count);
   $display("ROTATED_PIPELINE frame=%0d shape=%0d",f,shape);
   repeat(8) @(negedge clk);
  end
  $display("PASS rotated grayscale -> real Canny+Median -> DP/Hough: {len(frames)} frames, rotated rectangles and triangles");$finish;
 end
endmodule
'''
try:
    simulate('shape_rotated_stable',tb,['src/shape_detect.v']+[str(p) for p in Path('src/canny').glob('*.v')])
except subprocess.CalledProcessError as error:
    print(error.stdout or '');raise
