"""Single ROI/mask bank: real dynamic normalization -> OCR -> DDR freeze.

The pixel clock is intentionally stopped: legacy ROI display acknowledgement
must not gate a transaction after those displays and their RAM ports are gone.
The full-frame snapshot/commit acknowledgement must still gate publication.
"""
from PIL import Image
from plate_reference import sample
from run_canny import simulate,OUT

cases=[Image.new('L',(256,96),190),sample('BKT682',size=52),sample('ZX1470',size=52),sample('ABCXYZ',size=52),sample('DMN112',negative=True,size=52)]
(OUT/'single_roi_lock_input.hex').write_text(''.join(f'{v:02x}\n' for im in cases for v in im.tobytes()))
tb=r'''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,en=0,v=0,s=0,e=0,accepted=0,snapshot=0;
reg[10:0]x=0,rx=3;reg[9:0]y=0,ry=2;reg[7:0]gray=0;
wire hold,locked,valid,result_toggle;wire[47:0]ascii;wire[5:0]stage;wire[2:0]reason;wire[3:0]count;
wire[23:0]pixel;wire[10:0]cx,cw;wire[9:0]cy,ch;
plate_segmenter #(.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),.ENABLE_NZ_OCR(1),.ADAPTIVE_THRESHOLD(1),.BLACK_INK(1),.MIN_HEIGHT(12)) dut(
.clk(clk),.rst_n(rst),.enable(en),.in_valid(v),.in_sop(s),.in_eop(e),.in_x(x),.in_y(y),.in_gray(gray),.adjust(8'd128),
.candidate_valid(1'b1),.roi_x(rx),.roi_y(ry),.roi_width(11'd256),.roi_height(10'd96),
.accept_frame(accepted),.snapshot_ready(snapshot),.capture_hold(hold),
.pixel_clk(1'b0),.pixel_rst_n(rst),.vsync(1'b0),.x_pos(12'd0),.y_pos(12'd0),.pixel(pixel),
.cam_state(stage),.cam_locked(locked),.cam_valid(valid),.cam_ascii(ascii),.cam_reject(reason),.cam_count(count),.cam_result_toggle(result_toggle),
.captured_x(cx),.captured_y(cy),.captured_width(cw),.captured_height(ch));
reg[7:0]images[0:122879];integer xx,yy;reg seen;reg[47:0]old_ascii;
always @(posedge clk)if(rst)begin
 if(dut.bank!==0)$fatal(1,"single mode changed bank");
 if(locked&&dut.capture_write)$fatal(1,"wrote into locked single bank");
 if(pixel!==24'd0)$fatal(1,"disabled ROI display generated pixels");
end
task rearm;begin
 @(negedge clk);en=0;v=0;s=0;e=0;accepted=0;repeat(8)@(negedge clk);en=1;
 wait(stage==1);@(negedge clk);
 if(locked||valid||hold||ascii!==48'h3f3f3f3f3f3f)$fatal(1,"stale result after single-bank rearm");
end endtask
task source(input integer index);begin
 wait(stage==1);@(negedge clk);v=1;s=1;accepted=1;x=0;y=0;gray=200;
 @(negedge clk);s=0;accepted=0;
 if(!hold)$fatal(1,"single mode failed to reserve capture");
 for(yy=0;yy<96;yy=yy+1)for(xx=0;xx<256;xx=xx+1)begin
  x=xx+3;y=yy+2;gray=images[index*24576+yy*256+xx];e=xx==255&&yy==95;
  @(negedge clk);
 end
 v=0;e=0;
end endtask
task expect_plate(input integer index,input[47:0]word);begin
 seen=result_toggle;snapshot=0;source(index);wait(stage==21);
 repeat(100)@(negedge clk);
 if(stage!=21||!hold||valid||result_toggle!=seen)$fatal(1,"single mode bypassed full-frame snapshot_ready");
 snapshot=1;wait(locked);@(negedge clk);
 if(!valid||ascii!==word||reason!=0||count!=6||result_toggle==seen)$fatal(1,"single OCR got%s valid%b reason%0d count%0d expected%s",ascii,valid,reason,count,word);
 if(cx!=3||cy!=2||cw!=256||ch!=96)$fatal(1,"single capture frame bbox");
 if(dut.thumb_mem[0]!==1'bx)$fatal(1,"single mode still writes unused thumbnail RAM");
 old_ascii=ascii;repeat(20)begin v=1;s=1;accepted=1;x=0;y=0;gray=0;@(negedge clk);v=0;s=0;accepted=0;@(negedge clk);end
 if(!locked||ascii!==old_ascii)$fatal(1,"live stream replaced frozen single-bank result");
end endtask
initial begin
 $readmemh("tests/generated/single_roi_lock_input.hex",images);
 repeat(8)@(negedge clk);rst=1;en=1;wait(stage==1);
 if($size(dut.roi_mem)!=24576||$size(dut.mask_mem)!=49152)$fatal(1,"single bank array size");
 snapshot=1;seen=result_toggle;source(0);wait(result_toggle!=seen);wait(stage==1);
 if(locked||valid||hold||reason!=1)$fatal(1,"single blank failed to release %0d",reason);
 expect_plate(1,"BKT682");rearm;expect_plate(2,"ZX1470");
 rearm;snapshot=1;seen=result_toggle;source(3);wait(result_toggle!=seen);wait(stage==1);
 if(locked||valid||hold||reason==0)$fatal(1,"invalid text accepted or retained freeze");
 rearm;snapshot=1;seen=result_toggle;source(4);wait(result_toggle!=seen);wait(stage==1);
 if(locked||valid||hold)$fatal(1,"inverse plate accepted");
 // A valid but uncommitted result may be cancelled without pixel-domain ack.
 rearm;snapshot=0;source(1);wait(stage==21);rearm;snapshot=1;
 repeat(40)@(negedge clk);if(locked||valid)$fatal(1,"cancelled result resurrected");
 expect_plate(2,"ZX1470");
 $display("PASS single-buffer dynamic OCR:half ROI/mask RAM,no thumbnail writes or pixel clock dependence,both NZ formats,full-frame commit wait,blank/invalid/inverse rejection,frozen-write protection,rearm and cancelled-result recovery");$finish;
end
initial begin #120000000;$fatal(1,"single ROI lock timeout state%0d candidate%b",stage,dut.work_candidate);end
endmodule
'''
simulate('single_roi_lock',tb,['src/plate_segmenter.v'],timeout=240)
