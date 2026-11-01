"""Exact integer Douglas-Peucker masks versus an independent stack reference."""
from pathlib import Path
import math
from run_canny import simulate,OUT
def reference(points,eps):
    n=len(points);x,y=points[0]
    far=max(range(n),key=lambda i:(points[i][0]-x)**2+(points[i][1]-y)**2)
    keep={0,far,n-1};stack=[(0,far),(far,n-1)]
    while stack:
        a,b=stack.pop()
        if b<=a+1:continue
        ax,ay=points[a];bx,by=points[b];dx,dy=bx-ax,by-ay
        value=lambda i:abs(dx*(points[i][1]-ay)-dy*(points[i][0]-ax))
        m=max(range(a+1,b),key=value)
        if value(m)**2>eps**2*(dx*dx+dy*dy):
            keep.add(m);stack.extend(((a,m),(m,b)))
    return sum(1<<i for i in keep)
rect=[(20+10*i,20) for i in range(8)]+[(100,20+10*i) for i in range(6)]+[(100-10*i,80) for i in range(8)]+[(20,80-10*i) for i in range(6)]+[(20,20)]
triangle=[(20+5*i,20+5*i) for i in range(12)]+[(80-5*i,80) for i in range(12)]+[(20,80-5*i) for i in range(12)]+[(20,20)]
circle=[(80+round(30*math.cos(2*math.pi*i/32)),80+round(30*math.sin(2*math.pi*i/32))) for i in range(33)]
cases=[(rect,2,2),(triangle,2,3),(circle,3,0),([(i*6+10,30+(i%2)*9) for i in range(15)],2,0),([(10+i*4,20+i*3) for i in range(12)],1,0)]
cases.append(([(80+round(50*math.cos(2*math.pi*i/78)),80+round(50*math.sin(2*math.pi*i/78))) for i in range(79)],1,0))
init=[];data=[]
for f,(points,eps,polygon) in enumerate(cases):
    offset=len(data);data.extend(points)
    mask=reference(points,eps);collected=[]
    for i,p in enumerate(points):
        if mask>>i&1 and (not collected or sum(abs(a-b) for a,b in zip(p,collected[-1]))>2*eps):
            collected.append(p)
    if 1<len(collected)<=8 and sum(abs(a-b) for a,b in zip(collected[0],collected[-1]))<=2*eps:
        collected.pop()
    init.append(f"offsets[{f}]={offset};lengths[{f}]={len(points)};eps[{f}]={eps};polygons[{f}]={polygon};counts[{f}]={len(collected)};masks[{f}]=80'h{mask:020x};")
OUT.joinpath('shape_dp_points.hex').write_text(''.join(f'{(y<<11)|x:06x}\n' for x,y in data))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,wp=0,start=0;reg [6:0] wi=0,n=0;
 reg [10:0] x=0,y=0,epsilon=2;wire done;wire [1:0] polygon;wire [5:0] count;wire [175:0] vertices;
 shape_dp dut(clk,rst,wp,wi,x,y,start,n,epsilon,32'd1000,done,polygon,count,vertices);
 reg [21:0] points[0:{len(data)-1}];reg [79:0] masks[0:{len(cases)-1}];integer offsets[0:{len(cases)-1}],lengths[0:{len(cases)-1}],eps[0:{len(cases)-1}],polygons[0:{len(cases)-1}],counts[0:{len(cases)-1}];integer f,i,t;
 initial begin
  $readmemh("tests/generated/shape_dp_points.hex",points);
  {''.join(init)}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(cases)};f=f+1) begin
   for(i=0;i<lengths[f];i=i+1) begin @(negedge clk);wp=1;wi=i;{{y,x}}=points[offsets[f]+i];end
   @(negedge clk);wp=0;n=lengths[f];epsilon=eps[f];start=1;
   @(negedge clk);start=0;t=0;
   while(!done && t<20000) begin @(negedge clk);t=t+1;end
   if(!done || dut.keep!==masks[f]) $fatal(1,"DP exact mask f=%0d got=%h expected=%h",f,dut.keep,masks[f]);
   if(count!==counts[f]) $fatal(1,"DP vertex count f=%0d got=%0d expected=%0d",f,count,counts[f]);
   if(polygon!==polygons[f]) $fatal(1,"DP polygon f=%0d got=%0d count=%0d",f,polygon,count);
   repeat(4) @(negedge clk);
  end
  $display("PASS exact Douglas-Peucker: independent integer reference masks and vertex counts, rectangle/triangle/circle/zigzag/collinear, 79-point contour, closed seam, stack and vertex classification");$finish;
 end
endmodule
'''
simulate('shape_dp',tb,['src/shape_dp.v'])
