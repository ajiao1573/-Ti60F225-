"""Exercise exact top-level rearm logic with the actual Canny/autoplate RTL.

The key control's decoded outputs are stimulated directly (its debounce has a
separate test). No copied behavioral Canny substitutes the accepted-frame path.
"""
from pathlib import Path
import os, subprocess, hashlib, json, re

ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
OUT=ROOT/'tests/generated';OUT.mkdir(exist_ok=True)
SIM=ROOT/'tools/sim/mingw64/bin'
top=(ROOT/'example_top.v').read_text(encoding='utf-8')
control=top[top.index('    reg previous_rescan;'):top.index('    plate_key_control #')]
status=top[top.index('    integer status_char;'):top.index('\tlcd_driver u_lcd_driver')]
core=top[top.index('    autoplate_core #'):top.index('    wire history_freeze_request=')]
core=core.replace('.WIDTH(848),.HEIGHT(477)','.WIDTH(W),.HEIGHT(H)')
gate=re.search(r'\.enable\((canny_capture_ready[^\n]+)\),',top).group(1)
if '.char_adjust(applied_adjust)' not in core or 'camera_status[6*8+:8]=applied_adjust' not in status:
    raise AssertionError('Top no longer uses applied character parameter')
if 'rearm_pending && !canny_busy && !gray_valid' not in control:
    raise AssertionError('Top safe rearm boundary changed; review test contract')
integration=(ROOT/'tools/integrate_web_b.py').read_text(encoding='utf-8')
for snippet in (control.strip(),status.strip()):
    if snippet not in integration:
        raise AssertionError('Top rearm/status and integration generator disagree')

tb=r'''`timescale 1ns/1ps
`include "src/autoplate_core.v"
`include "src/app_control_bridge.v"
module tb;
localparam W=64,H=33,N=W*H;
reg cmos_pclk=0,clk_pixel=0,sys_clk=0;
always #5 cmos_pclk=~cmos_pclk;
always #6.7 clk_pixel=~clk_pixel;
always #7 sys_clk=~sys_clk;
reg rstn_sys=0;wire rstn_pixel=rstn_sys;
reg [7:0] plate_adjust=128;reg freeze_requested=0;
reg [9:0] requested_edge_threshold=27;reg requested_run_enable=1;
reg rearm_pending,plate_rearm;reg[9:0] edge_threshold;reg[7:0] applied_adjust;reg run_enable;
reg gray_valid=0,gray_sop=0,gray_eop=0;reg[7:0] gray_data=104;
reg[10:0] full_view_x=0,full_view_y=0;
wire canny_busy;reg canny_capture_ready=1;
wire resize_enable=@GATE@;
@CONTROL@

wire plate_capture_hold,canny_frame_start,canny_frame_done;
wire [7:0] core_state;wire [5:0] plate_state;
wire plate_locked,plate_valid,plate_low,plate_overflow;
wire [47:0] plate_ascii;wire[3:0] plate_count;wire[7:0] plate_threshold;
wire[2:0] plate_reject;wire[1:0] locator_diagnostic;
wire core_box_valid;wire[10:0] core_box_x,core_box_w;wire[9:0] core_box_y,core_box_h;
wire[31:0] core_box_frame,captured_frame_id;wire edge_frame_toggle;
wire[52:0] display_meta_cam=0;wire snapshot_ready=1;
wire[10:0] roi_x=full_view_x;wire[9:0] roi_y=full_view_y;
wire roi_valid=gray_valid,roi_sop=gray_sop,roi_eop=gray_eop;
wire rgb_store_en,edge_store_en;wire[7:0] canny_data;
reg lcd_vs=0;
@CORE@
wire i2c_config_done=1,ov_size_error=0;
wire[9:0] camera_input_fps=30,edge_input_fps=29;
reg[383:0] camera_status;
@STATUS@

reg read_request=0;wire read_busy,read_valid;wire[383:0] host_status;
status_snapshot #(.WIDTH(384)) host_readback(
 .source_clk(cmos_pclk),.source_rst_n(rstn_sys),.source_data(camera_status),
 .target_clk(sys_clk),.target_rst_n(rstn_sys),.request(read_request),
 .busy(read_busy),.valid(read_valid),.data(host_status));

integer accepted=0,completed=0,source_pixels=0,preview_pixels=0,edge_pixels=0;
integer rearms=0;reg inflight=0;reg[18:0] saved_settings;
always @(posedge cmos_pclk) if(rstn_sys) begin
 if(canny_frame_start)begin
  if(inflight)$fatal(1,"overlapping accepted frames");
  inflight=1;accepted=accepted+1;saved_settings={edge_threshold,applied_adjust,run_enable};
 end
 if(rgb_store_en)source_pixels=source_pixels+1;
 if(edge_store_en)preview_pixels=preview_pixels+1;
 if(u_autoplate.ev)edge_pixels=edge_pixels+1;
 if(canny_frame_done)begin
  if(!inflight)$fatal(1,"EOF without accepted frame");
  inflight=0;completed=completed+1;
  if(edge_pixels!=completed*N)$fatal(1,"incomplete Canny output %0d expected%0d",edge_pixels,completed*N);
 end
 if(plate_rearm)begin
  rearms=rearms+1;
  if(inflight || canny_busy || gray_valid)$fatal(1,"rearm interrupted accepted Canny frame");
 end
 #1;
 if(inflight && {edge_threshold,applied_adjust,run_enable}!==saved_settings)
  $fatal(1,"applied settings changed midframe");
 if((rearm_pending || plate_rearm || canny_busy) && resize_enable)
  $fatal(1,"resizer accepted a new frame during pending/rearm/busy");
end
task read_status;
 input[9:0] wanted_edge;input[7:0] wanted_adjust;input wanted_run;
 begin
  wait(!read_busy);@(negedge sys_clk);read_request=1;
  @(negedge sys_clk);read_request=0;
  wait(read_valid);#1;
  if(host_status[4*8+:16]!=={6'd0,wanted_edge} || host_status[6*8+:8]!==wanted_adjust || host_status[3*8+7]!==wanted_run)
   $fatal(1,"host read requested instead of applied values edge%0d adj%0d run%0d",host_status[4*8+:16],host_status[6*8+:8],host_status[3*8+7]);
 end
endtask
task frame;
 input integer scenario;integer i,closed_before;
 begin
  wait(resize_enable);closed_before=completed;
  for(i=0;i<N;i=i+1)begin
   @(negedge cmos_pclk);gray_valid=1;gray_sop=i==0;gray_eop=i==N-1;
   full_view_x=i%W;full_view_y=i/W;gray_data=104;
   if(scenario==1 && i==N/3)begin plate_adjust=133;requested_edge_threshold=301;requested_run_enable=0;freeze_requested=~freeze_requested;end
   if(scenario==2 && i==N/4)begin plate_adjust=134;requested_edge_threshold=49;requested_run_enable=1;freeze_requested=~freeze_requested;end
   if(scenario==2 && i==N/2)plate_adjust=136;
   if(scenario!=0 && i==N/2+20)begin
    @(negedge cmos_pclk);gray_valid=0;gray_sop=0;gray_eop=0;
    if(scenario==1)read_status(27,128,1);else read_status(301,133,0);
   end
   if(i%41==40)begin @(negedge cmos_pclk);gray_valid=0;gray_sop=0;gray_eop=0;end
  end
  @(negedge cmos_pclk);gray_valid=0;gray_sop=0;gray_eop=0;
  // Hold valid without SOP after the accepted input frame. This is ignored by
  // Canny's take gate, but must block committing settings when output drains.
  if(scenario==1)gray_valid=1;
  wait(completed==closed_before+1);wait(!canny_busy);
  if(scenario==1)begin
   repeat(8)begin @(negedge cmos_pclk);
    if(!rearm_pending || plate_rearm || applied_adjust!=128 || edge_threshold!=27 || !run_enable)
     $fatal(1,"gray_valid did not postpone pending apply");
   end
   gray_valid=0;
  end
  if(scenario!=0)begin wait(plate_rearm);@(negedge cmos_pclk);wait(!plate_rearm);end
  repeat(6)@(negedge cmos_pclk);
  if(completed!=accepted || source_pixels!=accepted*N || preview_pixels!=source_pixels)
   $fatal(1,"accepted input/preview/EOF mismatch frames%0d/%0d pixels%0d/%0d",accepted,completed,source_pixels,preview_pixels);
 end
endtask
initial begin
 repeat(5)@(negedge cmos_pclk);rstn_sys=1;
 read_status(27,128,1);
 frame(1);read_status(301,133,0);
 if(rearms!=1 || core_state!=6)$fatal(1,"pause did not apply exactly once");
 $display("PASS midframe key/remote changes keep full Canny EOF; busy and gray_valid both block commit");
 frame(2);read_status(49,136,1);
 if(rearms!=2)$fatal(1,"coalesced latest key changes did not apply once");
 frame(0);read_status(49,136,1);
 $display("PASS next frame resumes, repeated pending changes coalesce, host snapshots report applied settings");
 // In idle, a decoded key event takes one pending cycle before applying.
 @(negedge cmos_pclk);plate_adjust=140;requested_edge_threshold=77;freeze_requested=~freeze_requested;
 @(posedge cmos_pclk);#1;
 if(!rearm_pending || plate_rearm || applied_adjust!=136)$fatal(1,"idle request skipped pending stage");
 @(posedge cmos_pclk);#1;
 if(!plate_rearm || applied_adjust!=140 || edge_threshold!=77)$fatal(1,"idle request did not apply atomically");
 repeat(5)@(negedge cmos_pclk);read_status(77,140,1);
 if(rearms!=3)$fatal(1,"idle request pulse count");
 $display("PASS idle commit, %0d accepted/completed frames, %0d exact Canny pixels, %0d rearms",completed,edge_pixels,rearms);
 $display("PASS app_rearm regression using extracted top code and real autoplate/Canny");$finish;
end
initial begin repeat(200000)@(posedge cmos_pclk);$fatal(1,"watchdog accepted%0d done%0d pending%0d busy%0d gray%0d",accepted,completed,rearm_pending,canny_busy,gray_valid);end
endmodule
'''
for key,val in [('CONTROL',control),('STATUS',status),('CORE',core),('GATE',gate)]:tb=tb.replace('@'+key+'@',val)
name='app_rearm';src=OUT/(name+'_tb.sv');src.write_text(tb,encoding='utf-8')
env=os.environ.copy();env['PATH']=str(SIM)+os.pathsep+env.get('PATH','')
result=subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-s','tb','-o',str(OUT/(name+'.vvp')),str(src)],capture_output=True,text=True,env=env)
log=result.stdout+result.stderr
if result.returncode:(OUT/(name+'.log')).write_text(log);raise SystemExit(log)
result=subprocess.run([str(SIM/'vvp.exe'),str(OUT/(name+'.vvp'))],capture_output=True,text=True,env=env,timeout=90)
log+=result.stdout+result.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,end='')
if result.returncode:raise SystemExit(result.returncode)
(OUT/(name+'_metrics.json')).write_text(json.dumps({'result':'PASS','width':64,'height':33,
 'accepted_and_completed_frames':3,'canny_pixels':6336,'rearm_pulses':3,
 'source':'exact extracted top-level control/status/core instance; real autoplate/Canny RTL',
 'top_sha256':hashlib.sha256(top.encode()).hexdigest(),'hardware_test':False},indent=2),encoding='utf-8')
