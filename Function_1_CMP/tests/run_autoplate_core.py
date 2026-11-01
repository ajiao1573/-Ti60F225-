"""Actual Canny->locator->dynamic gray crop->NZ OCR with serializable frame IDs.

Uses existing calibration photographs in new full-frame positions/scales. This
is integration regression, not independent road-scene recognition accuracy.
"""
from pathlib import Path
import json,random,sys
from PIL import Image
from run_plate_locator import smooth,simulate,OUT,ROOT

def fixture(w,h,file,x,y,pw,ph):
 rng=random.Random(291028+w+x+y)
 p=[104+rng.randrange(-2,3) for _ in range(w*h)]
 im=Image.open(ROOT/'tests/plate_samples'/file).convert('L').resize((pw,ph),Image.Resampling.LANCZOS)
 a=list(im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata())
 for yy in range(ph):p[(y+yy)*w+x:(y+yy)*w+x+pw]=a[yy*pw:(yy+1)*pw]
 return smooth(smooth(p,w,h),w,h,True)

def verify(name,w,h,cases):
 # Case0 is blank; each subsequent case is a rescan without resetting frame IDs.
 n=w*h;images=[[104]*n]+[fixture(w,h,*c[1:]) for c in cases]
 inp=OUT/(name+'_gray.hex');inp.write_text(''.join(f'{v:x}\n' for p in images for v in p))
 expected='\n'.join(f"words[{i+1}]=48'h{c[0].encode().hex()};" for i,c in enumerate(cases))
 tb='''`timescale 1ns/1ps
module tb;
localparam W=@W@,H=@H@,N=W*H,CASES=@CASES@;
reg clk=0;always #5.952381 clk=~clk;
reg pclk=0;always #6.734007 pclk=~pclk;
reg rst=0,rearm=0,run=1,iv=0,sop=0,eop=0;reg[7:0] gray=104;reg[10:0] ix=0;reg[9:0] iy=0;
reg vs=0;integer pc=0;always @(posedge pclk)begin if(pc==9999)begin pc<=0;vs<=1;end else begin pc<=pc+1;vs<=0;end end
wire start,done,busy,take,pv,hold,locked,valid,bv,toggle;wire[7:0] pd,app,thr;wire[5:0] stage;wire[47:0] ascii;
wire[3:0] chars;wire low,over;wire[2:0] reject;wire[1:0] diag;wire[10:0] bx,bw;wire[9:0] by,bh;wire[31:0] bf,cf;
reg snapshot=0;wire ready=!hold;
autoplate_core #(.WIDTH(W),.HEIGHT(H)) dut(
.clk(clk),.rst_n(rst),.run_enable(run),.rearm(rearm),.edge_threshold(10'd27),.char_adjust(8'd128),
.in_valid(iv),.in_sop(sop),.in_eop(eop),.in_gray(gray),.in_x(ix),.in_y(iy),.capture_ready(ready),.snapshot_ready(snapshot),
.pixel_clk(pclk),.pixel_rst_n(rst),.pixel_vsync(vs),.frame_start(start),.frame_done(done),.busy(busy),.source_take(take),
.preview_valid(pv),.preview_data(pd),.capture_hold(hold),.app_state(app),.segment_state(stage),
.recognized_locked(locked),.recognized_valid(valid),.recognized_ascii(ascii),.characters(chars),.binary_threshold(thr),
.low_contrast(low),.overflow(over),.reject_reason(reject),.locator_diagnostic(diag),.box_valid(bv),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),
.box_frame(bf),.captured_frame_id(cf),.edge_frame_toggle(toggle));
reg[7:0] image[0:(CASES+1)*N-1],queue[0:1023];reg[47:0] words[0:CASES];
integer written=0,read=0,accepted=0,closed=0,i,c,attempts,waits;reg last_hold=0;reg[31:0] expected_capture=0;
integer debug_file,debug_index;reg[5:0] previous_stage=0;
reg[10:0] fixed_x,fixed_w;reg[9:0] fixed_y,fixed_h;reg[31:0] fixed_frame;
always @(posedge clk)if(rst)begin
 if(start)begin
  accepted=accepted+1;
  if(stage==1 && dut.located && run)expected_capture=accepted;
 end
 if(take)begin queue[written%1024]=gray;written=written+1;end
 if(pv)begin
  if(read>=written || pd!==queue[read%1024])$fatal(1,"preview not accepted original gray at%0d",read);
  read=read+1;
 end
 if(done)closed=closed+1;
 if(!last_hold && hold)snapshot<=0;
 if(done && hold)snapshot<=1;
 last_hold<=hold;
 #1;
 if(hold && cf!=expected_capture)$fatal(1,"capture frame mismatch got%0d expected%0d",cf,expected_capture);
 if(hold && (!bv || bf!=cf))$fatal(1,"frozen box/frame mismatch bf%0d cf%0d",bf,cf);
end
always @(negedge clk)if(rst)begin
 if(stage==46 && previous_stage!=46)begin
  debug_file=$fopen($sformatf("tests/generated/@NAME@_case%0d_glyph.hex",c),"w");
  for(debug_index=0;debug_index<3840;debug_index=debug_index+1)$fdisplay(debug_file,"%h",dut.segmenter.nz_ocr.classifier.glyph_rows[debug_index/20][19-debug_index%20]);
  $fclose(debug_file);
  debug_file=$fopen($sformatf("tests/generated/@NAME@_case%0d_roi.hex",c),"w");
  for(debug_index=0;debug_index<24576;debug_index=debug_index+1)$fdisplay(debug_file,"%h",dut.segmenter.roi_mem[(!dut.segmenter.SINGLE_BUFFER && dut.segmenter.bank ? 24576:0)+debug_index]);
  $fclose(debug_file);
  debug_file=$fopen($sformatf("tests/generated/@NAME@_case%0d_mask.hex",c),"w");
  for(debug_index=0;debug_index<24576;debug_index=debug_index+1)$fdisplay(debug_file,"%h",dut.segmenter.mask_mem[(!dut.segmenter.SINGLE_BUFFER && dut.segmenter.bank ? 49152:0)+(dut.segmenter.selected_mask ? 24576:0)+debug_index]);
  $fclose(debug_file);
 end
 previous_stage=stage;
end
task frame;
input integer which;
begin
 wait(!busy && !hold);
 for(i=0;i<N;i=i+1)begin
  iv=1;sop=i==0;eop=i==N-1;gray=image[which*N+i];ix=i%W;iy=i/W;@(negedge clk);
  if(i%W==W-1 || i%37==36)begin iv=0;sop=0;eop=0;repeat(3)@(negedge clk);end
 end
 iv=0;sop=0;eop=0;
 repeat(50000)@(negedge clk);
end
endtask
task report_failure;
begin
 $display("DIAG @NAME@ case%0d attempts%0d stage%0d app%0d locked%0d valid%0d ascii%s count%0d low%0d over%0d reject%0d diag%0d bbox%0d,%0d %0dx%0d capture%0d",c,attempts,stage,app,locked,valid,ascii,chars,low,over,reject,diag,bx,by,bw,bh,cf);
 $display("work_count%0d work_candidate%0d dark%0d work_low%0d OCRvalid%0d OCRascii%s",dut.segmenter.work_count,dut.segmenter.work_candidate,dut.segmenter.dark,dut.segmenter.work_low,dut.segmenter.ocr_valid,dut.segmenter.ocr_ascii);
 for(debug_index=0;debug_index<6;debug_index=debug_index+1)$display("glyph%0d box%h L%c err%0d margin%0d D%c err%0d margin%0d",debug_index,dut.segmenter.boxes[debug_index*32+:32],dut.segmenter.nz_ocr.classifier.letters[debug_index*8+:8],dut.segmenter.nz_ocr.classifier.letter_error[debug_index*10+:10],dut.segmenter.nz_ocr.classifier.letter_margin[debug_index*10+:10],dut.segmenter.nz_ocr.classifier.digits[debug_index*8+:8],dut.segmenter.nz_ocr.classifier.digit_error[debug_index*10+:10],dut.segmenter.nz_ocr.classifier.digit_margin[debug_index*10+:10]);
end
endtask
initial begin
 $readmemh("tests/generated/@NAME@_gray.hex",image);@EXPECTED@
 repeat(8)@(negedge clk);rst=1;
 frame(0);frame(0);
 if(bv || hold || locked || valid)$fatal(1,"blank input created box/freeze/result");
 for(c=1;c<=CASES;c=c+1)begin
  rearm=1;@(negedge clk);rearm=0;snapshot=0;repeat(60)@(negedge clk);
  if(hold || locked || valid || bv)$fatal(1,"rescan did not clear prior transaction");
  attempts=0;
  while(!locked && attempts<6)begin
   frame(c);attempts=attempts+1;waits=0;
   while(hold && !locked && waits<1000000)begin @(negedge clk);waits=waits+1;end
   if(waits==1000000)begin report_failure();$fatal(1,"recognition stuck");end
  end
  if(!locked || !valid || ascii!==words[c])begin report_failure();$fatal(1,"OCR expected%s",words[c]);end
  if(chars!=6 || !hold || !bv || cf==0 || bf!=cf)$fatal(1,"success transaction flags/frame invalid");
  fixed_x=bx;fixed_y=by;fixed_w=bw;fixed_h=bh;fixed_frame=cf;
  repeat(5000)begin @(negedge clk);if(bx!=fixed_x || by!=fixed_y || bw!=fixed_w || bh!=fixed_h || cf!=fixed_frame || !locked)$fatal(1,"locked result changed");end
  $display("PASS @NAME@ photo%s bbox%0d,%0d %0dx%0d capture-frame%0d sourceframes%0d",ascii,bx,by,bw,bh,cf,attempts);
 end
 if(read!=written || written!=accepted*N || closed!=accepted)$fatal(1,"frame/preview counts accepted%0d done%0d data%0d/%0d",accepted,closed,read,written);
 run=0;rearm=1;@(negedge clk);rearm=0;repeat(60)@(negedge clk);
 if(hold || locked || valid || app!=6)$fatal(1,"pause did not release freeze");
 $display("PASS @NAME@: actual Canny/history/locator/dynamic crop/filled glyph OCR, blank rejection, rescan, pause, original-gray preview and bound capture IDs");$finish;
end
initial begin repeat((CASES+3)*(N*10+2000000))@(posedge clk);$fatal(1,"core timeout stage%0d hold%0d",stage,hold);end
endmodule
'''
 for k,v in [('W',w),('H',h),('CASES',len(cases)),('NAME',name),('EXPECTED',expected)]:tb=tb.replace('@'+k+'@',str(v))
 simulate(name,tb,['src/autoplate_core.v'],timeout=600)
 return {'name':name,'width':w,'height':h,'cases':[c[0] for c in cases]}

if __name__=='__main__':
 results=[]
 if '--full-only' not in sys.argv:
  results.append(verify('autoplate_core_small',384,193,[
   ('AUY359','01_AUY359.jpg',40,36,216,72),
   ('AUY359','01_AUY359.jpg',136,104,200,64),
   ('TR7750','04_TR7750.jpg',80,48,240,80)]))
 if '--small-only' not in sys.argv:
  results.append(verify('autoplate_core_full',848,477,[('AUY359','01_AUY359.jpg',304,176,216,72)]))
 (OUT/'autoplate_core_metrics.json').write_text(json.dumps(results,indent=2))
 (OUT/'autoplate_core.log').write_text('\n'.join((OUT/(r['name']+'.log')).read_text() for r in results))
