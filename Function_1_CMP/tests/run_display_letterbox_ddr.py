"""477 real rows: DDR color, raw history, pooling, replay and temporal voting."""
from pathlib import Path
import sys,runpy
import run_canny
simulate=run_canny.simulate

def capture(path,args):
 cases={}
 run_canny.simulate=lambda name,tb,files,**kw:cases.update({name:(tb,files)})
 saved=sys.argv;sys.argv=[path,*args]
 try:runpy.run_path(path,run_name='__capture__')
 finally:sys.argv=saved;run_canny.simulate=simulate
 return cases

def swap(s,a,b):
 assert a in s,a
 return s.replace(a,b)

if '--temporal' not in sys.argv:
 s,files=capture('tests/run_overlay.py',['--streaming','--raw-gray','--native-history'])['color_native_capture']
 s=swap(s,'.HISTORY_ENABLE(1),','.EDGE_LINES(477),.GRAY_LINES(238),.LETTERBOX_TOP(79),.HISTORY_ENABLE(1),')
 for a,b in [('y<636','y<477'),('y=624','y=465'),('y==635','y==476'),
             ('rows==3498','rows==2623'),('edge_rows!=636','edge_rows!=477'),
             ('gray_rows!=318','gray_rows!=238'),('packed_rows!=636','packed_rows!=477'),
             ('crop_rows!=318','crop_rows!=239'),('write_beats!=241998','write_beats!=181440'),
             ('!y[0] && !x[0]','y[0] && !x[0]'),('if(!y[0])','if(y[0])'),
             ('yy=42;yy<=677','yy=121;yy<=597'),('yy>=201 && yy<=518','yy>=241 && yy<=478'),
             ('2*(yy-201)','2*(yy-241)+1'),('yy-201','yy-241'),('yy-42','yy-121'),
             ('color(row*2,byte_x*2)','color(row*2+1,byte_x*2)')]:
  s=swap(s,a,b)
 # Independent reference is the OLD padded canvas: first pool combines
 # black row 78 with image row 0; subsequent pools combine 1/2, 3/4, etc.
 s=swap(s,'edge_pixel(2*row,','edge_pixel((row==0 ? 0 : 2*row-1),')
 s=swap(s,'edge_pixel(2*row+1,','edge_pixel(2*row,')
 s=swap(s,".freeze_requested(1'b0),.history_requested(1'b0),.compare_requested(1'b0)",'.freeze_requested(freeze),.history_requested(hist),.compare_requested(comp)')
 s=swap(s,'reg rv=0,','reg freeze=0,hist=0,comp=0;reg rv=0,')
 s=swap(s,'reg [127:0] ddr_mem[0:524287];','reg [127:0] ddr_mem[0:524287];reg [127:0] history_mem[0:131071];')
 s=swap(s,"    if(addr>=32'h02100000) begin","    if(addr>=32'h02000000) history_mem[((addr-32'h02000000)>>4)+beat]<=wdata;\n    if(addr>=32'h02100000) begin")
 s=swap(s,'rdata=ddr_mem[(read_addr>>4)+readbeat];',"rdata=read_addr>=32'h02000000 ? history_mem[((read_addr-32'h02000000)>>4)+readbeat] : ddr_mem[(read_addr>>4)+readbeat];")
 # Live byte planes never stalled this old fixture's R channel; packed
 # history expansion does. Model AXI's held-valid response correctly.
 s=swap(s,' reg ac=0,',' wire rr;reg r_taken=0;reg ac=0,')
 s=swap(s,'.axi_rid(4\'d0),','.axi_rready(rr),.axi_rid(4\'d0),')
 s=swap(s,' always @(posedge ac) begin',' always @(posedge ac) begin\n  r_taken=rvalid && rr;')
 s=swap(s,'if(rvalid) begin','if(rvalid && rr) begin')
 s=swap(s,'  rvalid=!reset && reading && delay_r==0 && random_state[4];','  if(!rvalid || r_taken) begin\n  rvalid=!reset && reading && delay_r==0 && random_state[4];')
 s=swap(s,' : ddr_mem[(read_addr>>4)+readbeat];',' : ddr_mem[(read_addr>>4)+readbeat];\n  end')
 marker='  @(negedge dc);reset=1;repeat(8) @(negedge dc);reset=0;'
 s=swap(s,marker,r'''
  freeze=1;wait(dut.frozen);hist=1;comp=0;refresh;
  for(yy=0;yy<477;yy=yy+1) begin
   for(xx=0;xx<848;xx=xx+1) begin
    if(dut.rfifo_empty || pixel!==edge_pixel(yy,xx)) $fatal(1,"477-row raw replay %d,%d",xx,yy);
    display_en=1;@(negedge dc);
   end
   display_en=0;repeat(600) @(negedge dc);
  end
  comp=1;refresh;
  for(yy=0;yy<239;yy=yy+1) begin
   repeat(2) begin
    for(xx=0;xx<432;xx=xx+1) begin
     expected=(xx<424 && (edge_pixel(2*yy,2*xx)!=0 || edge_pixel(2*yy,2*xx+1)!=0 ||
       edge_pixel(yy==0 ? 0 : 2*yy-1,2*xx)!=0 || edge_pixel(yy==0 ? 0 : 2*yy-1,2*xx+1)!=0)) ? 255 : 0;
     if(dut.rfifo_empty || pixel!==expected) $fatal(1,"239-row native replay %d,%d",xx,yy);
     display_en=1;@(negedge dc);
    end
   end
   display_en=0;repeat(600) @(negedge dc);
  end
  hist=0;comp=0;freeze=0;
'''+marker)
 s=swap(s,'3498 variable-length bursts, 241998 data beats, 636 packed history rows, 318 native thumbnail rows',
        '2623 bursts, 181440 beats, 477 real rows, 238 reference rows, 239 native thumbnail rows; raw replay and dual-pane replay')
 s=swap(s,'full 848x636 alignment','full 848x477 alignment')
 simulate('display_letterbox_ddr477',s,files,timeout=420)

if '--color' not in sys.argv:
 cases=capture('tests/run_temporal_majority.py',['--full'])
 s,files=cases['temporal_majority_full']
 for a,b in [('.EDGE_LINES(636),.GRAY_LINES(318)','.EDGE_LINES(477),.GRAY_LINES(238),.LETTERBOX_TOP(79)'),
             ('y<318;','y<238;'),('yy<636;','yy<477;'),('y<636;','y<477;'),
             ('y==635','y==476'),(' ? 1272 : 0)',' ? 954 : 0)'),
             ('yy>=159 && yy<=476','yy>=120 && yy<=357'),('yy-159','yy-120'),
             ('848x636','848x477')]:s=swap(s,a,b)
 simulate('display_letterbox_temporal477',s,files,timeout=420)
 # Small odd-height native case reaches both ordinary and voted thumbnail
 # completion, including the first single row and final paired row.
 s,files=cases['temporal_majority_native']
 s=swap(s,'.EDGE_LINES(6),.GRAY_LINES(3)','.EDGE_LINES(5),.GRAY_LINES(2),.LETTERBOX_TOP(79)')
 s=swap(s,'y<3;y=y+1) for(x=0;x<432;','y<2;y=y+1) for(x=0;x<432;')
 for a,b in [('yy<6;','yy<5;'),('y<6;','y<5;'),('y==5 &&','y==4 &&'),(' ? 12 : 0)',' ? 10 : 0)'),
             ('edge_value(f,2*row,','edge_value(f,(row==0 ? 0 : 2*row-1),'),
             ('edge_value(f,2*row+1,','edge_value(f,2*row,')]:s=swap(s,a,b)
 simulate('display_letterbox_temporal_native5',s,files,timeout=180)
