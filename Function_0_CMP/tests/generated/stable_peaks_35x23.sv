`timescale 1ns/1ps
module tb;
localparam W=35,H=23,N=W*H,F=55,TOTAL=N*F,HIST=41055;
reg clk=0;always #5 clk=~clk;reg rst=0,iv=0,fv=0;reg[23:0] data=0;
wire pv,pf;wire[23:0] rgb;
camera_rgb_denoise #(.WIDTH(W),.HEIGHT(H)) common(clk,rst,fv,iv,data,pf,pv,rgb);
reg[$clog2(N+1)-1:0] idx=0;
always @(posedge clk) if(!rst) idx<=0;else if(pv)idx<=idx==N-1 ? 0:idx+1'b1;
wire sop=pv && idx==0,eop=pv && idx==N-1;
wire[9:0] rgb_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
reg[1:0] mode=3;reg[9:0] threshold=27;wire busy,gv,gs,ge,ev,es,ee,protect;wire[7:0] gd,ed;
canny_frame #(.WIDTH(W),.HEIGHT(H),.RUNTIME_MODES(1),.SOBEL_MAX_ENABLE(1),.ROBUST_NMS(1),.LOW_TIGHTEN(1),.BORDER_REFLECT(1),.NMS_TOLERANCE(4),.PROTECT_ENABLE(1),.COHERENT_PROTECT(1),.TEMPORAL_NMS(1)) dut(
.clk(clk),.rst_n(rst),.capture_ready(1'b1),.in_valid(pv),.in_sop(sop),.in_eop(eop),.in_data(rgb_sum[9:2]),.threshold(threshold),.algorithm(mode),
.busy(busy),.gray_valid(gv),.gray_sop(gs),.gray_eop(ge),.gray_data(gd),.edge_valid(ev),.edge_sop(es),.edge_eop(ee),.edge_data(ed),.edge_protect(protect));
reg[23:0] inp[0:TOTAL-1],goldrgb[0:TOTAL-1];reg[7:0] goldgray[0:TOTAL-1],goldedge[0:TOTAL-1],goldprotect[0:TOTAL-1];
reg[1:0] goldclass[0:TOTAL-1],modes[0:F-1];reg[9:0] thrs[0:F-1];reg goldhistory[0:HIST-1];
integer rc=0,gc=0,ec=0,hc=0,cycles=0,f,i,j; reg[22:0] dbg_center,dbg_a,dbg_c;reg dbg_held,dbg_compete,dbg_peak,dbg_direct,dbg_selected,dbg_weak;reg[7:0] dbg_support,dbg_ta,dbg_tb; always @(posedge clk) begin dbg_direct<=dut.frontend.nms_enabled.normal_a[22] && dut.frontend.nms_enabled.normal_a[18:8]!=0 && dut.frontend.nms_enabled.normal_a[18:8]>=dut.frontend.nms_enabled.stable_peak_logic.hold_limit && {1'b0,dut.frontend.nms_enabled.normal_a[18:8]}+12'd2>={1'b0,dut.frontend.nms_enabled.mag} && dut.frontend.nms_enabled.normal_a[20:19]==dut.frontend.nms_enabled.n22[20:19] && dut.frontend.nms_enabled.normal_a[21]==dut.frontend.nms_enabled.n22[21];dbg_support<=dut.frontend.nms_enabled.weak_support;dbg_ta<=dut.frontend.nms_enabled.tangent_a;dbg_tb<=dut.frontend.nms_enabled.tangent_b;dbg_selected<=dut.frontend.nms_enabled.selected_peak;dbg_weak<=dut.frontend.nms_enabled.weak_supported;dbg_center<=dut.frontend.nms_enabled.n22;dbg_a<=dut.frontend.nms_enabled.normal_a;dbg_c<=dut.frontend.nms_enabled.normal_c;dbg_held<=dut.frontend.nms_enabled.held_peak;dbg_compete<=dut.frontend.nms_enabled.competing_history;dbg_peak<=dut.frontend.nms_enabled.peak;end
always @(posedge clk) if(rst) begin
 cycles=cycles+1;if(cycles>TOTAL*8) $fatal(1,"timeout rc%0d gc%0d ec%0d hc%0d",rc,gc,ec,hc);
 if(pv)begin
  if(rgb!==goldrgb[rc])$fatal(1,"RGB f%0d x%0d y%0d got%h want%h",rc/N,rc%W,(rc%N)/W,rgb,goldrgb[rc]);rc=rc+1;
 end
 if(dut.frontend.nms_enabled.stable_history.history.out_valid)begin
  if(dut.frontend.nms_enabled.stable_history.history.out_data[22]!==goldhistory[hc])
   $fatal(1,"HISTORY token%0d x%0d y%0d got%b want%b",hc,hc%W,(hc%N)/W,dut.frontend.nms_enabled.stable_history.history.out_data[22],goldhistory[hc]);
  hc=hc+1;
 end
 if(gv)begin
  if(gd!==goldgray[gc] || dut.classification!==goldclass[gc])begin $display("DETAIL direct_a=%b selected=%b weak=%b support=%b ta=%b tb=%b n22=%h na=%h nc=%h held=%b competing=%b peak=%b weak=%b strong=%b low=%d high=%d",dbg_direct,dbg_selected,dbg_weak,dbg_support,dbg_ta,dbg_tb,dbg_center,dbg_a,dbg_c,dbg_held,dbg_compete,dbg_peak,dut.frontend.nms_enabled.weak_supported,dut.frontend.nms_enabled.strong_supported,dut.low_latched,dut.high_latched);$fatal(1,"GRAY/CLASS f%0d x%0d y%0d gray%0d/%0d class%0d/%0d",gc/N,gc%W,(gc%N)/W,gd,goldgray[gc],dut.classification,goldclass[gc]);end
  if(gs!==(gc%N==0) || ge!==(gc%N==N-1))$fatal(1,"GRAY framing %0d",gc);gc=gc+1;
 end
 if(ev)begin
  if(ed!==goldedge[ec] || protect!==goldprotect[ec][0])$fatal(1,"EDGE/PROTECT f%0d x%0d y%0d edge%0d/%0d protect%b/%b",ec/N,ec%W,(ec%N)/W,ed,goldedge[ec],protect,goldprotect[ec][0]);
  if(es!==(ec%N==0) || ee!==(ec%N==N-1))$fatal(1,"EDGE framing %0d",ec);ec=ec+1;
 end
end
initial begin
$readmemh("tests/generated/stable_peaks_35x23_input.hex",inp);
$readmemh("tests/generated/stable_peaks_35x23_rgb.hex",goldrgb);
$readmemh("tests/generated/stable_peaks_35x23_gray.hex",goldgray);
$readmemh("tests/generated/stable_peaks_35x23_edge.hex",goldedge);
$readmemh("tests/generated/stable_peaks_35x23_class.hex",goldclass);
$readmemh("tests/generated/stable_peaks_35x23_protect.hex",goldprotect);
$readmemh("tests/generated/stable_peaks_35x23_history.hex",goldhistory);
$readmemh("tests/generated/stable_peaks_35x23_mode.hex",modes);
$readmemh("tests/generated/stable_peaks_35x23_threshold.hex",thrs);
repeat(8)@(negedge clk);rst=1;
for(f=0;f<F;f=f+1)begin
 wait(!busy);mode=modes[f];threshold=thrs[f];fv=1;
 for(i=0;i<N;i=i+1)begin
  iv=1;data=inp[f*N+i];@(negedge clk);
  if(i==N/2)begin mode=~modes[f];threshold=thrs[f]^10'h3ff;end
  if(i%13==7 || i%W==W-1)begin iv=0;repeat(1+i%4)@(negedge clk);end
 end
 iv=0;fv=0;wait(ec==(f+1)*N);repeat(5*W+30)@(negedge clk);
 if(rc!=(f+1)*N || gc!=(f+1)*N)$fatal(1,"frame count%0d",f);
end
if(hc!=HIST)$fatal(1,"history count%0d expected%0d",hc,HIST);
$display("PASS stable peaks 35x23: 55 frames; common RGB,gray,class,edge,protect,all markers,prior-history bits,mode/THR transitions,midframe changes,gaps,partial word");$finish;
end
endmodule
