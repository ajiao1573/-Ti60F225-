`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0;integer i,c;reg [7:0] source[0:24575];wire [5:0] stage;wire valid,toggle;wire [47:0] word;wire [3:0] count;wire [2:0] reason;
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.LENS_CORRECTION(1),.ENABLE_NZ_OCR(1),.ADAPTIVE_THRESHOLD(1),.NZ_BLACK_ONLY(1),.FLAT_TILE_FALLBACK(1),.MIN_HEIGHT(12))dut(
 .clk(clk),.rst_n(rst),.enable(1'b1),.in_valid(1'b0),.in_sop(1'b0),.in_eop(1'b0),.in_x(11'd0),.in_y(11'd0),.in_gray(8'd0),.adjust(8'd128),
 .pixel_clk(clk),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),.accept_frame(1'b1),.snapshot_ready(1'b1),
 .candidate_valid(1'b0),.roi_x(11'd0),.roi_y(11'd0),.roi_width(11'd0),.roi_height(11'd0),
 .cam_state(stage),.cam_valid(valid),.cam_ascii(word),.cam_count(count),.cam_reject(reason),.cam_result_toggle(toggle));
initial begin
 $readmemh("tests/generated/lens_distorted_AUY359.hex",source);
 for(c=0;c<3;c=c+1)begin
 rst=0;repeat(4)@(negedge clk);rst=1;
 wait(stage==1);@(negedge clk);
 for(i=0;i<24576;i=i+1)dut.roi_mem[i]=c==0 ? source[i] : c==1 ? 200 : 30;
 dut.captured_x=640;dut.captured_y=420;dut.captured_width=640;dut.captured_height=192;dut.state=54;
 wait(toggle);repeat(3)@(negedge clk);
 if(!dut.lens_retry)$fatal(1,"bounded original-frame retry was not exercised");
 if(c==0)begin
  if(!valid || word!=="AUY359" || count!=6)$fatal(1,"distorted fixture OCR got %s valid%0d count%0d reject%0d",word,valid,count,reason);
  for(i=0;i<24576;i=i+1)if(dut.roi_mem[i]!==source[i])$fatal(1,"original-frame retry lost pixel %d",i);
 end else if(valid || reason==0)$fatal(1,"blank/solid accepted");
 end
 $display("PASS measured-lens AUY359:corrected rejection -> exact original-frame retry -> AUY359;blank/solid rejected,bounded retry");$finish;
end
initial begin #50000000;$fatal(1,"timeout stage%0d",stage);end
endmodule