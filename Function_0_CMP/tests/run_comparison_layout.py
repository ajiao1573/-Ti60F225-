"""Check actual top-level display gates and RGB mux against the requested layout."""
from pathlib import Path
import re
from run_canny import simulate

top = Path('example_top.v').read_text(encoding='utf-8')
names = ['view_active','split_overlap_row', 'split_edge_only_row', 'split_stream_request',
         'overlay_left_pixel', 'overlay_pixel', 'history_play_pixel',
         'history_compare_row', 'history_compare_pixel', 'history_compare_discard',
         'history_compare_request','history_compare_take','display_stream_request', 'split_left_pixel', 'split_right_pixel',
         'lcd_split_data', 'history_pixel', 'display_rgb']
declarations=[]
for name in names:
 if name=='display_rgb':
  declarations.append('wire [23:0] display_rgb;'+re.search(r'assign display_rgb\s*=.*?;',top,re.S).group(0))
 else:
  declarations.append(re.search(r'wire\s+(?:\[[^\]]+\]\s+)?'+name+r'\s*=.*?;',top,re.S).group(0))
declarations='\n'.join(declarations)
assert '.OVERLAY_SINGLE(0)' in top
assert '.rframe_left(overlay_left_pixel)' in top
assert ".x(view_x-12'd432)" in top
tb = '''
module tb;
 reg [11:0] lcd_xpos,lcd_ypos;
 reg lcd_request=1,display_history=0,display_overlay=0,display_compare=0;
 reg [7:0] lcd_data=8'h35;
 reg [23:0] lcd_overlay_rgb=24'h123456;
 reg display_edge_wide=0;
 wire [11:0] view_x=(lcd_xpos*2)/3,view_y=(lcd_ypos*2)/3;
 wire view_request=lcd_request && lcd_xpos%3!=1 && lcd_ypos%3!=1;
 integer x,y,e,leftp,rightp,vx,vy;
 reg [23:0] expected;
''' + declarations + '''
 initial begin
  display_overlay=1;
  for(e=0;e<2;e=e+1) begin
   display_edge_wide=e;
   for(y=0;y<1080;y=y+1) begin
    for(x=0;x<1920;x=x+1) begin
     lcd_xpos=x;lcd_ypos=y;#1;
     vx=(x*2)/3;vy=(y*2)/3;
     leftp=(vy>=241 && vy<=478 && vx>=0 && vx<424);
     rightp=(vy>=121 && vy<=597 && vx>=432 && vx<1280);
     expected=leftp ? 24'h123456 : rightp ?
              (e ? 24'hff0000 : 24'h123456) : 24'd0;
     if(display_rgb!==expected || display_stream_request!==((leftp || rightp) && view_request)
        || overlay_left_pixel!==leftp[0])
      $fatal(1,"top comparison layout x=%0d y=%0d edge=%0d",x,y,e);
    end
   end
  end
  $display("PASS actual top layout: left original RGB, right red-edge overlay, black gap, 4147200 pixels across the full 1080p scaled canvas");
  $finish;
 end
endmodule
'''
simulate('comparison_layout', tb, [], timeout=120)
