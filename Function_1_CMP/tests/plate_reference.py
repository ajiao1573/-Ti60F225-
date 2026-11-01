"""Independent image reference for plate segmentation, buffers and rendered pixels."""
from pathlib import Path
from collections import Counter
import random
from PIL import Image,ImageDraw,ImageFont,ImageOps
from run_canny import simulate,OUT

W,H,M=256,96,4
font_path=r'C:\Windows\Fonts\arialbd.ttf'
def sample(text,negative=False,size=55,border=False,noise=False):
    im=Image.new('L',(W,H),220);draw=ImageDraw.Draw(im)
    font=ImageFont.truetype(font_path,size)
    box=draw.textbbox((0,0),text,font=font)
    draw.text(((W-(box[2]-box[0]))//2-box[0],(H-(box[3]-box[1]))//2-box[1]),text,font=font,fill=30)
    if border:
        draw.rectangle((4,4,W-5,H-5),outline=30,width=3)
        for x in [55,200]:draw.ellipse((x,9,x+5,14),fill=30)
    if noise:
        rng=random.Random(40)
        for _ in range(12):draw.point((rng.randrange(8,W-8),rng.choice([16,80])),fill=30)
    return ImageOps.invert(im) if negative else im

def clean_mask(ink):
    result=[False]*len(ink)
    for y in range(M,H-M):result[y*W+M:y*W+W-M]=ink[y*W+M:y*W+W-M]
    for y in range(M,H-M):
        start=None
        for x in range(M,W-M+1):
            on=x<W-M and ink[y*W+x]
            if on and start is None:start=x
            if not on and start is not None:
                if x-start>W//4:
                    result[y*W+start:y*W+x]=[False]*(x-start)
                start=None
    return result

def segment_mask(ink):
    good={y for y in range(M,H-M) if sum(ink[y*W+M:y*W+W-M])<(W-2*M)*3//4}
    points={x:[y for y in good if ink[y*W+x]] for x in range(M,W-M)}
    mass={x:sum(H//6<=y<H*5//6 for y in ys) for x,ys in points.items()}
    peak=max(mass[x] for x in range(W//4,W*3//4));cut=max(2,min(8,peak//10))
    groups=[]
    for x in points:
        if mass[x]>=cut:
            if not groups or x-groups[-1][-1]>2:groups.append([x])
            else:groups[-1].append(x)
    accepted=[]
    for g in groups:
        x0,x1=g[0],g[-1];ys=[y for x in g for y in points[x]]
        if x1-x0+1>=3 and max(ys)-min(ys)+1>=H//4 and sum(mass[x] for x in g)>=H//4*2 and (
            (x0>M+2 and x1<W-M-3) or x1-x0+1>W//4):accepted.append((x0,x1))
    if len(accepted)>16:return 1,[],0,0,0
    boxes=[];quality=0;overflow=False;ink_sum=0;box_sum=0
    def visit(x0,x1):
        nonlocal quality,overflow,ink_sum,box_sum
        if overflow:return
        bands=[]
        for y in range(M,H-M):
            if y in good and sum(ink[y*W+x0:y*W+x1+1])>=2:
                if not bands or y-bands[-1][-1]>2:bands.append([y])
                else:bands[-1].append(y)
        if not bands:return
        band=max(bands,key=lambda b:b[-1]-b[0]+1);y0,y1=band[0],band[-1]
        h,w=y1-y0+1,x1-x0+1
        if h<H//4:return
        if w*4>h*3 and w>=12:
            center=(x0+x1)//2
            valley=min(range(x0+w//4,x1-w//4+1),key=lambda x:(mass[x],abs(x-center)))
            left=right=valley
            while left>x0 and mass[left-1]<=mass[valley]+1:left-=1
            while right<x1 and mass[right+1]<=mass[valley]+1:right+=1
            if mass[valley]*4<=peak and right-left+1<=max(3,h//6):
                visit(x0,valley);visit(valley+1,x1);return
        area=sum(sum(ink[y*W+x0:y*W+x1+1]) for y in band)
        if 3<=w<=W//4 and x0>M+2 and x1<W-M-3 and area>=H//4*2:
            quality+=0 if area*4>w*h*3 and w*4>h else 4
            ink_sum+=area;box_sum+=w*h
            if len(boxes)==8:overflow=True
            else:boxes.append((x0,x1,y0,y1))
    for x0,x1 in accepted:visit(x0,x1)
    return int(overflow),[] if overflow else boxes,quality,ink_sum,box_sum

def choose_first_polarity(a,b):
    """Strokes fill their boxes far less than background gaps between glyphs."""
    a_over,a_boxes,a_score,a_ink,a_box=a
    b_over,b_boxes,b_score,b_ink,b_box=b
    if not a_over and not b_over and len(a_boxes)>=2 and len(b_boxes)>=2:
        if a_ink*b_box<b_ink*a_box and len(a_boxes)+2>=len(b_boxes):return True
        if b_ink*a_box<a_ink*b_box and len(b_boxes)+2>=len(a_boxes):return False
    return a_score>b_score or (a_score==b_score and len(a_boxes)>=len(b_boxes))

def oracle(im,adjust=128):
    p=list(im.tobytes());bins=[0]*32
    for y in range(M,H-M):
        for x in range(M,W-M):bins[p[y*W+x]>>3]+=1
    n=sum(bins);acc=0;lo=hi=None
    for i,v in enumerate(bins):
        acc+=v
        if lo is None and acc>=n//20:lo=i
        if hi is None and acc>=n*19//20:hi=i
    base=((lo<<3)+(hi<<3)+7)//2
    threshold=max(0,min(255,base+adjust-128));dark=(bins.index(max(bins))*8+4)>=base
    low=hi<=lo+1
    ink=[False if low else v<threshold if dark else v>threshold for v in p]
    first_clean=clean_mask(ink)
    first=segment_mask(first_clean);first_over,first_boxes=first[:2]
    other_ink=[False if low else v>threshold if dark else v<threshold for v in p]
    other_clean=clean_mask(other_ink)
    other=segment_mask(other_clean);other_over,other_boxes=other[:2]
    choose_first=choose_first_polarity(first,other)
    if choose_first:overflow,boxes=first_over,first_boxes;norm_ink=first_clean
    else:
        overflow,boxes=other_over,other_boxes
        dark=not dark;ink=other_ink;norm_ink=other_clean
    thumbs=[]
    for x0,x1,y0,y1 in boxes:
        bw,bh=x1-x0+1,y1-y0+1
        fw,fh=(20,max(1,bh*20//bw)) if bw*32>bh*20 else (max(1,bw*32//bh),32)
        px,py=(20-fw)//2,(32-fh)//2
        out=[0]*640
        for y in range(fh):
            for x in range(fw):out[(y+py)*20+x+px]=255*norm_ink[(y0+y*bh//fh)*W+x0+x*bw//fw]
        thumbs+=out
    thumbs += [0]*(5120-len(thumbs))
    return threshold,int(dark),int(low),int(overflow),boxes,thumbs,norm_ink


def run_cases(cases,name,step=1,source_size=None):
    sw,sh=source_size or (W*step,H*step)
    image_data=[];mask_data=[];capture_data=[];thumb_data=[];box_data=[];init=[]
    xgrid={i*sw//W:i for i in range(W)}
    ygrid={i*sh//H:i for i in range(H)}
    for i,(case_name,im,expected,adjust) in enumerate(cases):
        t,d,low,over,boxes,thumbs,ink=oracle(im,adjust)
        assert len(boxes)==expected,(case_name,boxes)
        if case_name=='overflow':assert over
        image_data+=list(im.tobytes());thumb_data+=thumbs;mask_data+=list(map(int,ink))
        raw=im.tobytes()
        capture_data += [raw[ygrid[y]*W+xgrid[x]] if x in xgrid and y in ygrid else 250
                         for y in range(sh) for x in range(sw)]
        packed=[x0|x1<<8|y0<<16|y1<<23 for x0,x1,y0,y1 in boxes]+[0]*(8-len(boxes));box_data+=packed
        init.append(f' levels[{i}]=8\'d{adjust};thr[{i}]=8\'d{t};counts[{i}]=4\'d{expected};polarity[{i}]={d};low[{i}]={low};over[{i}]={over};')
    OUT.joinpath(f'{name}_input.hex').write_text(''.join(f'{x:02x}\n' for x in image_data))
    OUT.joinpath(f'{name}_mask.hex').write_text(''.join(f'{x:x}\n' for x in mask_data))
    OUT.joinpath(f'{name}_capture.hex').write_text(''.join(f'{x:02x}\n' for x in capture_data))
    OUT.joinpath(f'{name}_thumbs.hex').write_text(''.join(f'{x:02x}\n' for x in thumb_data))
    OUT.joinpath(f'{name}_boxes.hex').write_text(''.join(f'{x:08x}\n' for x in box_data))
    tb=f'''`timescale 1ns/1ps
    module tb;
     reg clk=0;always #5 clk=~clk;reg pc=0;always #7 pc=~pc;
     reg rst=0,en=0,iv=0,sop=0,vs=0;reg [10:0] ix=0;reg [9:0] iy=0;reg [7:0] gray=0,adjust=128;
     reg [11:0] x=0,y=0;wire [23:0] rgb;wire ready,overflow,lowc,toggle;wire [3:0] count;wire [7:0] threshold;
     plate_segmenter #(.X_START(2),.Y_START(2),.SOURCE_WIDTH({sw}),.SOURCE_HEIGHT({sh})) dut(.clk(clk),.rst_n(rst),.enable(en),.in_valid(iv),.in_sop(sop),.in_x(ix),.in_y(iy),.in_gray(gray),.adjust(adjust),.pixel_clk(pc),.pixel_rst_n(rst),.vsync(vs),.x_pos(x),.y_pos(y),.pixel(rgb),.ready(ready),.count(count),.threshold(threshold),.overflow(overflow),.low_contrast(lowc),.display_toggle(toggle));
     reg expected_mask[0:{len(mask_data)-1}];
     reg [7:0] captured[0:{len(capture_data)-1}];
     reg [7:0] images[0:{len(image_data)-1}],thumbs[0:{len(thumb_data)-1}],levels[0:{len(cases)-1}],thr[0:{len(cases)-1}];
     reg [31:0] boxes[0:{len(box_data)-1}];reg [3:0] counts[0:{len(cases)-1}];
     reg polarity[0:{len(cases)-1}],low[0:{len(cases)-1}],over[0:{len(cases)-1}];
     integer f,xx,yy,c,n,side;reg old_toggle;reg [31:0] b;reg border,ink;reg [7:0] value;reg [23:0] expected;
     always @(posedge clk) if(rst && ready) begin
      if((dut.state==7 || dut.state==31) && dut.mask_addr/49152==dut.display_bank)
       $fatal(1,"overwrote displayed mask bank");
      if(dut.capture_write && dut.camera_addr/24576==dut.display_bank)
       $fatal(1,"overwrote displayed gray bank");
     end
     task commit;
     begin @(negedge pc);vs=1;repeat(8) @(negedge pc);vs=0;repeat(8) @(negedge pc);end endtask
     initial begin
     $readmemh("tests/generated/{name}_input.hex",images);$readmemh("tests/generated/{name}_thumbs.hex",thumbs);$readmemh("tests/generated/{name}_boxes.hex",boxes);
     $readmemh("tests/generated/{name}_capture.hex",captured);
     $readmemh("tests/generated/{name}_mask.hex",expected_mask);
    {chr(10).join(init)}
     repeat(8) @(negedge clk);rst=1;en=1;
     for(f=0;f<{len(cases)};f=f+1) begin
      wait(dut.state==1);adjust=levels[f];old_toggle=toggle;
      @(negedge clk);iv=1;sop=1;ix=0;iy=0;@(negedge clk);sop=0;iv=0;
      for(yy=0;yy<{sh};yy=yy+1) for(xx=0;xx<{sw};xx=xx+1) begin
       @(negedge clk);iv=1;ix=xx+2;iy=yy+2;
       gray=captured[f*{sw*sh}+yy*{sw}+xx];
       if(xx%31==17) begin @(negedge clk);iv=0;repeat(2) @(negedge clk);end
      end
      @(negedge clk);iv=0;
      wait(dut.state==22);repeat(8) @(negedge pc);
      if(toggle!==old_toggle) $fatal(1,"published before vertical blank");
      if(f==0) begin
       // Leaving/re-entering while publication is pending must not reuse its RAM.
       en=0;repeat(4) @(negedge clk);en=1;wait(dut.state==1);
       @(negedge clk);iv=1;sop=1;@(negedge clk);iv=0;sop=0;
       repeat(4) @(negedge clk);
       if(dut.state!=1) $fatal(1,"reused pending display bank after reentry");
      end
      commit;
      if(!ready || toggle===old_toggle || count!==counts[f] || threshold!==thr[f] || overflow!==over[f] || lowc!==low[f])
       $fatal(1,"result f=%0d count=%0d expected=%0d threshold=%0d expected=%0d",f,count,counts[f],threshold,thr[f]);
      for(c=0;c<count;c=c+1) if(dut.display_boxes[c*32+:32]!==boxes[f*8+c]) $fatal(1,"box f=%0d c=%0d",f,c);
      // Entire raw and binary ROIs, including the actual bounding-box overlay.
      for(side=0;side<2;side=side+1) for(yy=0;yy<96;yy=yy+1) for(xx=0;xx<256;xx=xx+1) begin
       @(posedge pc);#1;x=(side ? 672 : 96)+2*xx;y=208+2*yy;
       value=images[f*24576+yy*256+xx];border=0;
       for(c=0;c<count;c=c+1) begin
        b=boxes[f*8+c];
        if(xx>=b[7:0] && xx<=b[15:8] && yy>=b[22:16] && yy<=b[29:23] &&
          (xx==b[7:0] || xx==b[15:8] || yy==b[22:16] || yy==b[29:23])) border=1;
       end
       ink=expected_mask[f*24576+yy*256+xx];
       expected=border ? 24'h00ff00 : side ? {{24{{ink}}}} : {{3{{value}}}};
       @(negedge pc);#1;if(rgb!==expected) $fatal(1,"ROI pixel f=%0d side=%0d x=%0d y=%0d actual=%h expected=%h",f,side,xx,yy,rgb,expected);
      end
      for(c=0;c<count;c=c+1) for(yy=0;yy<32;yy=yy+1) for(xx=0;xx<20;xx=xx+1) begin
       @(posedge pc);#1;x=264+c*96+xx*4;y=512+yy*4;
       value=thumbs[f*5120+c*640+yy*20+xx];
       @(negedge pc);#1;if(rgb!=={{3{{value}}}}) $fatal(1,"thumbnail f=%0d c=%0d x=%0d y=%0d",f,c,xx,yy);
      end
      old_toggle=toggle;commit;if(toggle!==old_toggle) $fatal(1,"duplicate display commit");
     end
     en=0;repeat(20) @(negedge clk);en=1;repeat(40) @(negedge clk);
     if(dut.state!=1) $fatal(1,"mode exit/reentry");
     $display("PASS {name}: {len(cases)} frames; counts, polarity, bounds, raw/binary pixels, normalized thumbnails and atomic display commits");$finish;
     end
     initial begin #100000000;$fatal(1,"timeout state=%0d",dut.state);end
    endmodule
    '''
    simulate(name,tb,['src/plate_segmenter.v'],timeout=240)
