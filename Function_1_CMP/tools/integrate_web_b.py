"""Deterministic migration from the preserved standalone B top-level."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
base=root.parent/'ti60_split_20261022/nz_plate/example_top.v'
s=base.read_text(encoding='utf-8')
s=s.replace('`include "src/camera_rgb_smooth.v"','''`include "src/camera_rgb_denoise.v"
`include "src/autoplate_core.v"
`include "src/host_uart.v"
`include "src/app_control_bridge.v"
`include "src/single_gray_view.v"''',1)
s=s.replace('camera_rgb_smooth u_camera_rgb_smooth(','camera_rgb_denoise #(.WIDTH(1920),.HEIGHT(1080)) u_camera_rgb_smooth(',1)
s=s.replace('    camera_full_view #','''    wire canny_capture_ready,canny_busy;
    reg rearm_pending,plate_rearm;
    reg [9:0] edge_threshold;
    reg [7:0] applied_adjust;
    reg run_enable;
    camera_full_view #''',1)
s=re.sub(r'^\s*wire\s+lcd_vs;[^\n]*\n','',s,flags=re.M)
s=s.replace('    wire canny_capture_ready,canny_busy;','    wire canny_capture_ready,canny_busy;\n    wire lcd_vs;',1)
s=s.replace('.enable(canny_capture_ready),','.enable(canny_capture_ready && !canny_busy && !rearm_pending && !plate_rearm),',1)
a=s.index('    // Standalone plate mode;')
b=s.index('\treg\t\t\tr_XYCrop_frame_vsync',a)
s=s[:a]+r'''
    // Shared control inputs: local keys and UART apply to the same registers.
    localparam FRAME_DEPTH=8,FW=3;
    wire [7:0] plate_adjust;
    wire freeze_requested,remote_load,remote_rescan,requested_run_enable;
    wire [7:0] remote_adjust;
    wire [9:0] requested_edge_threshold;
    reg pre_rgb_frame_d;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) pre_rgb_frame_d<=0;else pre_rgb_frame_d<=pre_rgb_vsync;
    wire sensor_frame_boundary=pre_rgb_vsync && !pre_rgb_frame_d;
    reg previous_rescan;reg [7:0] previous_adjust;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin previous_rescan<=0;previous_adjust<=128;end
     else begin previous_rescan<=freeze_requested;previous_adjust<=plate_adjust;end
    wire key_or_remote_change=(previous_rescan!=freeze_requested)||(previous_adjust!=plate_adjust);
    // Key releases can occur mid-frame. Never reset Canny during an accepted
    // frame: preserve its final DDR EOF, then atomically apply the new settings.
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin
      rearm_pending<=0;plate_rearm<=0;edge_threshold<=27;applied_adjust<=128;run_enable<=1;
     end else begin
      plate_rearm<=0;
      if(key_or_remote_change) rearm_pending<=1;
      if(rearm_pending && !canny_busy && !gray_valid) begin
       edge_threshold<=requested_edge_threshold;applied_adjust<=plate_adjust;run_enable<=requested_run_enable;
       rearm_pending<=0;plate_rearm<=1;
      end
     end
    plate_key_control #(.CLOCK_HZ(84000000),.DEBOUNCE(840000),.REMOTE_ENABLE(1)) u_plate_keys(
     .clk(cmos_pclk),.rst_n(rstn_sys),.keys(key_data),.adjust(plate_adjust),.rescan_toggle(freeze_requested),
     .remote_load(remote_load),.remote_adjust(remote_adjust),.remote_rescan(remote_rescan));
    wire command_valid,command_ready;wire [7:0] command_code;wire [15:0] command_value;
    wire [383:0] status_payload;reg [383:0] camera_status;
    host_uart #(.CLOCK_HZ(96000000),.BAUD(115200)) u_host_uart(
     .clk(clk_sys),.rst_n(rstn_sys),.rx(uart_rx_i),.tx(uart_tx_o),.status_payload(status_payload),
     .command_ready(command_ready),.command_valid(command_valid),.command_code(command_code),.command_value(command_value));
    app_control_bridge u_app_control(
     .sys_clk(clk_sys),.sys_rst_n(rstn_sys),.cam_clk(cmos_pclk),.cam_rst_n(rstn_sys),.frame_boundary(sensor_frame_boundary),
     .command_valid(command_valid),.command_code(command_code),.command_value(command_value),.command_ready(command_ready),
     .camera_status(camera_status),.status_payload(status_payload),.edge_threshold(requested_edge_threshold),.run_enable(requested_run_enable),
     .remote_load(remote_load),.remote_adjust(remote_adjust),.remote_rescan(remote_rescan));

    wire plate_capture_hold,history_frozen,canny_frame_start,canny_frame_done;
    wire [7:0] core_state;wire [5:0] plate_state;
    wire plate_locked,plate_valid,plate_low,plate_overflow;
    wire [47:0] plate_ascii;wire [3:0] plate_count;wire [7:0] plate_threshold;
    wire [2:0] plate_reject;wire [1:0] locator_diagnostic;
    wire core_box_valid;wire [10:0] core_box_x,core_box_w;wire [9:0] core_box_y,core_box_h;
    wire [31:0] core_box_frame,captured_frame_id;
    wire edge_frame_toggle;
    wire [52:0] display_meta_cam;
    wire snapshot_ready=display_meta_cam[20] && display_meta_cam[52:21]==captured_frame_id;
    wire [10:0] roi_x=full_view_x;wire [9:0] roi_y=full_view_y;
    wire roi_valid=gray_valid,roi_sop=gray_sop,roi_eop=gray_eop;
    wire rgb_store_en,edge_store_en;wire [7:0] canny_data;
    autoplate_core #(.WIDTH(848),.HEIGHT(477)) u_autoplate(
     .clk(cmos_pclk),.rst_n(rstn_sys),.run_enable(run_enable),.rearm(plate_rearm),
     .edge_threshold(edge_threshold),.char_adjust(applied_adjust),
     .in_valid(roi_valid),.in_sop(roi_sop),.in_eop(roi_eop),.in_gray(gray_data),.in_x(roi_x),.in_y(roi_y),
     .capture_ready(canny_capture_ready),.snapshot_ready(snapshot_ready),
     .pixel_clk(clk_pixel),.pixel_rst_n(rstn_pixel),.pixel_vsync(lcd_vs),
     .frame_start(canny_frame_start),.frame_done(canny_frame_done),.busy(canny_busy),.source_take(rgb_store_en),
     .preview_valid(edge_store_en),.preview_data(canny_data),.capture_hold(plate_capture_hold),.app_state(core_state),.segment_state(plate_state),
     .recognized_locked(plate_locked),.recognized_valid(plate_valid),.recognized_ascii(plate_ascii),
     .characters(plate_count),.binary_threshold(plate_threshold),.low_contrast(plate_low),.overflow(plate_overflow),
     .reject_reason(plate_reject),.locator_diagnostic(locator_diagnostic),
     .box_valid(core_box_valid),.box_x(core_box_x),.box_y(core_box_y),.box_w(core_box_w),.box_h(core_box_h),
     .box_frame(core_box_frame),.captured_frame_id(captured_frame_id),.edge_frame_toggle(edge_frame_toggle));
    wire history_freeze_request=plate_capture_hold;
    wire thumbnail_valid,thumbnail_eol;wire [23:0] thumbnail_rgb;
    video_thumbnail2 u_video_thumbnail2(
     .clk(cmos_pclk),.rst_n(rstn_sys),.in_valid(rgb_store_en),
     .in_x(full_view_x),.in_y(full_view_y),.in_rgb(camera_rgb),
     .out_valid(thumbnail_valid),.out_eol(thumbnail_eol),.out_rgb(thumbnail_rgb));
    wire [9:0] thumbnail_gray_sum={2'b0,thumbnail_rgb[23:16]}+{1'b0,thumbnail_rgb[15:8],1'b0}+{2'b0,thumbnail_rgb[7:0]};
    reg [3:0] gray_pad_count;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) gray_pad_count<=0;
     else if(thumbnail_valid && thumbnail_eol) gray_pad_count<=8;
     else if(gray_pad_count!=0) gray_pad_count<=gray_pad_count-1'b1;
    wire gray_store_en=thumbnail_valid || gray_pad_count!=0;
    wire [7:0] gray_store_data=thumbnail_valid ? thumbnail_gray_sum[9:2]:8'd0;
    wire split_store_eof=canny_frame_done;
''' +s[b:]
a=s.index('\t// DDR中分平面保存')
b=s.index('\tsplit_frame_ctrl #',a)
s=s[:a]+r'''
    // One complete grayscale image. No split panes or character thumbnails.
    wire display_stream_request,stream_available;
    wire [31:0] display_frame_id;
    wire [9:0] fifo_missing_frame,fifo_missing_total,cache_missing_frame,cache_missing_total;
    wire [10:0] missing_frame_sum={1'b0,fifo_missing_frame}+{1'b0,cache_missing_frame};
    wire [10:0] missing_total_sum={1'b0,fifo_missing_total}+{1'b0,cache_missing_total};
    wire [9:0] display_underflow_frame=missing_frame_sum>999 ? 10'd999:missing_frame_sum[9:0];
    wire [9:0] display_underflow_total=missing_total_sum>999 ? 10'd999:missing_total_sum[9:0];
    wire [23:0] lcd_overlay_rgb;
''' +s[b:]
s=s.replace('split_frame_ctrl #(.EDGE_LINES(477)','split_frame_ctrl #(.SINGLE_VIEW(1),.EDGE_LINES(477)',1)
s=s.replace('.rframe_left(overlay_left_pixel)',".rframe_left(1'b0)",1)
s=s.replace('.display_underflow_frame(display_underflow_frame),.display_underflow_total(display_underflow_total)',
 '.display_underflow_frame(fifo_missing_frame),.display_underflow_total(fifo_missing_total),\n        .stream_available(stream_available),.display_frame_id(display_frame_id)',1)
a=s.index('\twire split_left_pixel')
b=s.index('\tlcd_driver u_lcd_driver',a)
s=s[:a]+r'''
    wire [74:0] box_packet_pixel;
    wire [74:0] box_packet_camera={core_box_frame,core_box_valid,core_box_x,core_box_y,core_box_w,core_box_h};
    status_snapshot #(.WIDTH(75)) u_box_snapshot(
     .source_clk(cmos_pclk),.source_rst_n(rstn_sys),.source_data(box_packet_camera),
     .target_clk(clk_pixel),.target_rst_n(rstn_pixel),.request(1'b1),.busy(),.valid(),.data(box_packet_pixel));
    wire [52:0] display_meta_pixel={display_frame_id,history_frozen,display_underflow_total,display_underflow_frame};
    status_snapshot #(.WIDTH(53)) u_display_snapshot(
     .source_clk(clk_pixel),.source_rst_n(rstn_pixel),.source_data(display_meta_pixel),
     .target_clk(cmos_pclk),.target_rst_n(rstn_sys),.request(1'b1),.busy(),.valid(),.data(display_meta_cam));
    wire [23:0] display_rgb_osd;
    single_gray_view u_single_gray_view(
     .clk(clk_pixel),.rst_n(rstn_pixel),.vsync(lcd_vs),.lcd_request(lcd_request),.x_pos(lcd_xpos),.y_pos(lcd_ypos),
     .stream_data(lcd_data),.stream_available(stream_available),.stream_request(display_stream_request),
     .box_valid(box_packet_pixel[42] && box_packet_pixel[74:43]==display_frame_id),
     .box_x(box_packet_pixel[41:31]),.box_y(box_packet_pixel[30:21]),.box_w(box_packet_pixel[20:10]),.box_h(box_packet_pixel[9:0]),
     .rgb(display_rgb_osd),.underflow_frame(cache_missing_frame),.underflow_total(cache_missing_total));
    reg camera_frame_toggle,raw_frame_d;
    always @(posedge cmos_pclk or negedge rstn_sys)
     if(!rstn_sys) begin camera_frame_toggle<=0;raw_frame_d<=0;end
     else begin raw_frame_d<=ov_frame_valid;if(ov_frame_valid && !raw_frame_d) camera_frame_toggle<=!camera_frame_toggle;end
    wire [9:0] camera_input_fps,edge_input_fps;
    frame_rate_meter #(.CLOCK_HZ(84000000)) u_camera_input_fps(
     .clk(cmos_pclk),.rst_n(rstn_sys),.frame_toggle(camera_frame_toggle),.fps(camera_input_fps));
    frame_rate_meter #(.CLOCK_HZ(84000000)) u_edge_input_fps(
     .clk(cmos_pclk),.rst_n(rstn_sys),.frame_toggle(edge_frame_toggle),.fps(edge_input_fps));
    integer status_char;
    always @* begin
     camera_status=0;
     camera_status[0+:8]=1;
     camera_status[2*8+:8]=!i2c_config_done || ov_size_error ? 0:core_state;
     camera_status[3*8+:8]={run_enable,plate_capture_hold,plate_valid,plate_overflow,plate_low,
      (plate_capture_hold && plate_state!=2 && plate_state!=49 && plate_state!=50),core_box_valid,(i2c_config_done && !ov_size_error)};
     camera_status[4*8+:16]={6'd0,edge_threshold};camera_status[6*8+:8]=applied_adjust;
     camera_status[7*8+:8]={4'd0,plate_count};
     for(status_char=0;status_char<6;status_char=status_char+1)
      camera_status[(8+status_char)*8+:8]=plate_ascii[(5-status_char)*8+:8];
     camera_status[14*8+:8]={5'd0,plate_reject};camera_status[15*8+:8]={6'd0,locator_diagnostic};
     camera_status[16*8+:16]={5'd0,core_box_x};camera_status[18*8+:16]={6'd0,core_box_y};
     camera_status[20*8+:16]={5'd0,core_box_w};camera_status[22*8+:16]={6'd0,core_box_h};
     camera_status[24*8+:16]={6'd0,camera_input_fps};camera_status[26*8+:16]={6'd0,edge_input_fps};
     camera_status[28*8+:16]={6'd0,display_meta_cam[9:0]};camera_status[30*8+:16]={6'd0,display_meta_cam[19:10]};
     camera_status[32*8+:32]=captured_frame_id;
     camera_status[36*8+:16]=1920;camera_status[38*8+:16]=1080;
     camera_status[40*8+:16]=848;camera_status[42*8+:16]=477;
     camera_status[44*8+:8]=plate_threshold;camera_status[45*8+:8]=1;camera_status[46*8+:16]=1;
    end
''' +s[b:]
(root/'example_top.v').write_text(s,encoding='utf-8')
print('Integrated full-gray preview, automatic plate core and UART control/status mailboxes')
