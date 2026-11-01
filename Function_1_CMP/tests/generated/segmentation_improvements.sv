
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,en=0,v=0,s=0,e=0,accept=0;reg[10:0]x=0;reg[9:0]y=0;reg[7:0]gray=0;
wire[1:0]locked,valid,toggle;wire[47:0]ascii[0:1];wire[5:0]stage[0:1];wire[3:0]chars[0:1];wire[2:0]reason[0:1];
genvar k;generate for(k=0;k<2;k=k+1)begin:g
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.ENABLE_NZ_OCR(1),.ADAPTIVE_THRESHOLD(1),
.MIN_HEIGHT(12),.NZ_BLACK_ONLY(k),.FLAT_TILE_FALLBACK(k)) d(
.clk(clk),.rst_n(rst),.enable(en),.in_valid(v),.in_sop(s),.in_eop(e),.in_x(x),.in_y(y),.in_gray(gray),.adjust(8'd128),
.candidate_valid(1'b1),.roi_x(11'd3),.roi_y(10'd2),.roi_width(11'd256),.roi_height(10'd96),
.accept_frame(accept),.snapshot_ready(1'b1),.pixel_clk(1'b0),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),
.cam_state(stage[k]),.cam_locked(locked[k]),.cam_valid(valid[k]),.cam_ascii(ascii[k]),.cam_count(chars[k]),.cam_reject(reason[k]),.cam_result_toggle(toggle[k]));
end endgenerate
reg[7:0]photo[0:24575];integer xx,yy,c,cycles,finished[0:1],j;reg[1:0]seen,checked;
always @(posedge clk)if(rst&&en)begin
 cycles=cycles+1;
 for(j=0;j<2;j=j+1)if(toggle[j]!=seen[j]&&finished[j]==0)finished[j]=cycles;
 if(c==3 && stage[0]==8 && !checked[0])begin
  if(g[0].d.mask_mem[48*256+100]!==0)$fatal(1,"baseline no longer reproduces erased thick-stroke interior");checked[0]=1;
 end
 if(c==3 && stage[1]==8 && !checked[1])begin
  if(g[1].d.mask_mem[48*256+100]!==1)$fatal(1,"fallback erased thick stroke");
  if(g[1].d.mask_mem[48*256+40]!==0)$fatal(1,"fallback filled white paper");checked[1]=1;
 end
end
initial begin
 $readmemh("tests/generated/improvements_roi.hex",photo);
 for(c=0;c<6;c=c+1)begin
  rst=0;en=0;v=0;s=0;e=0;accept=0;cycles=0;finished[0]=0;finished[1]=0;checked=0;seen=0;
  repeat(6)@(negedge clk);rst=1;en=1;wait(stage[0]==1&&stage[1]==1);
  @(negedge clk);v=1;s=1;accept=1;x=0;y=0;gray=200;
  @(negedge clk);s=0;accept=0;
  for(yy=0;yy<96;yy=yy+1)for(xx=0;xx<256;xx=xx+1)begin
   x=xx+3;y=yy+2;e=xx==255&&yy==95;
   gray=c==0 ? photo[yy*256+xx]:c==1 ? 200:c==2 ? 255-photo[yy*256+xx]:
    c==3 ? (xx>=80&&xx<128&&yy>=20&&yy<76 ? 30:200):
    c==4 ? (photo[yy*256+xx]*3)/4+12:photo[yy*256+xx]/2+70;
   @(negedge clk);
  end
  v=0;e=0;wait(finished[0]!=0&&finished[1]!=0);repeat(4)@(negedge clk);
  if(c==0 || c>=4)begin
   if(valid!==3 || ascii[0]!=="AUY359" || ascii[1]!=="AUY359" || chars[1]!=6)$fatal(1,"regression old%s new%s valid%b counts%0d,%0d reasons%0d,%0d",ascii[0],ascii[1],valid,chars[0],chars[1],reason[0],reason[1]);
   if(finished[1]>=finished[0])$fatal(1,"no speed improvement");
  end else if(valid[1]||locked[1])$fatal(1,"negative accepted case%0d ascii%s",c,ascii[1]);
  if(c==3&&checked!==3)$fatal(1,"stroke mask checks not exercised");
  $display("PASS case%0d baseline_cycles%0d improved_cycles%0d old_count%0d new_count%0d valid%b",c,finished[0],finished[1],chars[0],chars[1],valid);
 end
 $display("PASS same-frame A/B: original/dim/low-contrast AUY359 retained, thick-stroke interior recovered, paper preserved, blank/inverse/solid rejected");$finish;
end
initial begin #150000000;$fatal(1,"timeout case%0d stage%0d,%0d",c,stage[0],stage[1]);end
endmodule
