"""Check actual top gates for all modes and the exact previous content bounds."""
from pathlib import Path
import re
from run_canny import simulate
s=Path('example_top.v').read_text(encoding='utf-8')
names=['view_active','split_overlap_row','split_edge_only_row','split_stream_request',
 'overlay_left_pixel','overlay_pixel','history_play_pixel','history_compare_row',
 'history_compare_pixel','history_compare_discard','history_compare_request',
 'history_compare_take','display_stream_request','split_left_pixel','split_right_pixel',
 'lcd_split_data','history_pixel']
decl='\n'.join(re.search(r'wire\s+(?:\[[^\]]+\]\s+)?'+n+r'\s*=.*?;',s,re.S).group(0) for n in names)
decl+='\nwire [23:0] display_rgb;'+re.search(r'assign display_rgb\s*=.*?;',s,re.S).group(0)
assert '.EDGE_LINES(477),.GRAY_LINES(238),.LETTERBOX_TOP(79)' in s
assert s.count('.WIDTH(848),.HEIGHT(477)')==2
tb=r'''
module tb;
 reg [11:0] lcd_xpos,lcd_ypos;
 reg lcd_request=1,display_history=0,display_overlay=0,display_compare=0;
 reg [7:0] lcd_data=8'h35;reg [23:0] lcd_overlay_rgb=24'h123456;
 reg display_edge_wide=0;reg [7:0] status_display=0;wire [23:0] plate_display_rgb=0;
 wire [11:0] view_x=(lcd_xpos*2)/3,view_y=(lcd_ypos*2)/3;
 wire view_request=lcd_request && lcd_xpos%3!=1 && lcd_ypos%3!=1;
 integer mode,x,y,vx,vy,n=0,takes,leftp,rightp,playp,compp,padp,overlap;
 reg expected_take;reg [23:0] expected;
''' +decl+r'''
 initial begin
  for(mode=0;mode<4;mode=mode+1) begin
   display_history=mode>=2;display_compare=mode==3;display_overlay=mode==1;takes=0;
   for(y=0;y<1080;y=y+1) for(x=0;x<1920;x=x+1) begin
    lcd_xpos=x;lcd_ypos=y;display_edge_wide=(x+y)%2;#1;
    vx=2*x/3;vy=2*y/3;
    // The previous padded view sampled even canvas rows 80..554 on the left,
    // and pooled canvas rows 78/79..554/555 in historical comparisons.
    leftp=vy>=241 && vy<=478 && vx<424;
    rightp=vy>=121 && vy<=597 && vx>=432;
    playp=vy>=163 && vy<=639 && vx>=216 && vx<1064;
    compp=vy>=240 && vy<=478 && ((vx>=206 && vx<630)||(vx>=650 && vx<1074));
    padp=vy>=240 && vy<=478 && ((vx>=630 && vx<638)||(vx>=1074 && vx<1082));
    overlap=vy>=241 && vy<=478;
    case(mode)
     0:begin expected=leftp ? 24'h353535 : rightp && display_edge_wide ? 24'hffffff : 0;
       expected_take=view_request && (overlap || rightp);end
     1:begin expected=leftp ? 24'h123456 : rightp ? (display_edge_wide ? 24'hff0000 : 24'h123456) : 0;
       expected_take=view_request && (leftp || rightp);end
     2:begin expected=playp ? 24'h353535 : 0;expected_take=view_request && playp;end
     3:begin expected=compp ? 24'h353535 : 0;expected_take=view_request && (compp || padp);end
    endcase
    if(display_rgb!==expected || display_stream_request!==expected_take)
     $fatal(1,"layout/read mismatch mode=%0d x=%0d y=%0d rgb=%h expected=%h",mode,x,y,display_rgb,expected);
    takes=takes+display_stream_request;n=n+1;
   end
   case(mode)
    0:if(takes!=507312) $fatal(1,"gray takes %d",takes);
    1:if(takes!=505408) $fatal(1,"color takes %d",takes);
    2:if(takes!=404496) $fatal(1,"replay takes %d",takes);
    3:if(takes!=206496) $fatal(1,"compare takes %d",takes);
   endcase
  end
  $display("PASS actual top 1080p: %0d coordinates, gray/edge, color/red, replay, dual compare, exact old black boundaries, no DDR reads for black rows",n);$finish;
 end
endmodule
'''
simulate('display_letterbox_layout',tb,[],timeout=180)
