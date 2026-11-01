from pathlib import Path
import runpy
import run_canny
from run_canny import ROOT,OUT
original=run_canny.simulate
def bridge(name,tb,files,**kw):
 tb_front=r'''@TICK@timescale 1ns/1ps
module tb;
 localparam IW=768,IH=288,W=256,H=96,F=5,N=W*H;
 reg clk=0;always #5 clk=~clk;reg rst=0,v=0,fr=0;reg[7:0] data=0;
 wire sv,sf;wire[23:0] srgb;
 camera_rgb_smooth #(.WIDTH(IW),.HEIGHT(IH)) smoothing(
 .clk(clk),.rst_n(rst),.in_frame(fr),.in_valid(v),.in_rgb({data,data,data}),
 .out_frame(sf),.out_valid(sv),.out_rgb(srgb));
 wire ov,os,oe,overflow;wire[23:0] rgb;
 camera_full_view #(.IN_W(IW),.IN_H(IH),.WIDTH(W),.HEIGHT(H),.IMAGE_H(H),.FIFO_BITS(5)) resize(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_frame(sf),.in_valid(sv),.in_rgb(srgb),
 .out_valid(ov),.out_sop(os),.out_eop(oe),.out_rgb(rgb),.overflow(overflow));
 wire[9:0] gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
 reg[7:0] images[0:N*F-1];integer f,x,y,count=0,fd;
 always @(posedge clk) if(rst) begin
 if(overflow) $fatal(1,"plate frontend overflow");
 if(ov) begin
 if(os!==(count%N==0) || oe!==(count%N==N-1)) $fatal(1,"plate frontend framing");
 $fwrite(fd,"%02h\n",gray_sum[9:2]);count=count+1;end
 end
 initial begin
 $readmemh("@INPUT@",images);fd=$fopen("@FILTERED@","w");
 repeat(8) @(negedge clk);rst=1;
 for(f=0;f<F;f=f+1) begin
 fr=1;
 for(y=0;y<IH;y=y+1) begin
 for(x=0;x<IW;x=x+1) begin @(negedge clk);v=1;data=images[f*N+(y/3)*W+x/3];end
 @(negedge clk);v=0;repeat(40) @(negedge clk);
 end
 @(negedge clk);fr=0;repeat(IW+64) @(negedge clk);wait(count==(f+1)*N);
 end
 $fclose(fd);$display("PASS five plate fixtures through actual RGB smoothing and 3:1 downsampling");$finish;
 end
endmodule'''
 inp=(OUT/'plate_sizes.hex').as_posix();filtered=(OUT/'noise_fix_plate_pixels.hex').as_posix()
 tb_front=tb_front.replace('@TICK@',chr(96)).replace('@INPUT@',inp).replace('@FILTERED@',filtered)
 original('noise_fix_plate_frontend',tb_front,['src/camera_rgb_smooth.v','src/camera_full_view.v'],timeout=180)
 original('noise_fix_plate',tb.replace(inp,filtered),files,**kw)
run_canny.simulate=bridge
runpy.run_path(str(ROOT/'tests/run_field_plate.py'),run_name='__main__')
