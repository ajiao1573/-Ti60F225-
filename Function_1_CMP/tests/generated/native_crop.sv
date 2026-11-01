`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,en=1,v=0,s=0,e=0,candidate=0,accept=1;
reg [10:0] x=0,rx=0,rw=0;reg [10:0] y=0,ry=0,rh=0;
reg [7:0] gray=0;
wire hold;wire[5:0] stage;wire locked,good;wire[10:0] captured_x,captured_w;wire[10:0] captured_y,captured_h;
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.ENABLE_NZ_OCR(1),.ADAPTIVE_THRESHOLD(1),.MIN_HEIGHT(12)) dut(
.clk(clk),.rst_n(rst),.enable(en),.in_valid(v),.in_sop(s),.in_eop(e),.in_x(x),.in_y(y),.in_gray(gray),.adjust(8'd128),
.pixel_clk(clk),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),
.accept_frame(accept),.snapshot_ready(1'b1),.capture_hold(hold),
.candidate_valid(candidate),.roi_x(rx),.roi_y(ry),.roi_width(rw),.roi_height(rh),
.cam_state(stage),.cam_locked(locked),.cam_valid(good),.captured_x(captured_x),.captured_y(captured_y),.captured_width(captured_w),.captured_height(captured_h));
integer tag=0,expected_x,expected_y,expected_w,expected_h;
integer checked=0,active=0,cases=0,px,py,sx,sy,addr,want,bin,b,mins[0:31],maxs[0:31],hist[0:31];
function integer value;
input integer xx,yy,ff;
begin value=(xx*11+yy*17+ff*29)&255;end
endfunction
always @(posedge clk) if(rst && active && stage==3 && !checked) begin
 #1;
 if(captured_x!=expected_x || captured_y!=expected_y || captured_w!=expected_w || captured_h!=expected_h)
  $fatal(1,"candidate lock changed during frame");
 if(!hold || good || locked) $fatal(1,"capture/recognition state invalid");
 for(b=0;b<32;b=b+1)begin hist[b]=0;mins[b]=255;maxs[b]=0;end
 for(py=0;py<96;py=py+1)for(px=0;px<256;px=px+1)begin
  sx=expected_x+(px*expected_w)/256;sy=expected_y+(py*expected_h)/96;
  want=value(sx,sy,tag);addr=(dut.bank ? 24576:0)+py*256+px;
  if(dut.roi_mem[addr]!==want[7:0])$fatal(1,"crop case%0d dest%0d,%0d source%0d,%0d got%0d want%0d",tag,px,py,sx,sy,dut.roi_mem[addr],want);
  if(px>=4 && px<252 && py>=4 && py<92)begin
   bin=want>>3;hist[bin]=hist[bin]+1;b=(py/32)*8+px/32;
   if(want<mins[b])mins[b]=want;if(want>maxs[b])maxs[b]=want;
  end
 end
 for(b=0;b<32;b=b+1)begin
  if(dut.histogram[b]!==hist[b][15:0])$fatal(1,"normalized histogram case%0d bin%0d got%0d want%0d",tag,b,dut.histogram[b],hist[b]);
  if(dut.tile_min[b*8+:8]!==mins[b][7:0] || dut.tile_max[b*8+:8]!==maxs[b][7:0])$fatal(1,"normalized extrema case%0d tile%0d",tag,b);
 end
 checked=1;cases=cases+1;$display("crop%0d PASS x%0d y%0d size%0dx%0d",tag,expected_x,expected_y,expected_w,expected_h);
end
task reset_case;
begin
 rst=0;v=0;s=0;e=0;candidate=0;checked=0;active=0;en=1;accept=1;
 repeat(6)@(negedge clk);rst=1;wait(stage==1);@(negedge clk);
end
endtask
task run_case;
input integer xx,yy,ww,hh,fw,fh,ff;
integer a,b,n;
begin
 reset_case;tag=ff;expected_x=xx;expected_y=yy;expected_w=ww;expected_h=hh;
 rx=xx;ry=yy;rw=ww;rh=hh;candidate=1;active=1;n=0;
 for(b=0;b<fh;b=b+1)for(a=0;a<fw;a=a+1)begin
  x=a;y=b;v=1;s=a==0&&b==0;e=a==fw-1&&b==fh-1;gray=value(a,b,ff);
  @(negedge clk);n=n+1;
  if(n==20)begin rx=0;ry=0;rw=2;rh=2;candidate=0;end
  if(n%19==0 || a==fw-1)begin v=0;s=0;e=0;repeat(2)@(negedge clk);end
 end
 v=0;s=0;e=0;
 n=0;while(!checked && n<100000)begin @(negedge clk);n=n+1;end
 if(!checked)$fatal(1,"normalization timeout case%0d state%0d",ff,stage);
end
endtask
integer i;
initial begin
 run_case(1650,1040,128,32,1920,1080,9);
 // No candidate or unaccepted source SOP may reserve capture.
 reset_case;rw=128;rh=40;rx=3;ry=4;candidate=0;v=1;s=1;x=0;y=0;
 @(negedge clk);v=0;s=0;repeat(10)@(negedge clk);
 if(stage!=1 || hold)$fatal(1,"empty candidate captured");
 candidate=1;accept=0;v=1;s=1;@(negedge clk);v=0;s=0;repeat(10)@(negedge clk);
 if(stage!=1 || hold)$fatal(1,"unaccepted frame captured");
 // Truncated frame before the final crop sample must release and clear.
 accept=1;v=1;s=1;x=0;y=0;@(negedge clk);s=0;
 x=3;y=4;gray=88;@(negedge clk);
 x=159;y=39;e=1;@(negedge clk);v=0;e=0;candidate=0;
 repeat(50)@(negedge clk);
 if(stage!=1 || hold || good)$fatal(1,"truncated frame remained reserved stage%0d",stage);
 // Cancellation clears capture and stale recognition immediately.
 v=1;s=1;candidate=1;@(negedge clk);v=0;s=0;en=0;
 repeat(5)@(negedge clk);if(stage!=0 || hold || good)$fatal(1,"cancel did not clear");
 $display("PASS native1080 ROI:y1040..1071 pixel-exact source crop, normalized histogram/extrema, SOP origin, candidate locking, gaps, missing/invalid acceptance, truncation and cancel");$finish;
end
initial begin #90000000;$fatal(1,"global dynamic crop timeout");end
endmodule
