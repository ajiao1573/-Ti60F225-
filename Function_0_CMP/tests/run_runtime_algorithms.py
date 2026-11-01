from run_canny import simulate,write_hex,local_link,RTL
import random

def oracle(p,w,h,mode,high):
    if mode&1:
        q=p[:]
        for y in range(1,h-1):
            for x in range(1,w-1):
                q[y*w+x]=sorted(p[(y+dy)*w+x+dx] for dy in (-1,0,1) for dx in (-1,0,1))[4]
        p=q
    if mode&2:
        for _ in range(2):
            q=p[:]
            for y in range(1,h-1):
                for x in range(1,w-1):
                    q[y*w+x]=(sum(p[(y+dy)*w+x+dx]*wy*wx for dy,wy in [(-1,1),(0,2),(1,1)] for dx,wx in [(-1,1),(0,2),(1,1)])+8)//16
            p=q
    mags=[0]*(w*h);direction=[0]*(w*h)
    for y in range(1,h-1):
        for x in range(1,w-1):
            gx=sum(wy*(p[(y+dy)*w+x+1]-p[(y+dy)*w+x-1]) for dy,wy in [(-1,1),(0,2),(1,1)])
            gy=sum(wx*(p[(y+1)*w+x+dx]-p[(y-1)*w+x+dx]) for dx,wx in [(-1,1),(0,2),(1,1)])
            ax,ay=abs(gx),abs(gy);i=y*w+x;mags[i]=ax+ay
            direction[i]=0 if ay*256<=ax*106 else 2 if ax*256<=ay*106 else 3 if (gx<0)!=(gy<0) else 1
    if not mode&2: return p,[255 if m and m>=high else 0 for m in mags],[2 if m and m>=high else 0 for m in mags]
    classes=[0]*(w*h)
    for y in range(1,h-1):
        for x in range(1,w-1):
            i=y*w+x;d=[1,w+1,w,w-1][direction[i]]
            a,b=i-d,i+d
            m=mags[i]
            if m and m>=mags[a] and m>mags[b] and m>=high//3: classes[i]=2 if m>=high else 1
    return p,local_link(classes,w,h),classes

w,h=32,24;n=w*h;rng=random.Random(1908)
modes=[3,0,1,2,0,3,2,1]
pixels=[];grays=[];edges=[];classes=[]
for mode in modes:
    image=[rng.randrange(256) for _ in range(n)]
    g,e,c=oracle(image,w,h,mode,72);pixels+=image;grays+=g;edges+=e;classes+=c
cp=write_hex('runtime_class',classes)
ip=write_hex('runtime_input',pixels);gp=write_hex('runtime_gray',grays);ep=write_hex('runtime_edge',edges)
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,isp=0,iep=0;
 reg [7:0] data=0;reg [1:0] mode=3;reg [9:0] threshold=72;
 wire busy,gv,gs,ge,ev,es,ee;wire [7:0] gd,ed;
 canny_frame #(.WIDTH({w}),.HEIGHT({h}),.RUNTIME_MODES(1)) dut(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(iv),.in_sop(isp),.in_eop(iep),.in_data(data),
 .threshold(threshold),.algorithm(mode),.busy(busy),.gray_valid(gv),.gray_sop(gs),.gray_eop(ge),.gray_data(gd),
 .edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed));
 reg [7:0] input_mem[0:{len(pixels)-1}],gray_mem[0:{len(pixels)-1}],edge_mem[0:{len(pixels)-1}];
 reg [1:0] class_mem[0:{len(pixels)-1}];
 reg [1:0] modes[0:7];integer gc=0,ec=0,f,i,ticks=0;
 always @(posedge clk) if(rst) begin
  ticks=ticks+1;if(ticks>100000) $fatal(1,"timeout");
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
  modes[0]=3;modes[1]=0;modes[2]=1;modes[3]=2;modes[4]=0;modes[5]=3;modes[6]=2;modes[7]=1;
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<8;f=f+1) begin
   wait(!busy);mode=modes[f];threshold=72;
   for(i=0;i<{n};i=i+1) begin
    @(negedge clk);iv=1;isp=i==0;iep=i=={n-1};data=input_mem[f*{n}+i];
    // UI changes mid-frame must affect only the NEXT accepted SOP.
    if(i==7) begin mode=~modes[f];threshold=500;end
    if(i%31==30) begin @(negedge clk);iv=0;isp=0;iep=0;end
   end
   @(negedge clk);iv=0;isp=0;iep=0;wait(ec==(f+1)*{n});repeat(12) @(negedge clk);
  end
  if(gc!={len(pixels)}) $fatal(1,"count");
  $display("PASS four algorithms share gradients: median/Sobel/Canny pixels, 1:3 thresholds, SOP config latch, gaps, successive mode changes");$finish;
 end
endmodule
'''
simulate('runtime_algorithms',tb,RTL)

