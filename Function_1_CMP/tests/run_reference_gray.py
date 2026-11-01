from pathlib import Path
from run_canny import ROOT,OUT,simulate
s=(ROOT/'example_top.v').read_text(encoding='utf-8');a=s.index('wire thumbnail_valid,');b=s.index('wire split_store_eof=',a);fragment=s[a:b]
tb=r'''@TICK@timescale 1ns/1ps
module tb;
 reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;reg rstn_sys=0,rgb_store_en=0;
 reg[10:0] full_view_x=0,full_view_y=0;reg[23:0] camera_rgb=0;wire[7:0] canny_gray_data=42;
 @FRAGMENT@
 integer count=0,rgbcount=0,x,y,f,index,cx,cy,channel,pixelval,rr,gg,bb,expectgray;reg[23:0] expected;
 reg collecting=0;
 function integer color;
 input integer xx,yy,ff,cc;
 begin
  case(cc)
   0:color=(xx+3*yy+7*ff)&255;
   1:color=(2*xx+yy+11*ff)&255;
   default:color=(xx+2*yy+17*ff)&255;
  endcase
 end
 endfunction
 always @(posedge cmos_pclk) if(rstn_sys) begin
 if(thumbnail_valid) begin
 if(!collecting) $fatal(1,"rejected frame leaked");
 cx=2*(rgbcount%424);cy=2*(rgbcount/424);
 rr=(color(cx,cy,f,0)+color(cx+1,cy,f,0)+color(cx,cy+1,f,0)+color(cx+1,cy+1,f,0)+2)/4;
 gg=(color(cx,cy,f,1)+color(cx+1,cy,f,1)+color(cx,cy+1,f,1)+color(cx+1,cy+1,f,1)+2)/4;
 bb=(color(cx,cy,f,2)+color(cx+1,cy,f,2)+color(cx,cy+1,f,2)+color(cx+1,cy+1,f,2)+2)/4;
 if(thumbnail_rgb!=={8'(rr),8'(gg),8'(bb)}) $fatal(1,"averaged RGB %0d",rgbcount);
 rgbcount=rgbcount+1;end
 if(gray_store_en) begin
 if(!collecting) $fatal(1,"unaccepted gray");
 index=count%432;cx=2*index;cy=2*(count/432);
 rr=(color(cx,cy,f,0)+color(cx+1,cy,f,0)+color(cx,cy+1,f,0)+color(cx+1,cy+1,f,0)+2)/4;
 gg=(color(cx,cy,f,1)+color(cx+1,cy,f,1)+color(cx,cy+1,f,1)+color(cx+1,cy+1,f,1)+2)/4;
 bb=(color(cx,cy,f,2)+color(cx+1,cy,f,2)+color(cx,cy+1,f,2)+color(cx+1,cy+1,f,2)+2)/4;
 expectgray=index<424 ? (rr+2*gg+bb)/4:0;
 if(gray_store_data!==8'(expectgray)) $fatal(1,"gray/pad %0d got=%d expected=%d",count,gray_store_data,expectgray);
 count=count+1;end
 end
 initial begin
 repeat(8) @(negedge cmos_pclk);rstn_sys=1;
 for(f=0;f<2;f=f+1) begin
 count=0;rgbcount=0;collecting=1;
 for(y=0;y<477;y=y+1) begin
 for(x=0;x<848;x=x+1) begin
 @(negedge cmos_pclk);rgb_store_en=1;full_view_x=x;full_view_y=y;
 camera_rgb={8'(color(x,y,f,0)),8'(color(x,y,f,1)),8'(color(x,y,f,2))};
 if(x%31==30) begin @(negedge cmos_pclk);rgb_store_en=0;end
 end
 @(negedge cmos_pclk);rgb_store_en=0;repeat(12) @(negedge cmos_pclk);
 end
 repeat(12) @(negedge cmos_pclk);collecting=0;
 if(count!=238*432 || rgbcount!=238*424) $fatal(1,"bad count %0d %0d",count,rgbcount);
 end
 repeat(900) begin @(negedge cmos_pclk);full_view_x=full_view_x+1;camera_rgb=~camera_rgb;end
 $display("PASS current common-gray reference: two 848x477 frames, exact 2x2 RGB average, 424x238 plus 8 pad/row, unpaired last row dropped, valid gaps and rejected-frame gate");$finish;
 end
endmodule'''
simulate('reference_gray',tb.replace('@TICK@',chr(96)).replace('@FRAGMENT@',fragment),['src/video_thumbnail2.v'],timeout=180)
