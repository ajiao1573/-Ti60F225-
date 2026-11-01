"""Actual auto-located ROI: synchronous white bounds, exact mask, six glyphs/OCR.

Fixture is a calibration-photo derived crop, not held-out recognition accuracy.
Independent equations reproduce analyze_autoplate_roi.py white_both exactly.
"""
from pathlib import Path
from PIL import Image
from plate_reference import clean_mask,segment_mask
from run_canny import simulate,OUT

p=list(Image.open(Path(__file__).with_name('fixtures')/'autolocate_AUY359_roi.png').convert('L').tobytes())
hist=[0]*32;mi=[255]*32;ma=[0]*32
for y in range(4,92):
 for x in range(4,252):
  v=p[y*256+x];t=y//32*8+x//32;hist[v>>3]+=1;mi[t]=min(mi[t],v);ma[t]=max(ma[t],v)
acc=0;lo=hi=None;total=sum(hist)
for i,n in enumerate(hist):
 acc+=n
 if lo is None and acc>=total//20:lo=i
 if hi is None and acc>=total*19//20:hi=i
white=((lo<<3)+3*(hi<<3))//4
left=[min([x for x in range(256) if p[y*256+x]>=white]+[255]) for y in range(96)]
right=[max([x for x in range(256) if p[y*256+x]>=white]+[0]) for y in range(96)]
top=[min([y for y in range(96) if p[y*256+x]>=white]+[95]) for x in range(256)]
bottom=[max([y for y in range(96) if p[y*256+x]>=white]+[0]) for x in range(256)]
mask=clean_mask([ma[y//32*8+x//32]-mi[y//32*8+x//32]>=24 and
 p[y*256+x]<(mi[y//32*8+x//32]+ma[y//32*8+x//32])//2 and
 left[y]<x<right[y] and top[x]<y<bottom[x]
 for y in range(96) for x in range(256)])
boxes=segment_mask(mask)[1];assert len(boxes)==6,boxes
for name,values in [('input',p),('rows',[a|(b<<8) for a,b in zip(left,right)]),
 ('columns',[a|(b<<7) for a,b in zip(top,bottom)]),('mask',mask),
 ('boxes',[x0|x1<<8|y0<<16|y1<<23 for x0,x1,y0,y1 in boxes])]:
 (OUT/f'panel_enclosure_{name}.hex').write_text(''.join(f'{int(v):x}\n' for v in values))
tb=r'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=0,en=0,v=0,s=0,e=0,accept=0;
reg[10:0]x=0;reg[9:0]y=0;reg[7:0]gray=0;
wire[5:0]stage;wire locked,valid,hold;wire[47:0]ascii;wire[3:0]count;wire[2:0]reason;
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.ENABLE_NZ_OCR(1),.ADAPTIVE_THRESHOLD(1),.BLACK_INK(1),.MIN_HEIGHT(12)) dut(
.clk(clk),.rst_n(rst),.enable(en),.in_valid(v),.in_sop(s),.in_eop(e),.in_x(x),.in_y(y),.in_gray(gray),.adjust(8'd128),
.candidate_valid(1'b1),.roi_x(11'd3),.roi_y(10'd2),.roi_width(11'd256),.roi_height(10'd96),
.accept_frame(accept),.snapshot_ready(1'b1),.capture_hold(hold),
.pixel_clk(1'b0),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),
.cam_state(stage),.cam_locked(locked),.cam_valid(valid),.cam_ascii(ascii),.cam_count(count),.cam_reject(reason));
reg[7:0]pixels[0:24575];reg[15:0]rows[0:95];reg[13:0]columns[0:255];reg goldmask[0:24575];reg[31:0]boxes[0:5];
integer xx,yy,i,mask_base;reg bounds_checked=0,mask_checked=0;
always @(posedge clk)if(rst)begin
 if(stage==5 && !bounds_checked)begin
  if(dut.panel_white!=@WHITE@)$fatal(1,"white threshold got%0d expected@WHITE@",dut.panel_white);
  for(i=0;i<96;i=i+1)if(dut.row_bounds[i]!==rows[i])$fatal(1,"row bound%0d got%h want%h",i,dut.row_bounds[i],rows[i]);
  for(i=0;i<256;i=i+1)if(dut.column_bounds[i]!==columns[i])$fatal(1,"column bound%0d got%h want%h",i,dut.column_bounds[i],columns[i]);
  bounds_checked=1;
 end
 if(stage==8 && dut.dark && !mask_checked)begin
  mask_base=dut.second_polarity ? 24576:0;
  for(yy=4;yy<92;yy=yy+1)for(xx=4;xx<252;xx=xx+1)
   if(dut.mask_mem[mask_base+yy*256+xx]!==goldmask[yy*256+xx])$fatal(1,"enclosed mask %0d,%0d got%b want%b",xx,yy,dut.mask_mem[mask_base+yy*256+xx],goldmask[yy*256+xx]);
  mask_checked=1;
 end
end
initial begin
 $readmemh("tests/generated/panel_enclosure_input.hex",pixels);
 $readmemh("tests/generated/panel_enclosure_rows.hex",rows);
 $readmemh("tests/generated/panel_enclosure_columns.hex",columns);
 $readmemh("tests/generated/panel_enclosure_mask.hex",goldmask);
 $readmemh("tests/generated/panel_enclosure_boxes.hex",boxes);
 repeat(8)@(negedge clk);rst=1;en=1;wait(stage==1);
 @(negedge clk);v=1;s=1;accept=1;x=0;y=0;@(negedge clk);s=0;accept=0;
 for(yy=0;yy<96;yy=yy+1)for(xx=0;xx<256;xx=xx+1)begin
  x=xx+3;y=yy+2;gray=pixels[yy*256+xx];e=xx==255&&yy==95;@(negedge clk);
 end
 v=0;e=0;wait(locked);@(negedge clk);
 if(!bounds_checked||!mask_checked||!valid||ascii!=="AUY359"||count!=6||reason!=0)$fatal(1,"actual ROI failed ascii%s valid%b count%0d reason%0d",ascii,valid,count,reason);
 for(i=0;i<6;i=i+1)if(dut.publish_boxes[i*32+:32]!==boxes[i])$fatal(1,"glyph box%0d got%h want%h",i,dut.publish_boxes[i*32+:32],boxes[i]);
 $display("PASS white-panel enclosure:actual auto-located AUY359 ROI,exact96 row/256 column bounds,21824 mask pixels,six boxes,original OCR limits,normalized crop/stats retained");$finish;
end
initial begin #20000000;$fatal(1,"panel timeout stage%0d reason%0d",stage,reason);end
endmodule
'''.replace('@WHITE@',str(white))
simulate('panel_enclosure',tb,['src/plate_segmenter.v'],timeout=180)
