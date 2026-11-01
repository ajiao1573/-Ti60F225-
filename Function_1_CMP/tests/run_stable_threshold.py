from run_canny import simulate,write_hex,local_link,RTL
import random,sys

def oracle(p, w, h, mode, high, max_enable=True, robust=True, tight=False):
    max_enable = bool(max_enable)
    low = high * 5 // 8 if tight else high // 3
    if mode & 1:
        q = p[:]
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                q[y * w + x] = sorted((p[(y + dy) * w + x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)))[4]
        p = q
    if mode & 2:
        for _ in range(2):
            q = p[:]
            for y in range(1, h - 1):
                for x in range(1, w - 1):
                    q[y * w + x] = (sum((p[(y + dy) * w + x + dx] * wy * wx for dy, wy in [(-1, 1), (0, 2), (1, 1)] for dx, wx in [(-1, 1), (0, 2), (1, 1)])) + 8) // 16
            p = q
    mags = [0] * (w * h)
    direction = [0] * (w * h)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            gx = sum((wy * (p[(y + dy) * w + x + 1] - p[(y + dy) * w + x - 1]) for dy, wy in [(-1, 1), (0, 2), (1, 1)]))
            gy = sum((wx * (p[(y + 1) * w + x + dx] - p[(y - 1) * w + x + dx]) for dx, wx in [(-1, 1), (0, 2), (1, 1)]))
            ax, ay = (abs(gx), abs(gy))
            i = y * w + x
            mags[i] = ax + ay
            if max_enable:
                a, b, c, d, e, f, g, j, k = (p[(y + dy) * w + x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                mags[i] = max(ax, ay, abs(f + 2 * k + j - b - 2 * a - d), abs(b + 2 * c + f - d - 2 * g - j))
            direction[i] = 0 if ay * 256 <= ax * 106 else 2 if ax * 256 <= ay * 106 else 3 if (gx < 0) != (gy < 0) else 1
    if not mode & 2:
        return (p, [255 if m and m >= high else 0 for i, m in enumerate(mags)], [2 if m and m >= high else 0 for i, m in enumerate(mags)])
    classes = [0] * (w * h)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            i = y * w + x
            d = [1, w + 1, w, w - 1][direction[i]]
            a, b = (i - d, i + d)
            m = mags[i]
            peak = m and m >= mags[a] and (m > mags[b])
            weak_supported = strong_supported = True
            if robust:
                sides = (((-1, -1), (0, -1), (1, -1)), ((-1, 1), (0, 1), (1, 1))) if direction[i] == 0 else (((0, -1), (1, -1), (1, 0)), ((0, 1), (-1, 0), (-1, 1))) if direction[i] == 1 else (((-1, -1), (-1, 0), (-1, 1)), ((1, -1), (1, 0), (1, 1))) if direction[i] == 2 else (((-1, -1), (0, -1), (-1, 0)), ((1, 0), (0, 1), (1, 1)))

                def supported(side, limit):
                    return any((0 <= x + dx < w and 0 <= y + dy < h and (mags[(y + dy) * w + x + dx] > 0) and (mags[(y + dy) * w + x + dx] >= limit) and (direction[(y + dy) * w + x + dx] != direction[i] ^ 2) for dx, dy in side))
                weak_supported = any((supported(side, max(low, m // 2)) for side in sides))
                strong_supported = all((supported(side, max(high, m // 2)) for side in sides))
            if peak and m >= low and weak_supported:
                classes[i] = 2 if m >= high and strong_supported else 1
    return (p, local_link(classes, w, h), classes)

full=False
w,h=(848,636) if full else (32,24)
n=w*h;rng=random.Random(1908)
modes=[3] if full else [3,0,1,2,0,3,2,1]*10
pixels=[];grays=[];edges=[];classes=[];thresholds=[]
for index,mode in enumerate(modes):
    kind=2 if full else index//8
    image=[150 + ((x//4)%2)*(5+5*(y//4)) for y in range(h) for x in range(w)]
    high=[0,1,5,10,30,72,130,255,511,1023][kind]
    thresholds.append(high)
    g,e,c=oracle(image,w,h,mode,high,tight=True);pixels+=image;grays+=g;edges+=e;classes+=c
cp=write_hex('stable_threshold_class',classes)
ip=write_hex('stable_threshold_input',pixels);gp=write_hex('stable_threshold_gray',grays);ep=write_hex('stable_threshold_edge',edges)
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,isp=0,iep=0;
 reg [7:0] data=0;reg [1:0] mode=3;reg [9:0] threshold=72;
 wire busy,gv,gs,ge,ev,es,ee;wire [7:0] gd,ed;
 canny_frame #(.WIDTH({w}),.HEIGHT({h}),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1)) dut(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(iv),.in_sop(isp),.in_eop(iep),.in_data(data),
 .threshold(threshold),.algorithm(mode),.busy(busy),.gray_valid(gv),.gray_sop(gs),.gray_eop(ge),.gray_data(gd),
 .edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed));
 reg [7:0] input_mem[0:{len(pixels)-1}],gray_mem[0:{len(pixels)-1}],edge_mem[0:{len(pixels)-1}];
 reg [1:0] class_mem[0:{len(pixels)-1}];
 reg [1:0] modes[0:{len(modes)-1}];reg [9:0] thresholds[0:{len(modes)-1}];integer gc=0,ec=0,f,i,ticks=0;
 always @(posedge clk) if(rst) begin
  ticks=ticks+1;if(ticks>{max(100000,len(modes)*n*3)}) $fatal(1,"timeout");
  if(gv) begin
   if(dut.classification!==class_mem[gc]) $fatal(1,"class mismatch %0d got %0d exp %0d",gc,dut.classification,class_mem[gc]);
   if(gd!==gray_mem[gc] || gs!==(gc%{n}==0) || ge!==(gc%{n}=={n-1})) $fatal(1,"gray mismatch %0d got %0d exp %0d",gc,gd,gray_mem[gc]);gc=gc+1;
  end
  if(ev) begin
   if(ed!==edge_mem[ec] || es!==(ec%{n}==0) || ee!==(ec%{n}=={n-1})) $fatal(1,"edge mismatch %0d got %0d exp %0d",ec,ed,edge_mem[ec]);ec=ec+1;
  end
 end
 initial begin
  $readmemh("{cp}",class_mem);$readmemh("{ip}",input_mem);$readmemh("{gp}",gray_mem);$readmemh("{ep}",edge_mem);
  {''.join(f"modes[{i}]={m};thresholds[{i}]={thresholds[i]};" for i,m in enumerate(modes))}
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<{len(modes)};f=f+1) begin
   wait(!busy);mode=modes[f];threshold=thresholds[f];
   for(i=0;i<{n};i=i+1) begin
    @(negedge clk);iv=1;isp=i==0;iep=i=={n-1};data=input_mem[f*{n}+i];
    // UI changes mid-frame must affect only the NEXT accepted SOP.
    if(i==7) begin mode=~modes[f];threshold=500;end
    if(i%31==30) begin @(negedge clk);iv=0;isp=0;iep=0;end
   end
   @(negedge clk);iv=0;isp=0;iep=0;wait(ec==(f+1)*{n});repeat(12) @(negedge clk);
  end
  if(gc!={len(pixels)}) $fatal(1,"count");
  $display("PASS reference four-direction maximum, {len(modes)} frames {w}x{h}: median/Sobel/Canny pixels, direct user thresholds, SOP config latch, gaps, successive mode changes");$finish;
 end
endmodule
'''
simulate('stable_threshold_sensitivity',tb,RTL)
for mode in (0,1,2,3):
    counts=[sum(bool(v) for v in edges[i*n:(i+1)*n]) for i,m in enumerate(modes) if m==mode]
    assert len(set(counts))>=3,(mode,counts)
    assert counts==sorted(counts,reverse=True),(mode,counts)
    print('PASS threshold response mode',mode,'edge counts',counts)


