from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def edit(name, replacements):
 p=ROOT/name;s=p.read_text(encoding='utf-8')
 for a,b in replacements:
  assert a in s,(name,a)
  s=s.replace(a,b)
 p.write_text(s,encoding='utf-8')

# Dedicated 960-wide controller. Both RGB panes read the same stored source;
# there is no second RGB plane and therefore no overlapping memory allocation.
edit('src/axi/split_frame_ctrl.v',[
 ('EDGE_LINES=636,GRAY_LINES=318','EDGE_LINES=720,GRAY_LINES=720'),
 ("EDGE_BEATS=8'd53,GRAY_BEATS=8'd27","EDGE_BEATS=8'd60,GRAY_BEATS=8'd60"),
 ('localparam EDGE_DISPLAY_TOP=42+LETTERBOX_TOP;','localparam EDGE_DISPLAY_TOP=180;'),
 ('localparam GRAY_DISPLAY_TOP=201+(LETTERBOX_TOP+1)/2;','localparam GRAY_DISPLAY_TOP=180;'),
 ('[895:0]','[1023:0]'),('index<848','index<960'),
 ('reg [8:0] left_write_line','reg [9:0] left_write_line'),
 ('reg [8:0] gray_write_line','reg [9:0] gray_write_line'),
 ('reg [8:0] gray_read_line','reg [9:0] gray_read_line'),
 ("rgb_write_half ? 10'd84", "rgb_write_half ? 10'd112"),
 ('wire left_ready=COLOR_ENABLE && left_write_line<GRAY_LINES && left_fifo_count>=106;', 'wire left_ready=1\'b0; // Full-size left RGB reuses RGB_BASE.'),
 ('rgb_write_line==EDGE_LINES && left_write_line==GRAY_LINES','rgb_write_line==EDGE_LINES'),
 ("rgb_write_half ? 8'd96", "rgb_write_half ? 8'd112"),
 ("choose_gray ? 8'd32 : 8'd64", "choose_gray ? 8'd64 : 8'd64"),
 ('rgb_write_half ? 84 : 128','rgb_write_half ? 112 : 128'),
 ("(write_beat==6 ? {48'd0,history_row[768+:80]} : history_row[write_beat*128+:128])", "(write_beat==7 ? {64'd0,history_row[896+:64]} : history_row[write_beat*128+:128])"),
 ('axi_awlen<=6;', 'axi_awlen<=7;'),
 ('wire last_word=write_beat==52;', 'wire last_word=write_beat==59;'),
 ("{48'd0,packed_protect,pack[127:64]}", "{64'd0,packed_protect,pack[127:80]}"),
 ("wire [8:0] history_bit_base=read_compare ? {history_group,5'b0} : {1'b0,history_group,4'b0};", "wire [8:0] history_bit_base={1'b0,history_group,4'b0};"),
 ('history_bit_base+(read_compare ? 2*px : px)','history_bit_base+px'),
 ('(history_beat<6 || bit_index<80)','(history_beat<7 || bit_index<64)'),
 ('read_left ? LEFT_RGB_BASE+{gray_read_line,11\'d0} : RGB_BASE+{edge_read_line,12\'d0}+','RGB_BASE+{edge_read_line,12\'d0}+'),
 ("(read_left ? 8'd112 : read_rgb ? (read_rgb_half ? 8'd96 : 8'd128) :\n  read_gray ? 8'd32 : 8'd64)", "(read_rgb ? (read_rgb_half ? 8'd112 : 8'd128) : 8'd64)"),
 ('(history_beat==6 ? (read_compare ? 2 : 4) : (read_compare ? 3 : 7))','(history_beat==7 ? 3 : 7)'),
 ('read_beat==6 ? history_row[768+:80]!=previous_vote[79:0]', 'read_beat==7 ? history_row[896+:64]!=previous_vote[63:0]'),
 ('(read_left ? read_beat<106 : read_rgb ? read_beat<(read_rgb_half ? 84 : 128) : (read_gray ? read_beat<GRAY_BEATS : read_beat<EDGE_BEATS))', '(read_rgb ? read_beat<(read_rgb_half ? 112 : 128) : (read_gray ? read_beat<GRAY_BEATS : read_beat<EDGE_BEATS))'),
 ("read_history ? 8'd6", "read_history ? 8'd7"),
 ('history_line+(read_compare ? 2 : 1)','history_line+1\'b1'),
 ('gray_read_line<=gray_read_line+1\'b1;read_left<=0;read_rgb<=1;read_rgb_half<=0;read_beat<=0;rstate<=R_ADDR;', "read_beat<=0;\n     if(!read_rgb_half) read_rgb_half<=1;\n     else begin gray_read_line<=gray_read_line+1'b1;read_left<=0;read_rgb<=1;read_rgb_half<=0;end\n     rstate<=R_ADDR;"),
 ('R_TADDR:begin axi_arlen<=6;', 'R_TADDR:begin axi_arlen<=7;'),
 ('.wr_en_i(left_rgb_data_en)', ".wr_en_i(1'b0)")
])
edit('example_top.v',[
 ('ov5640_dvp u_ov5640_dvp', 'ov5640_dvp #(.WIDTH(960),.HEIGHT(720)) u_ov5640_dvp'),
 ('.IMAGE_HSIZE_SOURCE (1920)', '.IMAGE_HSIZE_SOURCE (960)'),
 ('.IMAGE_VSIZE_SOURCE (1080)', '.IMAGE_VSIZE_SOURCE (720)'),
 ('.IMAGE_HSIZE_TARGET (1920 / CSI_STRB_WIDTH)', '.IMAGE_HSIZE_TARGET (960 / CSI_STRB_WIDTH)'),
 ('.IMAGE_YSIZE_TARGET (1080 \t )', '.IMAGE_YSIZE_TARGET (720 \t )'),
 ('.IMG_HDISP(1920)', '.IMG_HDISP(960)'),('.IMG_VDISP(1080)', '.IMG_VDISP(720)'),
 ('camera_rgb_smooth u_camera_rgb_smooth', 'camera_rgb_smooth #(.WIDTH(960),.HEIGHT(720)) u_camera_rgb_smooth'),
 ('camera_full_view #(.HEIGHT(477),.IMAGE_H(477),.FIFO_BITS(5))', 'camera_full_view #(.IN_W(960),.IN_H(720),.WIDTH(960),.HEIGHT(720),.IMAGE_H(720),.FIFO_BITS(6),.LINE_GAP(12))'),
 ('.WIDTH(848),.HEIGHT(477)', '.WIDTH(960),.HEIGHT(720)'),
 ('wire gray_sample_en=thumbnail_valid;', 'wire gray_sample_en=rgb_store_en;'),
 ('wire gray_store_en=gray_sample_en || gray_pad_count!=0;', 'wire gray_store_en=gray_sample_en;'),
 ("wire [7:0] gray_store_data=gray_sample_en ? thumbnail_gray_sum[9:2]:8'h00;", 'wire [7:0] gray_store_data=gray_data;'),
 ('.left_rgb_data_en(thumbnail_valid)', ".left_rgb_data_en(1'b0)"),
 ('.EDGE_LINES(477),.GRAY_LINES(238),.LETTERBOX_TOP(79)', '.EDGE_LINES(720),.GRAY_LINES(720),.LETTERBOX_TOP(0)'),
 ('.HISTORY_COMPARE_NATIVE(1)', '.HISTORY_COMPARE_NATIVE(0)'),
 ('.WIDTH(848)) u_edge_display_width2', '.WIDTH(960)) u_edge_display_width2'),
 (".x(view_x-12'd432),.y(view_y-12'd121)", ".x(view_x-12'd960),.y(view_y-12'd180)"),
 ('CLOCK_HZ(74250000)', 'CLOCK_HZ(148500000)'),
 ('reg [22:0] cam_idle;', 'reg [23:0] cam_idle;'),
 ('7425000', '14850000')
])
p=ROOT/'example_top.v';s=p.read_text(encoding='utf-8')
a=s.index('    // Present the existing 1280x720');b=s.index('\n\tsplit_frame_ctrl #',a)
s=s[:a]+'''    // Native pixels: two 960x720 panes, with 180-line status margins.
    wire view_active=lcd_xpos<1920 && lcd_ypos<1080;
    wire [11:0] view_x=lcd_xpos,view_y=lcd_ypos;
    wire view_request=lcd_request;
    wire [23:0] display_rgb;
    wire [23:0] scaled_image_rgb=display_rgb;
    wire split_overlap_row=view_y>=180 && view_y<900;
    wire split_stream_request=view_request && split_overlap_row && view_x<1920;
    wire [23:0] lcd_overlay_rgb;
    wire overlay_left_pixel=split_overlap_row && view_x<960;
    wire overlay_pixel=split_overlap_row && view_x>=960 && view_x<1920;
    wire history_play_pixel=split_overlap_row && view_x>=480 && view_x<1440;
    wire history_compare_pixel=split_overlap_row && view_x<1920;
    wire display_stream_request=view_active && (display_history ?
      (view_request && (display_compare ? history_compare_pixel : history_play_pixel)) : split_stream_request);
''' +s[b:]
a=s.index('\twire split_left_pixel =');b=s.index('    wire display_edge_wide;',a)
s=s[:a]+'''    wire split_left_pixel=overlay_left_pixel;
    wire split_right_pixel=overlay_pixel;
'''+s[b:]
p.write_text(s,encoding='utf-8')
edit('Ti60_Demo.peri.xml',[
 ('name="clk_pixel" number="1" out_divider="40"','name="clk_pixel" number="1" out_divider="20"'),
 ('name="clk_pixel_2x" number="2" out_divider="20"','name="clk_pixel_2x" number="2" out_divider="10"'),
 ('is_half_rate="false" is_serial="true" serial_width="10"','is_half_rate="true" is_serial="true" serial_width="10"')
])
edit('src/lcd_para.v',[('VGA_1920_1080_30FPS_74_25MHz','VGA_1920_1080_60FPS_148_5MHz')])
print('960-wide source changes applied; camera timing and validation still pending')
