`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0;integer i;reg [7:0] source[0:24575],expected[0:24575];
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.LENS_CORRECTION(1))dut(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_valid(1'b0),.in_sop(1'b0),.in_eop(1'b0),.in_x(11'd0),.in_y(11'd0),.in_gray(8'd0),.adjust(8'd128),
 .pixel_clk(clk),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),.accept_frame(1'b1),.snapshot_ready(1'b1),
 .candidate_valid(1'b0),.roi_x(11'd0),.roi_y(11'd0),.roi_width(11'd0),.roi_height(11'd0));
initial begin
 $readmemh("tests/generated/lens_source.hex",source);$readmemh("tests/generated/lens_integration_expected.hex",expected);#12;rst=1;
 wait(dut.state==1);@(negedge clk);
 for(i=0;i<24576;i=i+1)dut.roi_mem[i]=source[i];
 dut.captured_x=640;dut.captured_y=420;dut.captured_width=640;dut.captured_height=192;
 dut.state=54;
 wait(dut.state==3);@(negedge clk);
 for(i=0;i<24576;i=i+1)if(dut.roi_mem[i]!==expected[i])$fatal(1,"copyback pixel %d",i);
 if(dut.histogram[0]!==279)$fatal(1,"corrected histogram bin 0");
if(dut.histogram[1]!==713)$fatal(1,"corrected histogram bin 1");
if(dut.histogram[2]!==729)$fatal(1,"corrected histogram bin 2");
if(dut.histogram[3]!==731)$fatal(1,"corrected histogram bin 3");
if(dut.histogram[4]!==745)$fatal(1,"corrected histogram bin 4");
if(dut.histogram[5]!==725)$fatal(1,"corrected histogram bin 5");
if(dut.histogram[6]!==736)$fatal(1,"corrected histogram bin 6");
if(dut.histogram[7]!==718)$fatal(1,"corrected histogram bin 7");
if(dut.histogram[8]!==709)$fatal(1,"corrected histogram bin 8");
if(dut.histogram[9]!==709)$fatal(1,"corrected histogram bin 9");
if(dut.histogram[10]!==704)$fatal(1,"corrected histogram bin 10");
if(dut.histogram[11]!==699)$fatal(1,"corrected histogram bin 11");
if(dut.histogram[12]!==694)$fatal(1,"corrected histogram bin 12");
if(dut.histogram[13]!==710)$fatal(1,"corrected histogram bin 13");
if(dut.histogram[14]!==716)$fatal(1,"corrected histogram bin 14");
if(dut.histogram[15]!==718)$fatal(1,"corrected histogram bin 15");
if(dut.histogram[16]!==736)$fatal(1,"corrected histogram bin 16");
if(dut.histogram[17]!==722)$fatal(1,"corrected histogram bin 17");
if(dut.histogram[18]!==734)$fatal(1,"corrected histogram bin 18");
if(dut.histogram[19]!==741)$fatal(1,"corrected histogram bin 19");
if(dut.histogram[20]!==726)$fatal(1,"corrected histogram bin 20");
if(dut.histogram[21]!==730)$fatal(1,"corrected histogram bin 21");
if(dut.histogram[22]!==709)$fatal(1,"corrected histogram bin 22");
if(dut.histogram[23]!==695)$fatal(1,"corrected histogram bin 23");
if(dut.histogram[24]!==681)$fatal(1,"corrected histogram bin 24");
if(dut.histogram[25]!==664)$fatal(1,"corrected histogram bin 25");
if(dut.histogram[26]!==660)$fatal(1,"corrected histogram bin 26");
if(dut.histogram[27]!==641)$fatal(1,"corrected histogram bin 27");
if(dut.histogram[28]!==637)$fatal(1,"corrected histogram bin 28");
if(dut.histogram[29]!==642)$fatal(1,"corrected histogram bin 29");
if(dut.histogram[30]!==655)$fatal(1,"corrected histogram bin 30");
if(dut.histogram[31]!==416)$fatal(1,"corrected histogram bin 31");
 $display("PASS lens segmenter integration:24576 corrected pixels +32 histogram bins");$finish;
end
initial begin #12000000;$fatal(1,"timeout");end
endmodule