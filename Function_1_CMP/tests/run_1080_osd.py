from run_canny import simulate

tb=r'''
module tb;
 localparam FW=3;
 reg [11:0] lcd_xpos,lcd_ypos;
 wire view_active=lcd_xpos<1920 && lcd_ypos<1080;
 wire [23:0] scaled_image_rgb=24'h123456;
 wire [11:0] status_x=lcd_xpos,status_y=lcd_ypos;
 reg display_history=0,display_compare=0,display_overlay=0;
 reg [7:0] status_display=8'h60;
 reg [2:0] display_replay=7,display_left=0,display_right=7;
 reg [3:0] count_pixel_display=8;
 reg [9:0] canny_threshold_pixel=72,canny_fps_osd=30,history_underflow_frame=0,history_underflow_total=0;
 reg [1:0] shape_display=1;
 reg [7:0] lcd_split_data=0;wire [23:0] display_rgb=24'h123456;
 wire [7:0] lcd_split_data_with_osd,frame_pixel,underflow_pixel;
 wire [23:0] status_rgb,freeze_rgb,shape_rgb,camera_osd_rgb;
 wire osd_active,status_active,frame_active,underflow_active,freeze_active,shape_active,camera_osd_active;
 reg [51:0] camera_display={3'b100,16'h5640,9'd267,12'd1920,12'd1080};
 reg [9:0] camera_fps_display=30;reg camera_clock_display=1;
threshold_osd #(
		.X_START(12'd32),
		.Y_START(12'd24)
	) u_threshold_osd (
		.x_pos     (lcd_xpos),
		.y_pos     (lcd_ypos),
		.threshold (canny_threshold_pixel),
		.fps       (canny_fps_osd),
		.pixel_in  (lcd_split_data),
		.pixel_out (lcd_split_data_with_osd),
        .osd_active(osd_active)
	);
video_status_osd #(.X_START(32),.Y_START(80),.FW(FW)) u_status_osd(
     .x_pos(status_x),.y_pos(status_y),.gear(status_display[2:0]),.algorithm(status_display[7:5]),
     .overlay(display_overlay),.history(display_history),.compare(display_compare),
     .replay(display_replay),.left_frame(display_left),.right_frame(display_right),
     .pixel(status_rgb),.active(status_active));
threshold_osd #(.X_START(1040),.Y_START(24),.LABEL_KIND(2)) u_frame_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.threshold({{(10-FW){1'b0}},display_left}),
     .fps({{(10-FW){1'b0}},display_right}),.pixel_in(8'd0),.pixel_out(frame_pixel),.osd_active(frame_active));
threshold_osd #(.X_START(1200),.Y_START(24),.LABEL_KIND(4)) u_underflow_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.threshold(history_underflow_frame),
     .fps(history_underflow_total),.pixel_in(8'd0),.pixel_out(underflow_pixel),.osd_active(underflow_active));
video_status_osd #(.X_START(608),.Y_START(24),.FW(FW),.STATE_ONLY(1)) u_freeze_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.gear(3'd3),.algorithm(3'd0),
     .overlay(1'b0),.history(1'b1),.compare(1'b0),.replay(display_replay),
     .left_frame(display_left),.right_frame(display_right),.frozen(status_display[4]),
     .frame_count(count_pixel_display),.pixel(freeze_rgb),.active(freeze_active));
shape_osd #(.X_START(848),.Y_START(1020)) u_shape_osd(.x_pos(lcd_xpos),.y_pos(lcd_ypos),.shape(shape_display),
                         .pixel(shape_rgb),.active(shape_active));
camera_status_osd u_camera_status_osd(
     .x_pos(lcd_xpos),.y_pos(lcd_ypos),.ready(camera_display[51]),.failed(camera_display[50]),
     .size_error(camera_display[49]),.pclk_alive(camera_clock_display),.chip_id(camera_display[48:33]),
     .config_index(camera_display[32:24]),.input_fps(camera_fps_display),
     .width(camera_display[23:12]),.height(camera_display[11:0]),.pixel(camera_osd_rgb),.active(camera_osd_active));
wire [23:0] display_rgb_osd=camera_osd_active ? camera_osd_rgb : status_display[2:0]==4 && shape_active ? shape_rgb :
       osd_active ? {3{lcd_split_data_with_osd}} :
       status_active ? status_rgb : display_history && display_compare && frame_active ? {3{frame_pixel}} :
       display_history && display_compare && underflow_active ? {3{underflow_pixel}} :
       display_history && freeze_active ? freeze_rgb : scaled_image_rgb;
 integer x,y,m,n=0;reg expected_active;reg [23:0] expected;
 function box;input integer xx,yy,w,h;begin box=lcd_xpos>=xx && lcd_xpos<xx+w && lcd_ypos>=yy && lcd_ypos<yy+h;end endfunction
 initial begin
  for(m=0;m<4;m=m+1) begin
   display_history=m==1 || m==2;display_compare=m==2;status_display[2:0]=m==3 ? 4 : display_history ? 3 : 0;
   for(y=0;y<1080;y=y+8) for(x=0;x<1920;x=x+8) begin
    lcd_xpos=x;lcd_ypos=y;#1;
    if(osd_active!==box(32,24,128,46) || status_active!==box(32,80,384,72) ||
       camera_osd_active!==box(1504,24,384,72) || frame_active!==box(1040,24,128,46) ||
       underflow_active!==box(1200,24,128,46) || freeze_active!==box(608,24,384,72) || shape_active!==box(848,1020,224,40))
     $fatal(1,"OSD bounds mode=%0d xy=%0d,%0d",m,x,y);
    expected=camera_osd_active ? camera_osd_rgb : m==3 && shape_active ? shape_rgb :
       osd_active ? {3{lcd_split_data_with_osd}} : status_active ? status_rgb :
       m==2 && frame_active ? {3{frame_pixel}} : m==2 && underflow_active ? {3{underflow_pixel}} :
       display_history && freeze_active ? freeze_rgb : 24'h123456;
    if(display_rgb_osd!==expected) $fatal(1,"OSD compositor clipped or corrupt");
    n=n+1;
   end
  end
  lcd_xpos=1504;lcd_ypos=52;#1;
  if(u_camera_status_osd.text!="ID:5640 IDX:0267        ") $fatal(1,"ID/IDX diagnostic text %s",u_camera_status_osd.text);
  lcd_ypos=76;#1;
  if(u_camera_status_osd.text!="IN:0030 W:1920 H:1080   ") $fatal(1,"input diagnostics text %s",u_camera_status_osd.text);
  lcd_ypos=24;camera_display[51]=0;camera_display[50]=1;#1;
  if(u_camera_status_osd.text!="CAM:ERROR  PCLK:1       ") $fatal(1,"camera error text %s",u_camera_status_osd.text);
  lcd_xpos=159;lcd_ypos=69;#1;if(!osd_active) $fatal(1,"threshold last pixel clipped");
  lcd_ypos=70;#1;if(osd_active) $fatal(1,"threshold bottom overflow");
  lcd_xpos=1887;lcd_ypos=95;#1;if(!camera_osd_active) $fatal(1,"camera last pixel clipped");
  lcd_xpos=1888;#1;if(camera_osd_active) $fatal(1,"camera right overflow");
  $display("PASS full-HD OSD: %0d sampled pixels plus exact box boundaries across live/history/compare/shape; global margins, no viewport clipping; camera diagnostics",n);$finish;
 end
endmodule

'''
simulate('osd_1080',tb,['src/threshold_osd.v','src/video_status_osd.v','src/shape_osd.v','src/camera_status_osd.v'],timeout=180)
