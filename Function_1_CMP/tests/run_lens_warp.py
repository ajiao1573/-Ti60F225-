"""Measured-map numerical checks and pixel-exact RTL ROI warp regression."""
import sys,json,random,math
from pathlib import Path
from run_canny import simulate,write_hex,OUT
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from lens_geometry import LensProfile
from export_lens_rom import inverse

rom=[int(v,16) for v in (ROOT/'src/calibration/lens_map.hex').read_text().split()]
p=LensProfile(json.loads((ROOT/'docs/calibration/lens_profile_native1080.json').read_text()))
def signed(v):return v-(1<<21) if v&(1<<20) else v
def lookup(x,y,inv=False,grid=rom):
    xx,yy=x+65536,y+65536;gx,gy=xx>>14,yy>>14;fx,fy=xx&16383,yy&16383
    assert 0<=gx<38 and 0<=gy<25
    out=[]
    for axis in range(2):
        shift=21*(axis+2*int(inv))
        a,b,c,d=[signed((grid[(gy+dy)*39+gx+dx]>>shift)&0x1fffff) for dx,dy in [(0,0),(1,0),(0,1),(1,1)]]
        top=a+((b-a)*fx>>14);bottom=c+((d-c)*fx>>14)
        out.append(top+((bottom-top)*fy>>14))
    return out

rng=random.Random(119)
requests=[];maxerror=[0,0]
for inv in [False,True]:
    for _ in range(500):
        x,y=rng.randrange(1920*256),rng.randrange(1080*256)
        q=lookup(x,y,inv);exact=inverse(p,x/256,y/256) if inv else p.source(x/256,y/256)
        maxerror[inv]=max(maxerror[inv],math.dist([v/256 for v in q],exact))
        requests.append((x,y,int(inv),*q))
assert max(maxerror)<.8,maxerror
print('Maximum sampled native-coordinate ROM error forward/inverse:',maxerror)
commands='\n'.join(f'check({x},{y},{inv},{a},{b});' for x,y,inv,a,b in requests)
tb='''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0,inv=0;reg signed [20:0] x,y;
wire done,valid;wire signed [20:0] a,b;
lens_grid_lookup dut(.clk(clk),.rst_n(rst),.start(start),.inverse(inv),.x(x),.y(y),.done(done),.valid(valid),.mapped_x(a),.mapped_y(b));
task check(input integer xx,yy,ii,aa,bb);begin
 @(negedge clk);x=xx;y=yy;inv=ii;start=1;@(negedge clk);start=0;
 wait(done);#1;if(!valid || a!==aa || b!==bb)$fatal(1,"lookup got %d,%d expected %d,%d",a,b,aa,bb);
end endtask
initial begin #12;rst=1;
COMMANDS
 @(negedge clk);start=1;x=-100000;y=0;@(negedge clk);start=0;
 wait(done);#1;if(valid)$fatal(1,"out of map must reject");
 $display("PASS lens grid:1000 forward/inverse signed-coordinate samples + bounds");$finish;end
initial begin #2000000;$fatal(1,"timeout");end
endmodule'''.replace('COMMANDS',commands)
simulate('lens_grid',tb,['src/lens_grid_lookup.v'])

pixels=[(x*3+y*5+(x//19%2)*73)&255 for y in range(96) for x in range(256)]
source=write_hex('lens_source',pixels)
def warp(box,grid=rom):
    x,y,w,h=box
    bounds=[lookup(xx*256,yy*256,True,grid) for xx,yy in [(x,y),(x+w//2,y),(x+w,y),(x,y+h//2),(x+w,y+h//2),(x,y+h),(x+w//2,y+h),(x+w,y+h)]]
    left,top=[min(v[i] for v in bounds) for i in range(2)]
    right,bottom=[max(v[i] for v in bounds) for i in range(2)]
    rx,ry=16777216//w,6291456//h
    result=[]
    for oy in range(96):
        for ox in range(256):
            a,b=lookup(left+ox*(right-left)//256,top+oy*(bottom-top)//96,False,grid)
            u,v=((a-x*256)*rx>>16),((b-y*256)*ry>>16)
            if not(0<=u<=255*256 and 0<=v<=95*256):result.append(255);continue
            ix,iy=u>>8,v>>8;fx,fy=u&255,v&255
            p0=pixels[iy*256+ix];p1=pixels[iy*256+min(ix+1,255)]
            p2=pixels[min(iy+1,95)*256+ix];p3=pixels[min(iy+1,95)*256+min(ix+1,255)]
            a=p0*(256-fx)+p1*fx;b=p2*(256-fx)+p3*fx
            result.append((a*(256-fy)+b*fy+32768)>>16)
    return result

boxes=[(640,420,640,192),(32,32,640,200),(1248,840,640,200),(1650,1040,128,32)]
calls=[];expected=[]
for i,box in enumerate(boxes):
    data=warp(box);expected.append(data);dest=write_hex(f'lens_expected{i}',data)
    calls.append(f'$readmemh("{dest}",expected);run_case({",".join(map(str,box))});')
tb='''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0;reg [10:0] x,y,w,h;
wire rd,wr,done,success;wire [14:0] ra,wa;wire [7:0] wd;reg [7:0] data;
reg [7:0] source[0:24575],expected[0:24575];integer n,cycles;
always @(posedge clk)if(rd)data<=source[ra];
lens_roi_warp dut(.clk(clk),.rst_n(rst),.start(start),.roi_x(x),.roi_y(y),.roi_width(w),.roi_height(h),
 .read_enable(rd),.read_address(ra),.read_data(data),.write_enable(wr),.write_address(wa),.write_data(wd),.done(done),.success(success));
task run_case(input integer xx,yy,ww,hh);begin
 @(negedge clk);x=xx;y=yy;w=ww;h=hh;start=1;n=0;cycles=0;
 @(negedge clk);start=0;
 while(!done)begin
  if(wr)begin
   if(wa!==n || wd!==expected[n])$fatal(1,"pixel %d address %d got %d expected %d",n,wa,wd,expected[n]);n=n+1;
  end
  cycles=cycles+1;@(negedge clk);
 end
 if(!success || n!=24576)$fatal(1,"incomplete warp %d",n);
 $display("warp box %d,%d,%d,%d cycles %d",xx,yy,ww,hh,cycles);
end endtask
initial begin
 $readmemh("SOURCE",source);#12;rst=1;
 CALLS
 @(negedge clk);start=1;x=1900;y=0;w=640;h=96;@(negedge clk);start=0;
 wait(done);#1;if(success)$fatal(1,"invalid ROI accepted");
 $display("PASS lens warp:4 native ROIs,98304 exact bilinear pixels,repeated start,bounds");$finish;
end
initial begin #40000000;$fatal(1,"timeout");end
endmodule'''.replace('SOURCE',source).replace('CALLS','\n'.join(calls))
simulate('lens_warp',tb,['src/lens_roi_warp.v'],timeout=180)

# Integration: copy corrected pixels back and derive threshold statistics from
# the corrected image rather than the original captured histogram.
dest=write_hex('lens_integration_expected',expected[0])
hist=[0]*32
for y in range(4,92):
    for x in range(4,252):hist[expected[0][y*256+x]>>3]+=1
checks='\n'.join(f'if(dut.histogram[{i}]!=={v})$fatal(1,"corrected histogram bin {i}");' for i,v in enumerate(hist))
tb='''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0;integer i;reg [7:0] source[0:24575],expected[0:24575];
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.LENS_CORRECTION(1))dut(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_valid(1'b0),.in_sop(1'b0),.in_eop(1'b0),.in_x(11'd0),.in_y(11'd0),.in_gray(8'd0),.adjust(8'd128),
 .pixel_clk(clk),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),.accept_frame(1'b1),.snapshot_ready(1'b1),
 .candidate_valid(1'b0),.roi_x(11'd0),.roi_y(11'd0),.roi_width(11'd0),.roi_height(11'd0));
initial begin
 $readmemh("SOURCE",source);$readmemh("DEST",expected);#12;rst=1;
 wait(dut.state==1);@(negedge clk);
 for(i=0;i<24576;i=i+1)dut.roi_mem[i]=source[i];
 dut.captured_x=640;dut.captured_y=420;dut.captured_width=640;dut.captured_height=192;
 dut.state=54;
 wait(dut.state==3);@(negedge clk);
 for(i=0;i<24576;i=i+1)if(dut.roi_mem[i]!==expected[i])$fatal(1,"copyback pixel %d",i);
 CHECKS
 $display("PASS lens segmenter integration:24576 corrected pixels +32 histogram bins");$finish;
end
initial begin #12000000;$fatal(1,"timeout");end
endmodule'''.replace('SOURCE',source).replace('DEST',dest).replace('CHECKS',checks)
simulate('lens_integration',tb,['src/plate_segmenter.v'])
