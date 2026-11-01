"""Bit-exact local Canny regression; BFS also validates the historical engine.
Run: python tests/run_canny.py [--full]
Icarus may be on PATH or in tools/sim/mingw64/bin. No Python packages required.
"""
from pathlib import Path
from collections import deque
import os, random, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SIM = ROOT / 'tools/sim/mingw64/bin'
if SIM.exists(): os.environ['PATH'] = str(SIM) + os.pathsep + os.environ['PATH']
OUT = ROOT / 'tests/generated'
OUT.mkdir(exist_ok=True)

def flood(classes, w, h):
    result = [int(v == 2) for v in classes]
    q = deque(i for i, v in enumerate(result) if v)
    while q:
        i = q.popleft(); y, x = divmod(i, w)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                xx, yy = x+dx, y+dy
                if 0 <= xx < w and 0 <= yy < h:
                    j = yy*w+xx
                    if classes[j] and not result[j]: result[j] = 1; q.append(j)
    return [255*v for v in result]

def local_link(classes, w, h, passes=2):
    """Bounded graph distance from strong seeds, preserving 8-neighbor paths."""
    accepted = [v == 2 for v in classes]
    for _ in range(passes):
        previous = accepted
        accepted = previous[:]
        for y in range(h):
            for x in range(w):
                i = y*w+x
                if classes[i] and not previous[i]:
                    accepted[i] = any(previous[yy*w+xx]
                        for yy in range(max(0,y-1),min(h,y+2))
                        for xx in range(max(0,x-1),min(w,x+2)))
    return [255*int(v) for v in accepted]

def reference(p, w, h, low, median=True, gaussian_passes=2):
    if median:
        m=p[:]
        for y in range(1,h-1):
            for x in range(1,w-1):
                m[y*w+x]=sorted(p[(y+dy)*w+x+dx] for dy in (-1,0,1) for dx in (-1,0,1))[4]
        p=m
    for _ in range(gaussian_passes):
        g=p[:]
        for y in range(1,h-1):
            for x in range(1,w-1):
                g[y*w+x] = (sum(p[(y+dy)*w+x+dx]*wy*wx for dy,wy in [(-1,1),(0,2),(1,1)]
                               for dx,wx in [(-1,1),(0,2),(1,1)])+8)//16
        p=g
    mag, direction = [0]*(w*h), [0]*(w*h)
    for y in range(1,h-1):
        for x in range(1,w-1):
            gx = sum(wy*(g[(y+dy)*w+x+1]-g[(y+dy)*w+x-1]) for dy,wy in [(-1,1),(0,2),(1,1)])
            gy = sum(wx*(g[(y+1)*w+x+dx]-g[(y-1)*w+x+dx]) for dx,wx in [(-1,1),(0,2),(1,1)])
            ax, ay = abs(gx), abs(gy); i=y*w+x
            mag[i] = ax+ay
            direction[i] = 0 if ay*256 <= ax*106 else 2 if ax*256 <= ay*106 else 3 if (gx<0)!=(gy<0) else 1
    cls=[0]*(w*h)
    for y in range(1,h-1):
        for x in range(1,w-1):
            i=y*w+x; d=[1,w+1,w,w-1][direction[i]]
            # Negative offset is NE for 135 degrees, matching RTL n13 then n31.
            a,b=i-d,i+d
            m=mag[i]
            if m and m>=mag[a] and m>mag[b] and m>=low:
                cls[i]=2 if m>=max(1,low*2) else 1
    return g,cls,flood(cls,w,h)

def write_hex(name, data):
    path=OUT/(name+'.hex');path.write_text(''.join(f'{v:x}\n' for v in data))
    return path.relative_to(ROOT).as_posix()

def simulate(name, tb, files, timeout=180):
    src=OUT/(name+'.sv');src.write_text(tb)
    exe=OUT/(name+'.vvp')
    subprocess.run(['iverilog','-g2012','-s','tb','-o',str(exe),str(src),*files],check=True)
    r=subprocess.run(['vvp',str(exe)],check=True,text=True,capture_output=True,timeout=timeout)
    print(r.stdout.strip());(OUT/(name+'.log')).write_text(r.stdout)

RTL=[str(p.relative_to(ROOT)) for p in (ROOT/'src/canny').glob('*.v')]

def frontend_test(w=32,h=24,full=False):
    rng=random.Random(1907)
    frames = [([80]*(w*h),0),([255 if x>=w//2 else 0 for y in range(h) for x in range(w)],10),
              ([200 if y>=h//2 else 20 for y in range(h) for x in range(w)],30),
              ([220 if x>=y else 15 for y in range(h) for x in range(w)],25),
              ([220 if x+y>=w else 15 for y in range(h) for x in range(w)],25),
              ([rng.randrange(256) for _ in range(w*h)],90),
              ([rng.randrange(256) for _ in range(w*h)],1023),([0]*(w*h),0)]
    if full: frames=frames[1:2]
    inputs=[];gs=[];cs=[];es=[];thresholds=[]
    for pixels,t in frames:
        g,c,_=reference(pixels,w,h,t)
        e=local_link(c,w,h)
        inputs+=pixels;gs+=g;cs+=c;es+=e;thresholds.append(t)
    paths=[write_hex('full_'+n if full else n,d) for n,d in zip(['input','gray','class','edge','threshold'],[inputs,gs,cs,es,thresholds])]
    n=w*h;f=len(frames)
    tb=f'''
module tb;
localparam W={w},H={h},N=W*H,F={f};
reg clk=0;always #5 clk=~clk;
reg rst=0,ready=1,iv=0,isp=0,iep=0;reg [7:0] din=0;reg [9:0] threshold=0;
wire start,busy,gv,gs,ge,ev,es,ee;wire [7:0] gd,ed;wire [31:0] sweeps;
canny_frame #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,ready,iv,isp,iep,din,threshold,start,busy,gv,gs,ge,gd,ev,es,ee,ed,sweeps);
reg [7:0] inp[0:N*F-1],gray[0:N*F-1],edges[0:N*F-1];reg [1:0] cls[0:N*F-1];reg [9:0] th[0:F-1];
integer gc=0,ec=0,starts=0,i,k,gap,cycle=0;
always @(posedge clk) begin
 cycle<=cycle+1;
 if(cycle>100000000) $fatal(1,"timeout");
 if(rst) begin
  if(start) starts=starts+1;
  if(gv) begin
   if(gd!==gray[gc] || dut.classification!==cls[gc])
    $fatal(1,"gray/class mismatch index=%0d gray=%0d/%0d class=%0d/%0d",gc,gd,gray[gc],dut.classification,cls[gc]);
   if(gs!==(gc%N==0) || ge!==(gc%N==N-1)) $fatal(1,"gray framing %0d",gc);
   gc=gc+1;
  end
  if(ev) begin
   if(ed!==edges[ec]) $fatal(1,"edge mismatch %0d got=%0d expected=%0d",ec,ed,edges[ec]);
   if(es!==(ec%N==0) || ee!==(ec%N==N-1)) $fatal(1,"edge framing %0d",ec);
   ec=ec+1;
  end
 end
end
initial begin
 $readmemh("{paths[0]}",inp);$readmemh("{paths[1]}",gray);$readmemh("{paths[2]}",cls);
 $readmemh("{paths[3]}",edges);$readmemh("{paths[4]}",th);
 repeat(4) @(negedge clk);rst=1;
 ready=0;iv=1;isp=1;iep=1;din=255;
 repeat(3) @(negedge clk);
 if(start || busy || starts!=0) $fatal(1,"DDR backpressure ignored");
 iv=0;isp=0;iep=0;ready=1;
 // Reset an interrupted capture, then run all frames without further reset.
 @(negedge clk);iv=1;isp=1;din=99;
 @(negedge clk);isp=0;repeat(10) @(negedge clk);
 rst=0;iv=0;repeat(3) @(negedge clk);starts=0;rst=1;
 for(k=0;k<F;k=k+1) begin
  wait(!busy);repeat(10) @(negedge clk);threshold=th[k];
  for(i=0;i<N;i=i+1) begin
   @(negedge clk);iv=1;isp=i==0;iep=i==N-1;din=inp[k*N+i];
   if(i==N/2) threshold=1023; // must not alter this frame
   if(i%7==3 || i%W==W-1) begin
    @(negedge clk);iv=0;isp=0;iep=0;
    for(gap=0;gap<(i%5);gap=gap+1) @(negedge clk);
   end
  end
  @(negedge clk);iv=0;isp=0;iep=0;
  // An unrelated input frame while processing must be ignored.
  @(negedge clk);iv=1;isp=1;iep=1;din=255;
  @(negedge clk);iv=0;isp=0;iep=0;
  wait(ec==(k+1)*N);
 end
 repeat(30) @(negedge clk);
 if(gc!=N*F || ec!=N*F || starts!=F) $fatal(1,"count mismatch");
 $display("PASS frontend+frame {w}x{h}: %0d frames, %0d pixels, cycles=%0d",F,ec,cycle);$finish;
end
endmodule
'''
    simulate('full_frame' if full else 'frontend',tb,RTL)

def hysteresis_test():
    w,h=32,24;n=w*h;rng=random.Random(104)
    frames=[]
    # Long serpentine chain, seed at either end; requires more than a local pass.
    chain=[0]*n;path=[]
    for row in range(1,h-2,3):
        xs=range(1,w-1) if (row//3)%2==0 else range(w-2,0,-1)
        line=[row*w+x for x in xs];path+=line
        if row+3<h-2: path += [(row+1)*w+line[-1]%w,(row+2)*w+line[-1]%w]
    for i in path:chain[i]=1
    for seed in (path[0],path[-1]):
        a=chain[:];a[seed]=2;frames.append(a)
    frames += [[1]*n,[2]*n,[0]*n]
    # Row wrapping must NOT connect last column to next row's first column.
    a=[0]*n;a[w-1]=2;a[w]=1;frames.append(a)
    for _ in range(5):frames.append([rng.choices([0,1,2],[6,9,1])[0] for _ in range(n)])
    inputs=sum(frames,[]);expected=sum([flood(a,w,h) for a in frames],[])
    ip=write_hex('hyst_in',inputs);ep=write_hex('hyst_expected',expected);f=len(frames)
    tb=f'''
module tb;
localparam W={w},H={h},N=W*H,F={f};
reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,ie=0;reg [1:0] ic=0;
wire busy,ov,os,oe;wire [7:0] od;wire [31:0] sweeps;
canny_hysteresis #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,iv,ie,ic,busy,ov,os,oe,od,sweeps);
reg [1:0] inp[0:N*F-1];reg [7:0] expected[0:N*F-1];integer i,k,count=0,cycles=0;
always @(posedge clk) begin
 cycles<=cycles+1;if(cycles>2000000) $fatal(1,"timeout");
 if(rst && ov) begin
  if(od!==expected[count]) $fatal(1,"hysteresis mismatch %0d",count);
  if(os!==(count%N==0) || oe!==(count%N==N-1)) $fatal(1,"framing");
  count=count+1;
  if(oe) $display("hysteresis frame %0d sweeps=%0d",count/N,sweeps);
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
  @(negedge clk);iv=0;ie=0;wait(count==(k+1)*N);repeat(3) @(negedge clk);
 end
 $display("PASS hysteresis BFS equivalence: %0d frames",F);$finish;
end
endmodule
'''
    simulate('hysteresis',tb,['src/canny/canny_hysteresis.v'])

if __name__=='__main__':
    hysteresis_test();frontend_test()
    if '--full' in sys.argv:frontend_test(848,636,True)
