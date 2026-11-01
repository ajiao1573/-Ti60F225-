"""Shape RTL regression from independently rasterized geometric outlines."""
from pathlib import Path
import random
from run_canny import simulate, OUT

W,H=160,128
def outline(fill):
    return [int(fill(x,y) and any(not fill(x+dx,y+dy) for dx,dy in
             ((-1,0),(1,0),(0,-1),(0,1)))) for y in range(H) for x in range(W)]
frames=[];fills={}
def add(name, expected, fill=None, pixels=None, enabled=1):
    frames.append((name,expected,outline(fill) if fill else pixels,enabled))
    if fill:fills[name]=fill
for radius in (20,28,40,48):
    add(f'circle_r{radius}',1,lambda x,y,r=radius:(x-80)**2+(y-64)**2<=r*r)
for left,top,w,h in ((20,30,100,60),(51,12,50,99),(60,45,30,30)):
    add(f'rectangle_{w}_{h}',2,lambda x,y,l=left,t=top,w=w,h=h:l<=x<l+w and t<=y<t+h)
for apex in (30,80,125):
    for inverted in (False,True):
        def tri(x,y,a=apex,inv=inverted):
            yy=H-1-y if inv else y
            d=yy-20
            return 0<=d<=80 and a*80+(24-a)*d<=x*80<=a*80+(136-a)*d
        add(f'triangle_apex{apex}_inverted{inverted}',3,tri)
add('blank',0,pixels=[0]*(W*H))
add('small_circle',0,lambda x,y:(x-80)**2+(y-64)**2<=8**2)
add('ellipse',0,lambda x,y:(x-80)**2*20**2+(y-64)**2*55**2<=55**2*20**2)
add('diamond',2,lambda x,y:abs(x-80)+abs(y-64)<=42)
add('open_U',0,pixels=[int((x in (30,125) and 25<=y<=100) or (y==100 and 30<=x<=125)) for y in range(H) for x in range(W)])
add('two_targets',1,lambda x,y:(x-38)**2+(y-64)**2<=25**2 or (x-120)**2+(y-64)**2<=25**2)
add('clipped_rectangle',0,lambda x,y:0<=x<=95 and 25<=y<=100)
rng=random.Random(51)
add('noise',0,pixels=[int(rng.random()<.12) for _ in range(W*H)])
add('disabled_circle',0,lambda x,y:(x-80)**2+(y-64)**2<=40**2,enabled=0)
add('circle_after_disabled',1,lambda x,y:(x-80)**2+(y-64)**2<=40**2)
add('blank_clears_previous',0,pixels=[0]*(W*H))
OUT.joinpath('shape_edges.hex').write_text(''.join(f'{v:x}\n' for _,_,p,_ in frames for v in p))
checks='\n'.join(f' expected[{i}]=2\'d{e};enabled[{i}]=1\'b{en};' for i,(_,e,_,en) in enumerate(frames))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=1,valid=0,sop=0,eop=0,edge_pixel=0;
 wire [1:0] shape;wire done;
 shape_detect #(.WIDTH({W}),.HEIGHT({H})) dut(clk,rst,en,valid,sop,eop,edge_pixel,shape,done,);
 reg edges[0:{len(frames)*W*H-1}];reg [1:0] expected[0:{len(frames)-1}];reg enabled[0:{len(frames)-1}];
 integer f,i,n=0,timeout;reg [1:0] previous;
 initial begin
  $readmemh("tests/generated/shape_edges.hex",edges);
{checks}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(frames)};f=f+1) begin
   en=enabled[f];previous=shape;
   for(i=0;i<{W*H};i=i+1) begin
    @(negedge clk);valid=1;sop=i==0;eop=i=={W*H-1};edge_pixel=edges[n];n=n+1;
    if(i%173==99) begin
     @(negedge clk);valid=0;sop=0;eop=0;repeat(2) @(negedge clk);
    end
   end
   @(negedge clk);valid=0;sop=0;eop=0;
   timeout=0;
   while(!done && timeout<300000) begin @(negedge clk);timeout=timeout+1;end
   if(!done || shape!==expected[f]) begin
    $display("features w=%0d h=%0d area=%0d bad=%0d errors rect/circle/up/down=%0d/%0d/%0d/%0d limit=%0d",dut.box_w,dut.box_h,dut.area,dut.bad_rows,dut.rect_error,dut.circle_error,dut.up_error,dut.down_error,dut.error_limit);
    $fatal(1,"shape frame=%0d got=%0d expected=%0d done=%0d",f,shape,expected[f],done);
   end
   $display("shape frame %0d -> %0d",f,shape);
   repeat(6) @(negedge clk);
  end
  $display("PASS shape outlines: {len(frames)} frames, sizes, aspect ratios, shifted triangle apex, inverted triangles, blanks, noise, clipping, unknown contours, enable, stalls");$finish;
 end
endmodule
'''
simulate('shape',tb,['src/shape_detect.v'])

# Check every result bitmap against independent font/icon raster calculations.
s=Path('src/shape_osd.v').read_text()
import re
fonts={c:[int(bits[i:i+5],2) for i in range(0,35,5)] for c,bits in re.findall(r'"(.)":bits=35\'b([01]{35});',s)}
expected=[]
labels=['No shape ','Circle   ','Rectangle','Triangle ']
circle=[0x03c0,0x0c30,0x1008,0x2004,0x4002,0x4002,0x8001,0x8001,0x8001,0x8001,0x4002,0x4002,0x2004,0x1008,0x0c30,0x03c0]
for shape in range(4):
    for y in range(40):
        for x in range(224):
            ink=False
            if x<32 and 4<=y<36:
                row=(y-4)//2
                icon=0 if not shape else circle[row] if shape==1 else (0xffff if row in (0,15) else 0x8001) if shape==2 else (0xffff if row==15 else ((0x180<<((row+1)//2))|(0x180>>((row+1)//2)))&0xffff)
                ink=bool(icon>>(15-x//2)&1)
            if 48<=x<192 and 12<=y<26:
                col=((x-48)%16)//2
                glyph=fonts.get(labels[shape][(x-48)//16],[0]*7)
                ink|=col<5 and bool(glyph[(y-12)//2]>>(4-col)&1)
            expected.append(0x00ff80 if ink else 0x081020)
OUT.joinpath('shape_osd_expected.hex').write_text(''.join(f'{p:06x}\n' for p in expected))
tb=f'''module tb;
 reg [11:0] x=0,y=0;reg [1:0] shape=0;wire [23:0] pixel;wire active;
 shape_osd dut(x,y,shape,pixel,active);
 reg [23:0] expected[0:{len(expected)-1}];integer f,xx,yy,n=0;
 initial begin
  $readmemh("tests/generated/shape_osd_expected.hex",expected);
  for(f=0;f<4;f=f+1) begin
   shape=f;
   for(yy=0;yy<40;yy=yy+1) for(xx=0;xx<224;xx=xx+1) begin
    x=528+xx;y=680+yy;#1;
    if(!active || pixel!==expected[n]) $fatal(1,"OSD shape=%0d x=%0d y=%0d got=%h expected=%h",f,xx,yy,pixel,expected[n]);
    n=n+1;
   end
   x=527;y=680;#1;if(active) $fatal(1,"left border");
   x=752;y=680;#1;if(active) $fatal(1,"right border");
   x=528;y=679;#1;if(active) $fatal(1,"top border");
   x=528;y=720;#1;if(active) $fatal(1,"bottom border");
  end
  $display("PASS shape OSD: {len(expected)} pixels, three icons/names, No shape, centered bottom bounds");$finish;
 end
endmodule
'''
simulate('shape_osd',tb,['src/shape_osd.v'])

# Exercise the exact production edge engine rather than only ideal outlines.
cases=['circle_r40','rectangle_100_60','triangle_apex80_invertedFalse','triangle_apex80_invertedTrue']
gray=[];algorithms=[];results=[];thresholds=[]
for alg in range(4):
    for name in cases:
        gray.extend(220 if fills[name](x,y) else 20 for y in range(H) for x in range(W))
        algorithms.append(alg)
        thresholds.append(72)
        results.append(1 if name.startswith('circle') else 2 if name.startswith('rectangle') else 3)
for threshold in (72,62,62,62,62,62,62):
    gray.extend(48 if fills['rectangle_100_60'](x,y) else 20 for y in range(H) for x in range(W))
    algorithms.append(3);thresholds.append(threshold);results.append(0 if threshold==72 else 2)
OUT.joinpath('shape_gray.hex').write_text(''.join(f'{p:02x}\n' for p in gray))
init='\n'.join(f' algorithms[{i}]=2\'d{alg};expected[{i}]=2\'d{results[i]};thresholds[{i}]=10\'d{thresholds[i]};' for i,alg in enumerate(algorithms))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,sop=0,eop=0;reg [7:0] data=0;reg [1:0] algorithm=0;
 reg [9:0] threshold=72;
 wire ev,es,ee;wire [7:0] edge_data;wire [1:0] shape;wire done;
 canny_frame #(.WIDTH({W}),.HEIGHT({H}),.RUNTIME_MODES(1)) engine(
  .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(valid),.in_sop(sop),.in_eop(eop),.in_data(data),
  .threshold(threshold),.algorithm(algorithm),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(edge_data));
 shape_detect #(.WIDTH({W}),.HEIGHT({H})) dut(clk,rst,1'b1,ev,es,ee,edge_data!=0,shape,done,);
 reg [7:0] gray[0:{len(gray)-1}];reg [1:0] algorithms[0:{len(algorithms)-1}],expected[0:{len(algorithms)-1}];
 reg [9:0] thresholds[0:{len(algorithms)-1}];
 integer f,i,n=0,timeout;
 initial begin
  $readmemh("tests/generated/shape_gray.hex",gray);
{init}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(algorithms)};f=f+1) begin
   algorithm=algorithms[f];threshold=thresholds[f];
   for(i=0;i<{W*H};i=i+1) begin
    @(negedge clk);valid=1;sop=i==0;eop=i=={W*H-1};data=gray[n];n=n+1;
    if(i%179==41) begin @(negedge clk);valid=0;sop=0;eop=0;repeat(2) @(negedge clk);end
   end
   @(negedge clk);valid=0;sop=0;eop=0;timeout=0;
   while(!done && timeout<300000) begin @(negedge clk);timeout=timeout+1;end
   if(!done || shape!==expected[f]) begin
    $display("features w=%0d h=%0d area=%0d bad=%0d errors=%0d/%0d/%0d/%0d cap=%b%b limit=%0d",dut.box_w,dut.box_h,dut.area,dut.bad_rows,dut.rect_error,dut.circle_error,dut.up_error,dut.down_error,dut.top_closed,dut.bottom_closed,dut.error_limit);
    $fatal(1,"pipeline f=%0d algorithm=%0d got=%0d expected=%0d done=%0d",f,algorithm,shape,expected[f],done);
   end
   repeat(8) @(negedge clk);
  end
  $display("PASS grayscale -> all four real Sobel/Canny algorithms -> shape recognition: {len(algorithms)} frames, stalls, circle/rectangle/triangles, low-contrast 72 vs 62, six identical stationary frames");$finish;
 end
endmodule
'''
simulate('shape_pipeline',tb,['src/shape_detect.v']+[str(p) for p in Path('src/canny').glob('*.v')])
