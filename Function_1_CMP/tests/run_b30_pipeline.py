"""Full-size B RGB pipeline throughput at 84 MHz / HTS2500 / VTS1120.

Actual camera_rgb_denoise -> camera_full_view -> autoplate_core RTL. This
starts with RGB, NOT DVP/Bayer, and does not test DDR or physical HDMI output.
"""
from pathlib import Path
import hashlib,json,os,subprocess,time

ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
OUT=ROOT/'tests/generated';OUT.mkdir(exist_ok=True)
SIM=ROOT/'tools/sim/mingw64/bin';name='b30_pipeline'
tb=r'''`timescale 1ns/1ps
`include "src/camera_rgb_denoise.v"
`include "src/camera_full_view.v"
`include "src/autoplate_core.v"
module tb;
 localparam IW=1920,IH=1080,HTS=2500,VTS=1120,W=848,H=477,N=W*H;
 reg clk=0;always #5.952381 clk=~clk;
 reg pixel_clk=0;always #6.734007 pixel_clk=~pixel_clk;
 reg rst=0,source_frame=0,source_valid=0;reg[23:0] source_rgb=0;
 wire smooth_frame,smooth_valid;wire[23:0] smooth_rgb;
 camera_rgb_denoise #(.WIDTH(IW),.HEIGHT(IH)) common_frontend(
  .clk(clk),.rst_n(rst),.in_frame(source_frame),.in_valid(source_valid),.in_rgb(source_rgb),
  .out_frame(smooth_frame),.out_valid(smooth_valid),.out_rgb(smooth_rgb));
 wire rv,rs,re,overflow;wire[23:0] rgb;wire[10:0] rx,ry;wire busy;
 camera_full_view #(.HEIGHT(H),.IMAGE_H(H),.FIFO_BITS(5)) view(
  .clk(clk),.rst_n(rst),.enable(!busy),.in_frame(smooth_frame),.in_valid(smooth_valid),.in_rgb(smooth_rgb),
  .out_valid(rv),.out_sop(rs),.out_eop(re),.out_rgb(rgb),.out_x(rx),.out_y(ry),.overflow(overflow));
 wire[9:0] luma={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};
 wire start,done,take,pv,hold,locked,valid,bv,toggle;wire[7:0] pd,app,thr;wire[5:0] stage;wire[47:0] ascii;
 wire[3:0] chars;wire low,over;wire[2:0] reject;wire[1:0] diag;
 wire[10:0] bx,bw;wire[9:0] by,bh;wire[31:0] bf,cf;
 reg vs=0;integer pixel_count=0;
 always @(posedge pixel_clk)begin
  if(pixel_count==9999)begin pixel_count<=0;vs<=1;end else begin pixel_count<=pixel_count+1;vs<=0;end
 end
 autoplate_core #(.WIDTH(W),.HEIGHT(H)) core(
  .clk(clk),.rst_n(rst),.run_enable(1'b1),.rearm(1'b0),.edge_threshold(10'd27),.char_adjust(8'd128),
  .in_valid(rv),.in_sop(rs),.in_eop(re),.in_gray(luma[9:2]),.in_x(rx),.in_y(ry[9:0]),
  .capture_ready(1'b1),.snapshot_ready(1'b1),.pixel_clk(pixel_clk),.pixel_rst_n(rst),.pixel_vsync(vs),
  .frame_start(start),.frame_done(done),.busy(busy),.source_take(take),
  .preview_valid(pv),.preview_data(pd),.capture_hold(hold),.app_state(app),.segment_state(stage),
  .recognized_locked(locked),.recognized_valid(valid),.recognized_ascii(ascii),.characters(chars),
  .binary_threshold(thr),.low_contrast(low),.overflow(over),.reject_reason(reject),.locator_diagnostic(diag),
  .box_valid(bv),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.box_frame(bf),.captured_frame_id(cf),.edge_frame_toggle(toggle));

 integer resized=0,view_frames=0,view_ends=0,accepted=0,completed=0,source_taken=0,previews=0;
 integer edges=0,edge_starts=0,edge_ends=0,edge_nonzero0=0,edge_nonzero1=0,step_rows=0,last_step_row=-1;
 integer smooth_pixels=0,qwrite=0,qread=0,px,py,which,ei,ex,ey;
 reg[7:0] queue[0:255];
 reg[23:0] expected_rgb;reg[7:0] expected_gray;
 always @(posedge clk)if(rst)begin
  if(overflow)$fatal(1,"full_view FIFO overflow");
  if(smooth_valid)smooth_pixels=smooth_pixels+1;
  if(rv)begin
   px=resized%W;py=(resized/N==0 ? resized:resized-N)/W;which=resized/N;
   if(which>=2 || rx!==px || ry!==py)$fatal(1,"local view coords pixel%0d got%0d,%0d want%0d,%0d",resized,rx,ry,px,py);
   if(rs!==(resized%N==0) || re!==(resized%N==N-1))$fatal(1,"view SOP/EOP index%0d",resized);
   if(rs)view_frames=view_frames+1;if(re)view_ends=view_ends+1;
   if(which==0 && rgb!==24'h808080)$fatal(1,"constant RGB changed at%0d rgb%h",resized,rgb);
   if(which==1 && px<W/2-8 && rgb!==24'h323232)$fatal(1,"step left preview changed x%0d y%0d rgb%h",px,py,rgb);
   if(which==1 && px>W/2+8 && rgb!==24'hc8c8c8)$fatal(1,"step right preview changed x%0d y%0d rgb%h",px,py,rgb);
   if(!take)$fatal(1,"resized pixel not accepted by core index%0d",resized);
   resized=resized+1;
  end
  if(start)begin
   if(accepted!=completed)$fatal(1,"next accepted SOP while preceding EOF missing");
   accepted=accepted+1;
  end
  if(take)begin queue[qwrite%256]=luma[9:2];qwrite=qwrite+1;source_taken=source_taken+1;end
  if(pv)begin
   if(qread>=qwrite || pd!==queue[qread%256])$fatal(1,"preview not original accepted gray at%0d got%0d",qread,pd);
   qread=qread+1;previews=previews+1;
  end
  if(core.ev)begin
   ei=edges%N;ex=ei%W;ey=ei/W;
   if(core.es!==(ei==0) || core.ee!==(ei==N-1))$fatal(1,"Canny SOP/EOP index%0d",edges);
   if(core.es)edge_starts=edge_starts+1;if(core.ee)edge_ends=edge_ends+1;
   if(core.ed!==0)begin
    if(edges<N)edge_nonzero0=edge_nonzero0+1;
    else begin
     edge_nonzero1=edge_nonzero1+1;
     if(ex<W/2-8 || ex>W/2+8)$fatal(1,"step edge outside midpoint x%0d y%0d",ex,ey);
     if(ey!=last_step_row)begin step_rows=step_rows+1;last_step_row=ey;end
    end
   end
   edges=edges+1;
  end
  if(done)begin
   completed=completed+1;
   if(edges!=completed*N || source_taken!=completed*N || previews!=completed*N)
    $fatal(1,"frame%0d incomplete counts input%0d preview%0d edge%0d",completed,source_taken,previews,edges);
   $display("FRAME_DONE frame%0d pixels%0d source_id%0d edge_pixels%0d time%0t",completed,N,core.source_frame_id,completed==1 ? edge_nonzero0:edge_nonzero1,$time);
  end
  if(bv || hold || locked || valid)$fatal(1,"flat/one-step input falsely proposed or recognized a plate");
 end

 integer frame,y,x;reg[7:0] sample;time prior_sop=0;
 initial begin
  repeat(8)@(negedge clk);rst=1;
  for(frame=0;frame<2;frame=frame+1)begin
   for(y=0;y<VTS;y=y+1)begin
    for(x=0;x<HTS;x=x+1)begin
     @(negedge clk);
     if(x==0 && y==0)begin
      if(busy || completed!=frame || resized!=frame*N || smooth_pixels!=frame*IW*IH)
       $fatal(1,"source SOP%0d preceding frame late/drop busy%0d completed%0d resized%0d smooth%0d",frame,busy,completed,resized,smooth_pixels);
      if(core.source_frame_id!==frame)$fatal(1,"source frame id before SOP got%0d expected%0d",core.source_frame_id,frame);
      $display("SOURCE_SOP frame%0d time%0t previous_period%0t",frame+1,$time,prior_sop ? $time-prior_sop:0);
      prior_sop=$time;
     end
     source_frame=y<IH;source_valid=y<IH && x<IW;
     sample=frame==0 ? 128:(x<960 ? 50:200);source_rgb={sample,sample,sample};
    end
   end
  end
  // This is the time the next source SOP would arrive, not extra drain time.
  @(negedge clk);source_frame=0;source_valid=0;
  if(busy || completed!=2 || accepted!=2 || view_frames!=2 || view_ends!=2 || edge_starts!=2 || edge_ends!=2)
   $fatal(1,"two-frame throughput/SOP/EOP failure busy%0d frames%0d/%0d view%0d/%0d edge%0d/%0d",busy,accepted,completed,view_frames,view_ends,edge_starts,edge_ends);
  if(resized!=2*N || previews!=2*N || edges!=2*N || source_taken!=2*N || smooth_pixels!=2*IW*IH)
   $fatal(1,"final pixel counts mismatch");
  if(core.source_frame_id!==2 || cf!==0)$fatal(1,"frame IDs mismatch source%0d capture%0d",core.source_frame_id,cf);
  if(edge_nonzero0!=0 || step_rows<H-8 || edge_nonzero1<H-8)$fatal(1,"flat/step quality flat%0d step%0d rows%0d",edge_nonzero0,edge_nonzero1,step_rows);
  $display("PASS b30_pipeline: 2 source frames 1920x1080 RGB at84MHz HTS2500 VTS1120, 2x404496 preview/edge pixels, local848x477 coords, no FIFO overflow or drops");
  $display("PASS constant edges%0d; step edges%0d covering%0d/%0d rows; source IDs1,2; no plate candidates",edge_nonzero0,edge_nonzero1,step_rows,H);
  $finish;
 end
 initial begin repeat(2*HTS*VTS+10000)@(posedge clk);$fatal(1,"watchdog");end
endmodule
'''
source=OUT/(name+'_tb.sv');source.write_text(tb,encoding='utf-8')
env=os.environ.copy();env['PATH']=str(SIM)+os.pathsep+env.get('PATH','')
compile_result=subprocess.run([str(SIM/'iverilog.exe'),'-g2012','-s','tb','-o',str(OUT/(name+'.vvp')),str(source)],capture_output=True,text=True,env=env)
log=OUT/(name+'.log')
if compile_result.returncode:
    log.write_text(compile_result.stdout+compile_result.stderr);raise SystemExit(log.read_text())
sources=['src/camera_rgb_denoise.v','src/camera_rgb_smooth.v','src/camera_full_view.v','src/autoplate_core.v','src/plate_locator.v','src/plate_segmenter.v']
sources += [p.relative_to(ROOT).as_posix() for p in (ROOT/'src/canny').glob('*.v')]
hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}
t=time.monotonic()
with log.open('w',encoding='utf-8') as stream:
    stream.write(compile_result.stdout+compile_result.stderr);stream.flush()
    result=subprocess.run([str(SIM/'vvp.exe'),str(OUT/(name+'.vvp'))],stdout=stream,stderr=subprocess.STDOUT,env=env,timeout=1800)
text=log.read_text();print(text,end='')
if result.returncode:raise SystemExit(result.returncode)
import re
match=re.search(r'constant edges(\d+); step edges(\d+) covering(\d+)',text)
(OUT/(name+'_metrics.json')).write_text(json.dumps({'result':'PASS','elapsed_seconds':round(time.monotonic()-t,2),
 'input':[1920,1080],'processing':[848,477],'clock_hz':84000000,'hts':2500,'vts':1120,'fps':30,
 'frames':2,'pixels_per_frame':404496,'threshold':27,'constant_edges':int(match[1]),'step_edges':int(match[2]),'step_rows':int(match[3]),
 'scope':'RGB input through actual denoise/resize/autoplate RTL; not DVP, Bayer, DDR or HDMI physical validation',
 'source_sha256':hashes,'hardware_test':False},indent=2),encoding='utf-8')
