"""Compare packed and previous scalar RTL against independent BFS.
Includes partial words, cross-word diagonals, row borders and full ROI.
Latency is measured from classification EOP to final edge output at 100 MHz.
"""
from run_canny import flood, write_hex, simulate, OUT
import sys
COMPARE_PACKED32='--packed32' in sys.argv
COMPARE_BEFORE='--before-overlay-opt' in sys.argv
import random, json, re

def run(w,h,full=False):
    n=w*h;rng=random.Random(1912+w)
    frames=[]
    # Includes no strong seed, no weak candidates, and padding-boundary cases.
    if not full:
        frames=[[0]*n,[1]*n,[2]*n]
        a=[0]*n;a[w-1]=2;a[w]=1;frames.append(a)
        a=[0]*n
        for x in range(w):a[(h//2)*w+x]=1
        a[(h//2)*w+w-1]=2;frames.append(a)
        # Diagonal over boundaries at x=31/32 and 63/64, then a vertical path.
        a=[0]*n
        for x in range(w):a[min(h-2,1+x%max(1,h-2))*w+x]=1
        a[w+0]=2;frames.append(a)
        for _ in range(6):frames.append([rng.choices([0,1,2],[7,8,1])[0] for i in range(n)])
    else:
        # Clean step classification and noisy/speckled candidate map.
        a=[0]*n
        for y in range(1,h-1):a[y*w+w//2]=2
        frames=[a,[rng.choices([0,1,2],[85,12,3])[0] for i in range(n)]]
        if COMPARE_BEFORE:
            # Long connected weak runs, separated by empty rows. Preserve
            # every weak pixel; this exposes linear local-closure cost.
            frames.append([0 if y%2==0 else 2 if x==0 else 1
                           for y in range(h) for x in range(w)])
    f=len(frames)
    ip=write_hex(f'bench_{w}_{h}_in',sum(frames,[]))
    ep=write_hex(f'bench_{w}_{h}_expected',sum([flood(a,w,h) for a in frames],[]))
    tb=f'''
module tb;
localparam W={w},H={h},N=W*H,F={f};
reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,ie=0;reg [1:0] ic=0;
wire nv,ns,ne,ov,os,oe;wire [7:0] nd,od;wire [31:0] nsw,osw;
canny_hysteresis #(.WIDTH(W),.HEIGHT(H)) packed_dut(clk,rst,iv,ie,ic,,nv,ns,ne,nd,nsw);
canny_hysteresis_scalar #(.WIDTH(W),.HEIGHT(H)) scalar_dut(clk,rst,iv,ie,ic,,ov,os,oe,od,osw);
reg [1:0] inp[0:N*F-1];reg [7:0] expected[0:N*F-1];
integer i,k,nc=0,oc=0,cycles=0,start_cycle=0,fast_cycles=0;
always @(posedge clk) begin
 cycles=cycles+1;if(cycles>100000000) $fatal(1,"timeout");
 if(rst && iv && ie) start_cycle=cycles;
 if(rst && nv) begin
  if(nd!==expected[nc] || ns!==(nc%N==0) || ne!==(nc%N==N-1)) $fatal(1,"packed mismatch %0d",nc);
  nc=nc+1;
  if(ne) fast_cycles=cycles-start_cycle;
 end
 if(rst && ov) begin
  if(od!==expected[oc] || os!==(oc%N==0) || oe!==(oc%N==N-1)) $fatal(1,"scalar mismatch %0d",oc);
  oc=oc+1;
  if(oe) $display("BENCH {w} {h} %0d %0d %0d %0d %0d",oc/N-1,fast_cycles,cycles-start_cycle,nsw,osw);
 end
end
initial begin
 $readmemh("{ip}",inp);$readmemh("{ep}",expected);
 repeat(4) @(negedge clk);rst=1;
 for(k=0;k<F;k=k+1) begin
  for(i=0;i<N;i=i+1) begin
   @(negedge clk);iv=1;ie=i==N-1;ic=inp[k*N+i];
   if(i%11==0) begin @(negedge clk);iv=0;ie=0;end
  end
  @(negedge clk);iv=0;ie=0;
  wait(nc==(k+1)*N && oc==(k+1)*N);repeat(3) @(negedge clk);
 end
 $display("PASS packed/scalar/BFS equivalence {w}x{h}");$finish;
end
endmodule
'''
    name=f'benchmark_{w}_{h}'
    if COMPARE_PACKED32:
        tb=tb.replace('canny_hysteresis_scalar #','canny_hysteresis_packed32 #')
        baseline='tests/reference/canny_hysteresis_packed32.v'
    elif COMPARE_BEFORE:
        tb=tb.replace('canny_hysteresis_scalar #','canny_hysteresis_before_overlay_opt #')
        baseline='tests/reference/canny_hysteresis_before_overlay_opt.v'
    else:baseline='tests/reference/canny_hysteresis_scalar.v'
    simulate(name,tb,['src/canny/canny_hysteresis.v',baseline],timeout=300)
    result=[]
    for line in (OUT/(name+'.log')).read_text().splitlines():
        if line.startswith('BENCH '):
            _,ww,hh,index,fast,slow,fs,ss=line.split()
            result.append(dict(width=int(ww),height=int(hh),case=int(index),packed_cycles=int(fast),
                scalar_cycles=int(slow),speedup=round(int(slow)/int(fast),3),packed_sweeps=int(fs),scalar_sweeps=int(ss)))
    return result

results=[]
for w in (17,32,33,63,64,65,129):results+=run(w,19)
results+=run(848,636,True)
(OUT/('hysteresis_vs_before_overlay_opt.json' if COMPARE_BEFORE else 'hysteresis_vs_packed32.json' if COMPARE_PACKED32 else 'hysteresis_benchmark.json')).write_text(json.dumps(results,indent=2))
print('All',len(results),'comparisons passed; full-frame results:',results[-2:])
