"""Temporal hysteresis reference and the implemented top -> HDMI wiring."""
from pathlib import Path
from collections import Counter
import random,subprocess,json
from run_canny import simulate,OUT

# Lists of recognised frames form the reference; idle clocks cannot count as
# new evidence. Include explicit boundaries, alternate labels and fixed noise.
operations=[]
def frames(values):
    for value in values:
        operations.append((1,1,1,value))
        operations.extend((1,1,0,3) for _ in range(2))
frames([1,0,1,0,1])                  # 3/5, including non-consecutive votes
frames([2,0,1,3,1,0,0,1]*6)        # brief misses and isolated wrong labels
frames([2,2,2,2])                   # 4/5 replacement, no intermediate blank
operations.extend((1,1,0,0) for _ in range(40))
frames([0]*7+[2])                   # seventh miss holds; incumbent recovers
frames([0]*8)                       # exactly eighth consecutive miss clears
frames([1,2]*6)                     # acquire majority, reject 50/50 switching
frames([2,0,3,2,0,3,2,0])          # ambiguous absence also expires
frames([3,3,3])
operations.extend([(1,0,0,0)]*3)    # mode exit immediately clears old votes
frames([2,2,2])
operations.extend([(0,1,0,0),(1,1,0,0)])
frames([3,3,3])
rng=random.Random(914)
operations.extend((1,int(rng.random()>.04),int(rng.random()>.25),rng.randrange(4)) for _ in range(1200))

def reference(ops,acquire=3,switch=4,lost=8):
    window=[];stable=miss=0;expected=[]
    for reset,en,valid,sample in ops:
        before=stable
        if not reset or not en:
            window=[];stable=miss=0
        elif valid:
            window=(window+[sample])[-5:]
            counts=Counter(window)
            if stable==0:
                miss=0
                stable=next((v for v in (1,2,3) if counts[v]>=acquire),0)
            else:
                replacement=next((v for v in (1,2,3) if counts[v]>=switch),0)
                if replacement and replacement!=stable:
                    stable=replacement;miss=0
                elif sample==stable:miss=0
                else:
                    miss+=1
                    if miss>=lost:stable=miss=0;window=[]
        expected.append((stable,int(bool(reset) and stable!=before)))
    return expected

expected=reference(operations)
OUT.joinpath('shape_stability.hex').write_text(''.join(
    f'{(reset<<8)|(en<<7)|(valid<<6)|(raw<<4)|(stable<<1)|event:03x}\n'
    for (reset,en,valid,raw),(stable,event) in zip(operations,expected)))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=0,valid=0;reg [1:0] raw=0;wire [1:0] stable;wire changed;
 shape_stabilizer dut(clk,rst,en,valid,raw,stable,changed);
 reg [8:0] samples[0:{len(operations)-1}];integer i;
 initial begin
  $readmemh("tests/generated/shape_stability.hex",samples);
  repeat(3) @(negedge clk);
  for(i=0;i<{len(operations)};i=i+1) begin
   rst=samples[i][8];en=samples[i][7];valid=samples[i][6];raw=samples[i][5:4];
   @(negedge clk);
   if(stable!==samples[i][2:1] || changed!==samples[i][0])
    $fatal(1,"stability step=%0d raw=%0d stable=%0d expected=%0d event=%0d expected_event=%0d",i,raw,stable,samples[i][2:1],changed,samples[i][0]);
  end
  $display("PASS shape temporal reference: {len(operations)} clocks, 3/5 acquisition, 4/5 replacement, exact eight-miss expiry, alternating/noisy classes, idle/skipped frames, mode exit and reset");$finish;
 end
endmodule
'''
simulate('shape_stability',tb,['src/shape_stabilizer.v'])

# Extract BOTH producer/filter connections and existing HDMI CDC from the real
# top, feeding geometric edge frames through the actual recogniser.
top=Path('example_top.v').read_text(encoding='utf-8')
producer=top[top.index('    wire [1:0] shape_raw_result'):top.index('\t// Gray stream is emitted')]
producer=producer.replace('.WIDTH(848),.HEIGHT(477)','.WIDTH(64),.HEIGHT(56)')
assert '.WIDTH(64),.HEIGHT(56)' in producer, 'Top shape dimensions changed; update the fixture explicitly'
cdc=top[top.index('    // Bundled result'):top.index('    wire [23:0] shape_rgb')]
W,H=64,56
fills={0:lambda x,y:False,
       1:lambda x,y:(x-32)**2+(y-28)**2<=18**2,
       2:lambda x,y:10<=x<=53 and 10<=y<=45,
       3:lambda x,y:8<=y<=47 and 32*39+(8-32)*(y-8)<=x*39<=32*39+(56-32)*(y-8)}
sequence=[1,1,1]+[0,1,2,1,3,1]*4+[2]*4+[0]*8+[3]*3
outcomes=[s for s,_ in reference([(1,1,1,v) for v in sequence])]
raw_transitions=sum(a!=b for a,b in zip([0]+sequence,sequence))
stable_transitions=sum(a!=b for a,b in zip([0]+outcomes,outcomes))
pixels=[]
for v in sequence:
    fill=fills[v]
    pixels.extend(int(fill(x,y) and any(not fill(x+dx,y+dy) for dx,dy in
                  ((-1,0),(1,0),(0,-1),(0,1)))) for y in range(H) for x in range(W))
OUT.joinpath('shape_stability_pipeline.hex').write_text(''.join(f'{v:x}\n' for v in pixels))
init='\n'.join(f' raw_expected[{i}]=2\'d{v};stable_expected[{i}]=2\'d{outcomes[i]};' for i,v in enumerate(sequence))
tb=f'''`timescale 1ns/1ps
module tb;
 reg cmos_pclk=0;always #5 cmos_pclk=~cmos_pclk;
 reg clk_pixel=0;always #7 clk_pixel=~clk_pixel;
 reg rstn_sys=0,rstn_pixel=0,shape_requested=1;
 reg canny_valid=0,canny_sop=0,canny_eop=0;reg [7:0] canny_data=0;
 wire shape_busy;reg fps_vsync_d=0,lcd_vs=1;
{producer}
{cdc}
 reg pixels[0:{len(pixels)-1}];reg [1:0] raw_expected[0:{len(sequence)-1}],stable_expected[0:{len(sequence)-1}];
 integer f,i,n=0,t,raw_changes=0,stable_changes=0;reg [1:0] previous_raw=0,previous_stable=0;
 task blank;
  begin
   @(negedge clk_pixel);fps_vsync_d=1;lcd_vs=0;
   @(negedge clk_pixel);fps_vsync_d=0;lcd_vs=1;
  end
 endtask
 initial begin
  $readmemh("tests/generated/shape_stability_pipeline.hex",pixels);
{init}
  repeat(5) @(negedge cmos_pclk);rstn_sys=1;rstn_pixel=1;
  for(f=0;f<{len(sequence)};f=f+1) begin
   for(i=0;i<{W*H};i=i+1) begin
    @(negedge cmos_pclk);canny_valid=1;canny_sop=i==0;canny_eop=i=={W*H-1};canny_data=pixels[n] ? 255 : 0;n=n+1;
   end
   @(negedge cmos_pclk);canny_valid=0;canny_sop=0;canny_eop=0;t=0;
   while(!shape_raw_valid && t<300000) begin @(negedge cmos_pclk);t=t+1;end
   if(!shape_raw_valid || shape_raw_result!==raw_expected[f]) $fatal(1,"raw recognition f=%0d shape=%0d",f,shape_raw_result);
   repeat(10) @(negedge clk_pixel);
   if(shape_result!==stable_expected[f] || shape_pending!==stable_expected[f]) $fatal(1,"filter/top CDC f=%0d stable=%0d expected=%0d pending=%0d",f,shape_result,stable_expected[f],shape_pending);
   if(shape_display!==previous_stable) $fatal(1,"label changed inside HDMI frame");
   blank;
   if(shape_display!==stable_expected[f]) $fatal(1,"filtered result failed blank commit");
   raw_changes=raw_changes+(previous_raw!=raw_expected[f]);previous_raw=raw_expected[f];
   stable_changes=stable_changes+(previous_stable!=shape_display);previous_stable=shape_display;
   repeat(2) begin blank;if(shape_display!==previous_stable) $fatal(1,"display refresh counted as recognition evidence");end
  end
  if(raw_changes!={raw_transitions} || stable_changes!={stable_transitions}) $fatal(1,"unexpected label transition counts %0d %0d",raw_changes,stable_changes);
  @(negedge cmos_pclk);shape_requested=0;repeat(10) @(negedge clk_pixel);blank;
  if(shape_display!==0 || shape_result!==0) $fatal(1,"mode exit failed immediate clear");
  shape_requested=1;repeat(12) @(negedge clk_pixel);blank;
  if(shape_display!==0 || shape_result!==0) $fatal(1,"old label revived on mode reentry");
  $display("PASS actual recogniser -> temporal filter -> top CDC -> HDMI: {len(sequence)} geometric frames, raw transitions=%0d stable transitions=%0d, misses, class replacement, target removal, blank commits, repeated display refresh, mode exit/reentry",raw_changes,stable_changes);$finish;
 end
endmodule
'''
try:simulate('shape_stability_pipeline',tb,['src/shape_detect.v','src/shape_stabilizer.v'])
except subprocess.CalledProcessError as error:print(error.stdout or '');raise
OUT.joinpath('shape_stability_comparison.json').write_text(json.dumps({
    'frames':len(sequence),'raw_label_changes':raw_transitions,
    'stable_label_changes':stable_transitions,'acquire_votes':3,
    'switch_votes':4,'window_frames':5,'consecutive_misses_to_clear':8,
    'note':'Synthetic intermittent misses/competing labels plus real target changes; not camera accuracy.'},indent=2)+'\n')
