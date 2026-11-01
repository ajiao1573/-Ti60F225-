"""Sensitivity regression: partial occlusion, clutter and static frame repeats."""
from pathlib import Path
import json,subprocess
from run_canny import simulate,OUT
W,H=160,128
def outline(fill):
    return [int(fill(x,y) and any(not fill(x+dx,y+dy) for dx,dy in
                ((-1,0),(1,0),(0,-1),(0,1)))) for y in range(H) for x in range(W)]
circle=outline(lambda x,y:(x-80)**2+(y-64)**2<=38**2)
rectangle=outline(lambda x,y:32<=x<=128 and 28<=y<=100)
triangle=outline(lambda x,y:20<=y<=110 and 80*90-50*(y-20)<=x*90<=80*90+50*(y-20))
frames=[]
def add(name,expected,pixels):frames.append((name,expected,pixels))
for name,shape,base in (('circle',1,circle),('rectangle',2,rectangle),('triangle',3,triangle)):
    add(name+'_left_occlusion',shape,[int(v and not (56<=y<66 and x<80)) for (y,x),v in
          ((divmod(i,W),p) for i,p in enumerate(base))])
    add(name+'_missing_rows',shape,[int(v and not 56<=i//W<64) for i,v in enumerate(base)])
    add(name+'_border_lines',shape,[int(v or i%W in (0,159)) for i,v in enumerate(base)])
    add(name+'_separate_lines',shape,[int(v or (i//W==4 and 12<=i%W<=146) or
        (i%W==8 and 3<=i//W<=122) or (i%W==151 and 3<=i//W<=122)) for i,v in enumerate(base)])
    add(name+'_interior_lines',shape,[int(v or (i//W in (62,63) and 62<=i%W<=98)) for i,v in enumerate(base)])
    add(name+'_occlusion_and_lines',shape,[int((v and not (56<=i//W<66 and i%W<80)) or
        i%W in (0,159) or (i//W==4 and 12<=i%W<=146)) for i,v in enumerate(base)])
add('rectangle_partial_top',2,[int(v and not (i//W==28 and 66<=i%W<92)) for i,v in enumerate(rectangle)])
for f in range(6):add('static_circle_repeat_'+str(f),1,circle[:])
add('static_rectangle_after_circle',2,rectangle)
add('static_triangle_after_rectangle',3,triangle)
add('blank_clears',0,[0]*(W*H))
add('lines_only',0,[int(i%W in (8,80,151) or (i//W==4 and 15<=i%W<=140)) for i in range(W*H)])
add('open_U',0,[int((x in (32,128) and 28<=y<=100) or (y==100 and 32<=x<=128)) for y in range(H) for x in range(W)])
OUT.joinpath('shape_sensitivity.hex').write_text(''.join(f'{p:x}\n' for _,_,pixels in frames for p in pixels))
OUT.joinpath('shape_sensitivity_cases.json').write_text(json.dumps([{'name':n,'expected':e} for n,e,_ in frames],indent=2))
init='\n'.join(f' expected[{i}]=2\'d{e};' for i,(_,e,_) in enumerate(frames))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,s=0,e=0,p=0;wire [1:0] shape;wire done;
 shape_detect #(.WIDTH({W}),.HEIGHT({H})) dut(clk,rst,1'b1,v,s,e,p,shape,done,);
 reg pixels[0:{len(frames)*W*H-1}];reg [1:0] expected[0:{len(frames)-1}];integer f,i,n=0,t;
 initial begin
  $readmemh("tests/generated/shape_sensitivity.hex",pixels);
{init}
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<{len(frames)};f=f+1) begin
   for(i=0;i<{W*H};i=i+1) begin @(negedge clk);v=1;s=i==0;e=i=={W*H-1};p=pixels[n];n=n+1;end
   @(negedge clk);v=0;s=0;e=0;t=0;
   while(!done && t<300000) begin @(negedge clk);t=t+1;end
   $display("RESULT %0d %0d %0d",f,shape,expected[f]);
   if(!done || shape!==expected[f]) begin
    $display("last slot w=%0d h=%0d area=%0d bad=%0d errors=%0d/%0d/%0d/%0d cap=%b%b best=%0d",dut.box_w,dut.box_h,dut.area,dut.bad_rows,dut.rect_error,dut.circle_error,dut.up_error,dut.down_error,dut.top_closed,dut.bottom_closed,dut.best_shape);
    $fatal(1,"sensitivity frame=%0d shape=%0d expected=%0d done=%0d",f,shape,expected[f],done);
   end
   repeat(6) @(negedge clk);
  end
  $display("PASS sensitivity: {len(frames)} occlusion/clutter/static frames, blank clear and line/U rejection");$finish;
 end
endmodule
'''
try:simulate('shape_sensitivity',tb,['src/shape_detect.v'])
except subprocess.CalledProcessError as error:
    print(error.stdout or '');raise

# Observe the previous implementation on the SAME frames, without changing
# expected answers. This quantifies improvement rather than redefining tests.
old=tb[:tb.index('   if(!done || shape')]+'''   if(!done) $fatal(1,"baseline timeout");
   repeat(6) @(negedge clk);
  end
  $finish;
 end
endmodule
'''
simulate('shape_sensitivity_baseline',old.replace('shape,done,);','shape,done);'),['backup_before_shape_dp_hough/src/shape_detect.v'])
def accuracy(path):
    rows=[line.split() for line in path.read_text().splitlines() if line.startswith('RESULT ')]
    positive=[r for r in rows if r[3]!='0']
    return {'positive_hits':sum(r[2]==r[3] for r in positive),'positive_frames':len(positive),
            'negative_hits':sum(r[2]=='0' for r in rows if r[3]=='0'),'negative_frames':len(rows)-len(positive)}
report={'baseline':accuracy(OUT/'shape_sensitivity_baseline.log'),'optimized':accuracy(OUT/'shape_sensitivity.log')}
OUT.joinpath('shape_sensitivity_comparison.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
