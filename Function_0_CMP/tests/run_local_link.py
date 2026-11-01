"""Bounded linking RTL checked against independent candidate-graph distances."""
from run_canny import simulate,write_hex,local_link,flood
import random,json

def run(w,h,passes):
    n=w*h;rng=random.Random(930+w+passes)
    frames=[[0]*n,[1]*n,[2]*n]
    # Long weak chain; symmetric seed placement exposes scan-direction bias.
    for seed in (0,w-1,w//2):
        a=[0]*n
        for x in range(w): a[(h//2)*w+x]=1
        a[(h//2)*w+seed]=2;frames.append(a)
    for seed in (0,n-1,w-1,(h-1)*w):
        a=[1]*n;a[seed]=2;frames.append(a)
    # A gap must stop propagation, even when a seed is geometrically close.
    a=[0]*n;a[(h//2)*w]=2
    for x in range(2,w):a[(h//2)*w+x]=1
    frames.append(a)
    for _ in range(6):frames.append([rng.choices([0,1,2],[5,4,1])[0] for _ in range(n)])
    classes=sum(frames,[]);edges=sum([local_link(c,w,h,passes) for c in frames],[])
    cp=write_hex(f'local_{w}_{passes}_class',classes);ep=write_hex(f'local_{w}_{passes}_edge',edges)
    tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,isp=0,iep=0;reg [1:0] c=0;
 wire ov,os,oe;wire [7:0] d;
 canny_local_link #(.WIDTH({w}),.HEIGHT({h}),.PASSES({passes})) dut(clk,rst,iv,isp,iep,c,ov,os,oe,d);
 reg [1:0] classes[0:{len(classes)-1}];reg [7:0] edges[0:{len(edges)-1}];
 integer out_count=0,f,i,cycle=0,input_end=0;integer max_tail=0;reg checking=0;
 always @(posedge clk) if(rst) begin
  cycle=cycle+1;if(cycle>100000) $fatal(1,"timeout");
  if(ov && checking) begin
   if(d!==edges[out_count] || os!==(out_count%{n}==0) || oe!==(out_count%{n}=={n-1}))
    $fatal(1,"local linking w={w} passes={passes} pixel=%0d got=%0d expected=%0d",out_count,d,edges[out_count]);
   out_count=out_count+1;
   if(oe && cycle-input_end>max_tail) max_tail=cycle-input_end;
  end
 end
 initial begin
  $readmemh("{cp}",classes);$readmemh("{ep}",edges);
  repeat(5) @(negedge clk);rst=1;
  // Reset an interrupted frame. RAM contents intentionally survive reset.
  for(i=0;i<{n//2};i=i+1) begin @(negedge clk);iv=1;isp=i==0;c=2;end
  @(negedge clk);rst=0;iv=0;isp=0;repeat(5) @(negedge clk);rst=1;out_count=0;checking=1;
  for(f=0;f<{len(frames)};f=f+1) begin
   for(i=0;i<{n};i=i+1) begin
    @(negedge clk);iv=1;isp=i==0;iep=i=={n-1};c=classes[f*{n}+i];
    if(i%13==7) begin @(negedge clk);iv=0;isp=0;iep=0;repeat(i%3) @(negedge clk);end
   end
   input_end=cycle;@(negedge clk);iv=0;isp=0;iep=0;
   wait(out_count==(f+1)*{n});repeat(2) @(negedge clk);
  end
  if(max_tail>{passes}*({w}+12)) $fatal(1,"tail latency %0d",max_tail);
  $display("PASS local linking {w}x{h}, passes={passes}: {len(frames)} frames, 8 directions, borders, weak chains, gaps, no frame leakage, reset, tail=%0d cycles",max_tail);$finish;
 end
endmodule
'''
    simulate(f'local_link_{w}_{passes}',tb,['src/canny/canny_window.v','src/canny/canny_local_link.v'])

for width in (3,17,32,33,65):
    for passes in (1,2):run(width,9,passes)

# Explicit quality tradeoff: two weak pixels survive, longer chain is cut.
c=[2]+[1]*11
assert local_link(c,12,1)==[255]*3+[0]*9
assert flood(c,12,1)==[255]*12
print('PASS bounded-chain contract: seed + 2 connected weak pixels; no global flood')
