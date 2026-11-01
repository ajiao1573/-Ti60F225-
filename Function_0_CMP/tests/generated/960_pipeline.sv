`timescale 1ns/1ps
module tb;
 localparam N=960*720;
 reg clk=0;always #5.952381 clk=~clk;reg rst=0,fv=0,iv=0;reg[7:0] raw=0;
 wire pf,pv;wire[23:0] pr;
 raw8_rgb_frame #(.IMG_HDISP(960),.IMG_VDISP(720)) demosaic(
 .clk(clk),.rst_n(rst),.mirror(2'b00),.per_frame_vsync(fv),.per_frame_href(iv),.per_frame_hsync(iv),.per_img_RAW(raw),
 .post_frame_vsync(pf),.post_frame_href(pv),.post_img_red(pr[23:16]),.post_img_green(pr[15:8]),.post_img_blue(pr[7:0]));
 wire sf,sv;wire[23:0] sr;
 camera_rgb_denoise #(.WIDTH(960),.HEIGHT(720)) smooth(clk,rst,pf,pv,pr,sf,sv,sr);
 wire v,s,e,overflow;wire[23:0] rgb;wire[10:0] ox,oy;
 camera_full_view #(.IN_W(960),.IN_H(720),.WIDTH(960),.HEIGHT(720),.IMAGE_H(720),.FIFO_BITS(6),.LINE_GAP(12)) view(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_frame(sf),.in_valid(sv),.in_rgb(sr),
 .out_valid(v),.out_sop(s),.out_eop(e),.out_rgb(rgb),.out_x(ox),.out_y(oy),.overflow(overflow));
 wire[9:0] sum={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};wire[7:0] gray=sum[9:2];
 wire ev0,es0,ee0,b0;wire[7:0] e0;integer n0=0,frames0=0,ink0=0;
wire ev1,es1,ee1,b1;wire[7:0] e1;integer n1=0,frames1=0,ink1=0;
wire ev2,es2,ee2,b2;wire[7:0] e2;integer n2=0,frames2=0,ink2=0;
wire ev3,es3,ee3,b3;wire[7:0] e3;integer n3=0,frames3=0,ink3=0;
 canny_frame #(.WIDTH(960),.HEIGHT(720),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) d0(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),
 .algorithm(2'd0),.threshold(10'd22),.busy(b0),.edge_valid(ev0),.edge_sop(es0),.edge_eop(ee0),.edge_data(e0));
canny_frame #(.WIDTH(960),.HEIGHT(720),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) d1(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),
 .algorithm(2'd1),.threshold(10'd22),.busy(b1),.edge_valid(ev1),.edge_sop(es1),.edge_eop(ee1),.edge_data(e1));
canny_frame #(.WIDTH(960),.HEIGHT(720),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) d2(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),
 .algorithm(2'd2),.threshold(10'd22),.busy(b2),.edge_valid(ev2),.edge_sop(es2),.edge_eop(ee2),.edge_data(e2));
canny_frame #(.WIDTH(960),.HEIGHT(720),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) d3(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),
 .algorithm(2'd3),.threshold(10'd22),.busy(b3),.edge_valid(ev3),.edge_sop(es3),.edge_eop(ee3),.edge_data(e3));
 integer front=0,f,y,x;
 always @(posedge clk) if(rst) begin
  if(overflow) $fatal(1,"front FIFO overflow");
  if(v) begin
   if(s!==(front%N==0) || e!==(front%N==N-1) || ox!=front%960 || oy!=(front%N)/960) $fatal(1,"front pixel/marker");
   if(front<N && rgb!==24'h808080) $fatal(1,"constant RGB changed %h pixel%0d",rgb,front);
   front=front+1;
  end
  if(ev0) begin
  if(es0!==(n0%N==0) || ee0!==(n0%N==N-1) || ^e0===1'bx) $fatal(1,"mode0 marker/data mismatch");
  if(frames0==0 && e0!=0) $fatal(1,"mode0 constant frame edges");
  if(e0!=0) ink0=ink0+1;
  n0=n0+1;if(ee0) frames0=frames0+1;
 end
if(ev1) begin
  if(es1!==(n1%N==0) || ee1!==(n1%N==N-1) || ^e1===1'bx) $fatal(1,"mode1 marker/data mismatch");
  if(frames1==0 && e1!=0) $fatal(1,"mode1 constant frame edges");
  if(e1!=0) ink1=ink1+1;
  n1=n1+1;if(ee1) frames1=frames1+1;
 end
if(ev2) begin
  if(es2!==(n2%N==0) || ee2!==(n2%N==N-1) || ^e2===1'bx) $fatal(1,"mode2 marker/data mismatch");
  if(frames2==0 && e2!=0) $fatal(1,"mode2 constant frame edges");
  if(e2!=0) ink2=ink2+1;
  n2=n2+1;if(ee2) frames2=frames2+1;
 end
if(ev3) begin
  if(es3!==(n3%N==0) || ee3!==(n3%N==N-1) || ^e3===1'bx) $fatal(1,"mode3 marker/data mismatch");
  if(frames3==0 && e3!=0) $fatal(1,"mode3 constant frame edges");
  if(e3!=0) ink3=ink3+1;
  n3=n3+1;if(ee3) frames3=frames3+1;
 end
 end
 initial begin
  repeat(8) @(negedge clk);rst=1;
  for(f=0;f<2;f=f+1) begin
   for(y=0;y<875;y=y+1) for(x=0;x<1600;x=x+1) begin
    fv=y<720;iv=y<720 && x<960;
    raw=f==0 ? 128 : x<480 ? 50:200;
    @(negedge clk);
   end
   if(front!=(f+1)*N) $fatal(1,"frontend dropped frame");
   if(frames0!=f+1 || b0) $fatal(1,"mode0 failed to finish before next 60Hz SOP");
if(frames1!=f+1 || b1) $fatal(1,"mode1 failed to finish before next 60Hz SOP");
if(frames2!=f+1 || b2) $fatal(1,"mode2 failed to finish before next 60Hz SOP");
if(frames3!=f+1 || b3) $fatal(1,"mode3 failed to finish before next 60Hz SOP");
  end
  if(ink0==0 || ink1==0 || ink2==0 || ink3==0) $fatal(1,"step lost");
  $display("PASS native960x720 Bayer/smooth/unscaled source and 4 runtime engines: two continuous60Hz frames, exact pixel counts/coordinates, constant no-edge and step retained");$finish;
 end
endmodule
