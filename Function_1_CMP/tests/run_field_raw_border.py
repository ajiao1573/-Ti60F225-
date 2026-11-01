
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import run_canny
run_canny.OUT=run_canny.ROOT/'tests/generated'
tb=r'''@TICK@timescale 1ns/1ps
module tb;
 localparam IW=64,IH=36,W=32,H=18,N=W*H;
 reg clk=0;always #5 clk=~clk;reg rst=0,fv=0,de=0;reg [7:0] raw=0,level=80;
 wire rv,rf;wire [7:0] r,g,b;
 raw8_rgb_frame #(.IMG_HDISP(IW),.IMG_VDISP(IH)) isp(
 .clk(clk),.rst_n(rst),.mirror(2'b00),.per_frame_vsync(fv),.per_frame_href(de),.per_frame_hsync(de),.per_img_RAW(raw),
 .post_frame_vsync(rf),.post_frame_href(rv),.post_img_red(r),.post_img_green(g),.post_img_blue(b));
 wire v,s,e,ov;wire [23:0] rgb;wire [10:0] x,y;wire busy,busy_ref;
 camera_full_view #(.IN_W(IW),.IN_H(IH),.WIDTH(W),.HEIGHT(H),.IMAGE_H(H),.FIFO_BITS(5)) resize(
 .clk(clk),.rst_n(rst),.enable(!busy),.in_frame(rf),.in_valid(rv),.in_rgb({r,g,b}),
 .out_valid(v),.out_sop(s),.out_eop(e),.out_rgb(rgb),.out_x(x),.out_y(y),.overflow(ov));
 wire [9:0] gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
 wire [7:0] golden_gray=y<H/2 ? level : level-8'd80;
 wire ev,es,ee,evr,esr,eer;wire [7:0] edge_data,edge_ref;
 canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1)) actual(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray_sum[9:2]),
 .threshold(10'd72),.algorithm(2'd3),.busy(busy),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(edge_data));
 canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1)) direct_gray(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(golden_gray),
 .threshold(10'd72),.algorithm(2'd3),.busy(busy_ref),.edge_valid(evr),.edge_sop(esr),.edge_eop(eer),.edge_data(edge_ref));
 integer f,ix,iy,ec=0,edges=0,border_edges=0,inner_edges=0,ref_edges=0,bad_border=0,bad_inner=0,graycount=0;
 integer ref_border=0;integer frame_edges[0:3];reg [7:0] prev[0:N-1];integer flips=0,total_flips=0;
 always @(negedge clk) if(rst) begin
  if(ov) $fatal(1,"resize FIFO overflow");
  if(v) begin
   graycount=graycount+1;
   if(f>0) begin
    if(x<2 || x>=W-2 || y<2 || y>=H-2) begin if(gray_sum[9:2]!==golden_gray) bad_border=bad_border+1;end
    else if(gray_sum[9:2]!==golden_gray) bad_inner=bad_inner+1;
   end
  end
  if(ev!==evr || es!==esr || ee!==eer) $fatal(1,"stream timing mismatch");
  if(ev) begin
   if(edge_data!=0) begin
    edges=edges+1;
    if((ec%N)/W<4 || (ec%N)/W>=H-4) border_edges=border_edges+1;
    else inner_edges=inner_edges+1;
   end
   if(edge_ref!=0) begin ref_edges=ref_edges+1;if((ec%N)/W<4 || (ec%N)/W>=H-4) ref_border=ref_border+1;end
   if(ec>=2*N && edge_data!==prev[ec%N]) flips=flips+1;
   prev[ec%N]=edge_data;ec=ec+1;
  end
 end
 initial begin
  repeat(8) @(posedge clk);#1;rst=1;
  for(f=0;f<4;f=f+1) begin
   level=f==0 ? 120 : f==2 ? 121 : 120;ref_border=0;edges=0;border_edges=0;inner_edges=0;ref_edges=0;flips=0;bad_border=0;bad_inner=0;
   @(posedge clk);#1;fv=1;
   for(iy=0;iy<IH;iy=iy+1) begin
    for(ix=0;ix<IW;ix=ix+1) begin @(posedge clk);#1;de=1;raw=iy<IH/2 ? level : level-80;end
    @(posedge clk);#1;de=0;repeat(32) @(posedge clk);
   end
   @(posedge clk);#1;fv=0;
   wait(ec==(f+1)*N);repeat(20) @(posedge clk);
   $display("RAW BORDER RTL frame=%0d raw_top_band=%0d edges=%0d border_band_edges=%0d interior_edges=%0d direct_gray_edges=%0d border_gray_mismatch=%0d interior_gray_mismatch=%0d flips=%0d",f,level,edges,border_edges,inner_edges,ref_edges,bad_border,bad_inner,flips);
   if(f>0 && (ref_border!=0 || border_edges!=0)) $fatal(1,"reference unexpectedly has outer-band edges");
   if(f>0) $display("BORDER COMPARE actual=%0d reference=%0d",border_edges,ref_border);
   frame_edges[f]=edges;total_flips=total_flips+flips;
   repeat(400) @(posedge clk);
  end
  $display("PASS current-frame RAW borders: total flips after warmup=%0d",total_flips);$finish;
 end
 initial begin #10000000;$fatal(1,"raw pipeline timeout ec=%0d frame=%0d",ec,f);end
endmodule
'''
files=['src/raw8_rgb_frame.v','src/camera_full_view.v']+run_canny.RTL
run_canny.simulate('field_raw_border',tb.replace('@TICK@',chr(96)),files)
