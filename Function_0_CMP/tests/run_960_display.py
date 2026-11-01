"""Actual HDMI raster plus top-level pane geometry and OSD exclusion bounds."""
from pathlib import Path
from run_canny import simulate
import ast
source=Path('tests/run_ov5640_video.py').read_text()
call=next(n.value for n in ast.parse(source).body if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and getattr(n.value.func,'id','')=='simulate')
tb=call.args[1].left.value
tb=tb.replace('#6.734','#3.367003').replace('1080p30','1080p60').replace('74250000/(2200*1125)=30','148500000/(2200*1125)=60')
top=Path('example_top.v').read_text(encoding='utf-8')
geometry=top[top.index('    // Native pixels:'):top.index('\n\tsplit_frame_ctrl #')]
tb=tb.replace(' integer n=0,', '''wire[11:0] lcd_xpos=x,lcd_ypos=y;wire lcd_request=req;
 reg display_history=0,display_compare=0;
 wire ca,sa,ta,fa,ua,za,sha;
 camera_status_osd camera(.x_pos(x),.y_pos(y),.ready(1'b1),.failed(1'b0),.size_error(1'b0),.pclk_alive(1'b1),.chip_id(16'h5640),.config_index(9'd267),.input_fps(10'd60),.width(12'd960),.height(12'd720),.active(ca));
 video_status_osd #(.X_START(32),.Y_START(80)) status(.x_pos(x),.y_pos(y),.gear(3'd1),.algorithm(3'd3),.overlay(1'b0),.history(1'b0),.compare(1'b0),.active(sa));
 threshold_osd #(.X_START(32),.Y_START(24)) threshold(.x_pos(x),.y_pos(y),.threshold(10'd47),.fps(10'd60),.pixel_in(8'd0),.osd_active(ta));
 threshold_osd #(.X_START(1040),.Y_START(24),.LABEL_KIND(2)) frames(.x_pos(x),.y_pos(y),.threshold(10'd0),.fps(10'd7),.pixel_in(8'd0),.osd_active(fa));
 threshold_osd #(.X_START(1200),.Y_START(24),.LABEL_KIND(4)) underflow(.x_pos(x),.y_pos(y),.threshold(10'd0),.fps(10'd0),.pixel_in(8'd0),.osd_active(ua));
 video_status_osd #(.X_START(608),.Y_START(24),.STATE_ONLY(1)) frozen(.x_pos(x),.y_pos(y),.gear(3'd3),.history(1'b1),.frozen(1'b1),.frame_count(4'd8),.active(za));
 shape_osd #(.X_START(848),.Y_START(1020)) shape(.x_pos(x),.y_pos(y),.shape(2'd2),.active(sha));
 '''+geometry+'''
 integer left_pixels=0,right_pixels=0,play_pixels=0,compare_pixels=0,osdpixels=0;
 integer n=0,''')
tb=tb.replace('requests=requests+1;', '''if(overlay_left_pixel) left_pixels=left_pixels+1;
    if(overlay_pixel) right_pixels=right_pixels+1;
    if(history_play_pixel) play_pixels=play_pixels+1;
    if(history_compare_pixel) compare_pixels=compare_pixels+1;
    if(ca || sa || ta || fa || ua || za || sha) begin
     osdpixels=osdpixels+1;
     if(y>=180 && y<900) $fatal(1,"OSD covers image");
     if(integer'(ca)+integer'(sa)+integer'(ta)+integer'(fa)+integer'(ua)+integer'(za)+integer'(sha)>1) $fatal(1,"OSD boxes overlap");
    end
    requests=requests+1;''')
tb=tb.replace('  $display("PASS HDMI', '''  if(left_pixels!=960*720 || right_pixels!=960*720 || play_pixels!=960*720 || compare_pixels!=1920*720 || osdpixels==0) $fatal(1,"pane pixel totals");
  $display("PASS native panes960x720, no scaling, complete replay/compare geometry and non-overlapping OSD in margins");
  $display("PASS HDMI''')
tb+=Path('src/lcd_driver.v').read_text().replace('`include "lcd_para.v"','`include "src/lcd_para.v"')
simulate('960_display',tb,['src/threshold_osd.v','src/camera_status_osd.v','src/video_status_osd.v','src/shape_osd.v'],timeout=300)
