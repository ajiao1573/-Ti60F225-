"""Two uninterrupted sensor-sized frames through Bayer, smoothing and 4 modes."""
from run_canny import simulate,RTL
decl=[];inst=[];mon=[];checks=[]
for m in range(4):
 decl.append(f'wire ev{m},es{m},ee{m},b{m};wire[7:0] e{m};integer n{m}=0,frames{m}=0,ink{m}=0;')
 inst.append(f'''canny_frame #(.WIDTH(960),.HEIGHT(720),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) d{m}(
 .clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(v),.in_sop(s),.in_eop(e),.in_data(gray),
 .algorithm(2'd{m}),.threshold(10'd22),.busy(b{m}),.edge_valid(ev{m}),.edge_sop(es{m}),.edge_eop(ee{m}),.edge_data(e{m}));''')
 mon.append(f'''if(ev{m}) begin
  if(es{m}!==(n{m}%N==0) || ee{m}!==(n{m}%N==N-1) || ^e{m}===1'bx) $fatal(1,"mode{m} marker/data mismatch");
  if(frames{m}==0 && e{m}!=0) $fatal(1,"mode{m} constant frame edges");
  if(e{m}!=0) ink{m}=ink{m}+1;
  n{m}=n{m}+1;if(ee{m}) frames{m}=frames{m}+1;
 end''')
 checks.append(f'if(frames{m}!=f+1 || b{m}) $fatal(1,"mode{m} failed to finish before next 60Hz SOP");')
tb=r'''`timescale 1ns/1ps
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
 @DECL@
 @INST@
 integer front=0,f,y,x;
 always @(posedge clk) if(rst) begin
  if(overflow) $fatal(1,"front FIFO overflow");
  if(v) begin
   if(s!==(front%N==0) || e!==(front%N==N-1) || ox!=front%960 || oy!=(front%N)/960) $fatal(1,"front pixel/marker");
   if(front<N && rgb!==24'h808080) $fatal(1,"constant RGB changed %h pixel%0d",rgb,front);
   front=front+1;
  end
  @MON@
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
   @CHECK@
  end
  if(ink0==0 || ink1==0 || ink2==0 || ink3==0) $fatal(1,"step lost");
  $display("PASS native960x720 Bayer/smooth/unscaled source and 4 runtime engines: two continuous60Hz frames, exact pixel counts/coordinates, constant no-edge and step retained");$finish;
 end
endmodule
'''
for k,v in [('DECL',decl),('INST',inst),('MON',mon),('CHECK',checks)]:tb=tb.replace('@'+k+'@','\n'.join(v))
simulate('960_pipeline',tb,['src/raw8_rgb_frame.v','src/camera_rgb_denoise.v','src/camera_full_view.v']+RTL,timeout=1200)
