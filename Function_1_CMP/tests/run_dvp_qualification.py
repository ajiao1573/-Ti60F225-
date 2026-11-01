from run_canny import simulate
simulate('dvp_qualification',r"""
module tb;
 reg clk=0;always #5 clk=~clk;reg rst=0,cfg=0,vs=0,href=0;reg [7:0] data=0;
 wire fv,pv,err;wire [7:0] pixel;wire [11:0] width,height;
 ov5640_dvp #(.WIDTH(16),.HEIGHT(8),.WARMUP_FRAMES(2)) dut(clk,rst,cfg,vs,href,data,fv,pv,pixel,err,width,height);
 integer pixels=0,f=0,x,y;
 always @(negedge clk) if(pv) begin
  pixels=pixels+1;
  if(!fv || pixel!==8'h69) $fatal(1,"invalid pixel qualifier");
 end
 task tick;begin @(posedge clk);#1;end endtask
 task frame;input integer w;begin
  vs=1;repeat(4) tick;vs=0;repeat(4) tick;
  for(y=0;y<8;y=y+1) begin
   for(x=0;x<w;x=x+1) begin href=1;data=8'h69;tick;end
   href=0;repeat(4) tick;
  end
 end endtask
 initial begin
  repeat(4) tick;rst=1;cfg=1;repeat(8) tick;
  // Blanking-length pulses must never complete warmup or reach the ISP.
  frame(5);frame(5);frame(5);
  if(!err || pixels!=0 || width!=5 || height!=8) $fatal(1,"bad-sized warmup leaked");
  frame(16);frame(16);frame(16);
  if(err || pixels!=128 || width!=16 || height!=8) $fatal(1,"valid stream recovery err=%0d pixels=%0d",err,pixels);
  $display("PASS DVP qualification: blanking-width frames suppressed, two valid frames required, automatic size-error recovery, exact accepted frame");$finish;
 end
endmodule
""",['src/cmos_i2c/ov5640_dvp.v'])
