from pathlib import Path
import ast
from run_canny import simulate
src=Path('tests/run_history.py').read_text()
tb=next(n.value.value for n in ast.parse(src).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
tb=tb[:tb.index(' integer beforewrites;')]
tb=tb.replace('reg reset=1,sof=0,eof=0,gv=0,ev=0,freeze=0', 'reg reset=1,freeze=0')
tb=tb.replace('reg [7:0] gd=0,ed=0;', "wire[7:0] ed=0;wire[7:0] gd;")
tb=tb.replace('begin edge_value=((col+3*line+5*frame)%17)<7;end','begin edge_value=0;end')
tb=tb.replace('reg [127:0] mem[0:65535];','reg [127:0] mem[0:65535];reg [127:0] live[0:1048575];')
tb=tb.replace("if(wa>=32'h02000000) begin", "if(wa<32'h02000000) live[wa/16+wb]<=wd;\n    if(wa>=32'h02000000) begin")
tb=tb.replace('hold_b && history_rows==54','hold_b && history_rows==6')
anchor=' split_frame_ctrl #'
bridge=r"""
 reg iv=0,isop=0,ieop=0;reg[10:0] ix=0,iy=0;reg[7:0] v=0;
 wire sof,eof,ev,gv,tv,te;wire[23:0] rgb;
 plate_frame_gate gate(.clk(pc),.rst_n(!reset),.capture_ready(ready),
  .in_valid(iv),.in_sop(isop),.in_eop(ieop),.frame_start(sof),.out_valid(ev),.out_sop(),.out_eop(eof));
 reg accepting=0;
 always @(posedge pc) begin
  if(reset) accepting<=0;
  else begin if(sof) accepting<=1;if(iv && ieop) accepting<=0;end
 end
 video_thumbnail2 #(.WIDTH(848)) thumb(.clk(pc),.rst_n(!reset),
  .in_valid(iv && (sof || accepting)),.in_x(ix),.in_y(iy),.in_rgb({v,v,v}),
  .out_valid(tv),.out_eol(te),.out_rgb(rgb));
 reg[3:0] pad=0;
 always @(posedge pc) if(reset) pad<=0;else if(tv && te) pad<=8;else if(pad!=0) pad<=pad-1;
 assign gv=tv || pad!=0;assign gd=tv ? rgb[23:16]:0;
 integer starts=0,tokens=0,ends=0;
 always @(posedge pc) if(!reset) begin
  if(sof) starts=starts+1;
  if(ev) tokens=tokens+1;
  if(eof) ends=ends+1;
 end
"""
tb=tb.replace(anchor,bridge+anchor,1)
tb+=r"""
 task source_frame(input integer ff);
 begin
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<848;x=x+1) begin
    @(negedge pc);iv=1;isop=(x==0 && y==0);ieop=(x==847 && y==5);
    ix=x;iy=y;v=(x%100)+y+ff*20;
    if(x==1 && y==0) freeze=1;
   end
   @(negedge pc);iv=0;isop=0;ieop=0;repeat(40) @(negedge pc);
  end
 end endtask
 integer n,idx,xx,yy,bank;reg[7:0] expected;
 initial begin
 repeat(10) @(negedge pc);reset=0;
 for(n=0;n<3;n=n+1) begin
  freeze=0;wait(ready);hold_b=n==0;
  source_frame(n);
  if(n==0) begin
   wait(history_rows==6);repeat(50) @(negedge pc);
   if(frozen || ready) $fatal(1,"published before last B response");
   hold_b=0;
  end
  wait(frozen);repeat(50) @(negedge pc);
  if(dut.completed_generation!=n+1 || starts!=n+1 || tokens!=(n+1)*848*6 || ends!=n+1)
   $fatal(1,"frame commit/token count");
  bank=dut.latest_frame_index;
  for(yy=0;yy<3;yy=yy+1) for(xx=0;xx<432;xx=xx+1) begin
   idx=((bank<<22)+32'h200000+(yy<<11)+xx)/16;
   expected=xx<424 ? (2*xx)%100+2*yy+1+n*20:0;
   if(live[idx][xx%16*8+:8]!==expected) $fatal(1,"same-frame thumbnail row=%0d x=%0d got=%0d want=%0d",yy,xx,live[idx][xx%16*8+:8],expected);
  end
  source_frame(9);repeat(100) @(negedge pc);
  if(starts!=n+1 || dut.completed_generation!=n+1 || ready) $fatal(1,"frozen frame overwritten");
 end
 $display("PASS standalone frame gate + real DDR: exact tokens, average/padding, accepted SOP, delayed final response, frozen source rejection and rescan");$finish;
 end
endmodule
"""
fifos=Path('tests/tb_split_frame_ctrl.sv').read_text().split('module tb;')[0]
simulate('plate_transport',fifos+tb,['src/axi/split_frame_ctrl.v','src/plate_frame_gate.v','src/video_thumbnail2.v'],timeout=180)

