"""Douglas-Peucker/Hough versus identical contours with geometry disabled."""
from pathlib import Path
import math,json,subprocess
from run_canny import simulate,OUT
W,H=160,128
def polygon(vertices):
    def fill(x,y):
        signs=[(b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0]) for a,b in zip(vertices,vertices[1:]+vertices[:1])]
        return all(v>=0 for v in signs) or all(v<=0 for v in signs)
    return fill
def outline(fill):
    return [int(fill(x,y) and any(not fill(x+dx,y+dy) for dx,dy in ((-1,0),(1,0),(0,-1),(0,1)))) for y in range(H) for x in range(W)]
def rotated(vertices,angle):
    c,s=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    return [(80+x*c-y*s,64+x*s+y*c) for x,y in vertices]
frames=[]
for angle in (0,15,30,45,60,75,90):
    frames.append((f'rectangle_{angle}',2,outline(polygon(rotated([(-44,-24),(44,-24),(44,24),(-44,24)],angle)))))
for angle in (0,20,40,70,110,150,180,250):
    frames.append((f'triangle_{angle}',3,outline(polygon(rotated([(0,-43),(42,30),(-42,30)],angle)))))
circle=outline(lambda x,y:(x-80)**2+(y-64)**2<=40**2)
frames.append(('circle',1,circle))
frames.append(('circle_missing_arc',1,[int(p and not (42<=i//W<65 and i%W<80)) for i,p in enumerate(circle)]))
base=frames[2][2]
frames.append(('rotated_rectangle_clutter',2,[int(p or i%W in (0,159)) for i,p in enumerate(base)]))
frames.append(('blank',0,[0]*(W*H)))
frames.append(('open_U',0,[int((x in (32,128) and 28<=y<=100) or (y==100 and 32<=x<=128)) for y in range(H) for x in range(W)]))
for sides in (5,6):
    vertices=[(44*math.cos(2*math.pi*j/sides),44*math.sin(2*math.pi*j/sides)) for j in range(sides)]
    frames.append((f'other_polygon_{sides}',0,outline(polygon(rotated(vertices,17)))))
OUT.joinpath('shape_algorithms.hex').write_text(''.join(f'{p:x}\n' for _,_,pixels in frames for p in pixels))
OUT.joinpath('shape_algorithms_cases.json').write_text(json.dumps([{'name':n,'expected':e} for n,e,_ in frames],indent=2))
init='\n'.join(f' expected[{i}]=2\'d{e};' for i,(_,e,_) in enumerate(frames))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,s=0,e=0,p=0;wire [1:0] shape;wire done,busy;
 shape_detect #(.WIDTH({W}),.HEIGHT({H}),.ENABLE_GEOMETRY(1)) dut(clk,rst,1'b1,v,s,e,p,shape,done,busy);
 reg pixels[0:{len(frames)*W*H-1}];reg [1:0] expected[0:{len(frames)-1}];integer f,i,n=0,t;
 // Evidence that the new algorithms, rather than the template fallback,
 // actually produce the recognitions. Parameters are printed per candidate.
 always @(negedge clk) if(rst && dut.state==4 && dut.found && dut.box_w>=20 && dut.box_h>=20) begin
  $display("GEOMETRY frame=%0d shape=%0d template=%0d vertices=%0d DP=%0d circle_votes=%0d/%0d line_edges=%0d",f,dut.geometry_shape,dut.template_shape,
   dut.geometry.u_geometry.dp_count,dut.geometry.u_geometry.dp_polygon,
   dut.geometry.u_geometry.u_hough.best_votes,dut.geometry.u_geometry.point_count,
   dut.geometry.u_geometry.u_hough.supported_edges);
 end
 initial begin
  $readmemh("tests/generated/shape_algorithms.hex",pixels);
{init}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(frames)};f=f+1) begin
   for(i=0;i<{W*H};i=i+1) begin @(negedge clk);v=1;s=i==0;e=i=={W*H-1};p=pixels[n];n=n+1;end
   @(negedge clk);v=0;s=0;e=0;t=0;
   while(!done && t<300000) begin @(negedge clk);t=t+1;end
   $display("RESULT %0d %0d %0d cycles=%0d",f,shape,expected[f],t);
   if(!done || shape!==expected[f]) $fatal(1,"algorithm frame=%0d shape=%0d expected=%0d done=%0d",f,shape,expected[f],done);
   if(busy) $fatal(1,"busy did not release at result publication");
   repeat(6) @(negedge clk);
  end
  $display("PASS DP/Hough: {len(frames)} frames, rotated rectangles/triangles, missing circle arc, clutter, blank/U rejection, actual geometry votes, bounded completion");$finish;
 end
endmodule
'''
try:simulate('shape_algorithms',tb,['src/shape_detect.v'])
except subprocess.CalledProcessError as error:print(error.stdout or '');raise
baseline=tb.replace('.ENABLE_GEOMETRY(1)','.ENABLE_GEOMETRY(0)')
baseline=baseline[:baseline.index(' // Evidence')]+baseline[baseline.index(' initial begin'):]
baseline=baseline.replace('   if(!done || shape!==expected[f])', '   if(!done)')
baseline=baseline.replace('PASS DP/Hough:', 'PASS baseline observation:')
simulate('shape_algorithms_baseline',baseline,['src/shape_detect.v'])
def summary(path):
    rows=[line.split() for line in path.read_text().splitlines() if line.startswith('RESULT ')]
    return {'correct':sum(r[2]==r[3] for r in rows),'frames':len(rows),'max_post_frame_cycles':max(int(r[4].split('=')[1]) for r in rows)}
data={'template_baseline':summary(OUT/'shape_algorithms_baseline.log'),'dp_hough':summary(OUT/'shape_algorithms.log')}
OUT.joinpath('shape_algorithms_comparison.json').write_text(json.dumps(data,indent=2))
print(json.dumps(data,indent=2))
