from run_canny import simulate
simulate('field_osd',r'''@TICK@timescale 1ns/1ps
module tb;
 reg [11:0] x=40,y=84;reg [7:0] adj=128;reg low=1,fail=0,locked=0;wire active;wire [23:0] pixel;
 nz_plate_osd #(.DIAGNOSTICS(1)) dut(.x_pos(x),.y_pos(y),.locked(1'b0),.valid(1'b0),.ascii(48'd0),
 .ready(1'b1),.low_contrast(low),.overflow(1'b0),.characters(4'd6),.adjust(adj),.ae_locked(locked),.ae_failed(fail),
 .missing(10'd27),.fps(10'd7),.pixel(pixel),.active(active));
 initial begin
  #1;y=84;#1;if(dut.text!=="GEAR:6 NZ PLATE FPS:007 ") $fatal(1,"FPS %s",dut.text);
  y=156;#1;if(dut.text!=="CHARS:6 LOW:1 OVER:0    ") $fatal(1,"segmentation diagnostic %s",dut.text);
  y=180;#1;if(dut.text!=="LOCAL32 ADJ:+000        ") $fatal(1,"zero offset %s",dut.text);
  adj=43;#1;if(dut.text!=="LOCAL32 ADJ:-085        ") $fatal(1,"signed offset %s",dut.text);
  y=204;#1;if(dut.text!=="AE:AUTO   MISS:027      ") $fatal(1,"AUTO/missing %s",dut.text);
  locked=1;#1;if(dut.text!=="AE:LOCKED MISS:027      ") $fatal(1,"AE lock %s",dut.text);
  fail=1;#1;if(dut.text!=="AE:ERROR  MISS:027      ") $fatal(1,"AE failure %s",dut.text);
  y=223;#1;if(!active) $fatal(1,"last row clipped");y=224;#1;if(active) $fatal(1,"outside diagnostic area");
  $display("PASS field OSD: visible LOW/count/overflow, signed adjustment, AE state, FPS, live missing pixels and bounds");$finish;
 end
endmodule
'''.replace('@TICK@',chr(96)),['src/nz_plate_osd.v'])
