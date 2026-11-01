"""Production ROI sizes, last RAM row and actual top-level result CDC."""
from pathlib import Path
from run_canny import simulate,OUT
W,H=848,636
fills=[lambda x,y:(x-424)**2+(y-318)**2<=230**2,
       lambda x,y:64<=x<=783 and 16<=y<=619,
       lambda x,y:16<=y<=619 and 424*603+(64-424)*(y-16)<=x*603<=424*603+(783-424)*(y-16),
       lambda x,y:200<=x<=640 and 510<=y<=634,
       lambda x,y:False]
pixels=[]
for fill in fills:
    pixels.extend(int(fill(x,y) and any(not fill(x+dx,y+dy) for dx,dy in
                       ((-1,0),(1,0),(0,-1),(0,1)))) for y in range(H) for x in range(W))
OUT.joinpath('shape_full.hex').write_text(''.join(f'{v:x}\n' for v in pixels))
tb=f'''`timescale 1ns/1ps
module tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,sop=0,eop=0,edge_pixel=0;wire [1:0] shape;wire done;
 shape_detect dut(clk,rst,1'b1,valid,sop,eop,edge_pixel,shape,done,);
 reg edges[0:{len(pixels)-1}];reg [1:0] expected[0:4];integer f,i,n=0,timeout;
 initial begin
  $readmemh("tests/generated/shape_full.hex",edges);
  expected[0]=1;expected[1]=2;expected[2]=3;expected[3]=2;expected[4]=0;
  repeat(5) @(negedge clk);rst=1;
  for(f=0;f<5;f=f+1) begin
   for(i=0;i<{W*H};i=i+1) begin
    @(negedge clk);valid=1;sop=i==0;eop=i=={W*H-1};edge_pixel=edges[n];n=n+1;
   end
   @(negedge clk);valid=0;sop=0;eop=0;timeout=0;
   while(!done && timeout<300000) begin @(negedge clk);timeout=timeout+1;end
   if(!done || shape!==expected[f]) $fatal(1,"full ROI f=%0d shape=%0d expected=%0d",f,shape,expected[f]);
   repeat(6) @(negedge clk);
  end
  $display("PASS 848x636 recognition: large circle/rectangle/triangle, target at RAM row 634, blank clears, 2696640 input pixels");$finish;
 end
endmodule
'''
simulate('shape_full',tb,['src/shape_detect.v'])

# Extract the implemented CDC and frame-boundary logic, so this checks top RTL.
top=Path('example_top.v').read_text(encoding='utf-8')
logic=top[top.index('    // Bundled result'):top.index('    wire [23:0] shape_rgb')]
tb='''`timescale 1ns/1ps
module tb;
 reg clk_pixel=0;always #7 clk_pixel=~clk_pixel;
 reg camera_clk=0;always #5 camera_clk=~camera_clk;
 reg rstn_pixel=0,shape_result_toggle=0;reg [1:0] shape_result=0;
 reg fps_vsync_d=0,lcd_vs=1;
'''+logic+'''
 task publish;input [1:0] value;
  begin @(negedge camera_clk);shape_result=value;
   @(negedge camera_clk);shape_result_toggle=~shape_result_toggle;
   repeat(8) @(negedge clk_pixel);
   if(shape_pending!==value) $fatal(1,"pending result CDC");
  end
 endtask
 task vertical_blank;input [1:0] value;
  begin fps_vsync_d=1;lcd_vs=0;@(negedge clk_pixel);fps_vsync_d=0;lcd_vs=1;
   if(shape_display!==value) $fatal(1,"result did not commit at blank");
  end
 endtask
 initial begin
  repeat(4) @(negedge clk_pixel);rstn_pixel=1;
  publish(1);if(shape_display!==0) $fatal(1,"frame tear before first blank");vertical_blank(1);
  publish(2);if(shape_display!==1) $fatal(1,"frame tear rectangle");vertical_blank(2);
  publish(3);if(shape_display!==2) $fatal(1,"frame tear triangle");vertical_blank(3);
  publish(0);if(shape_display!==3) $fatal(1,"frame tear unknown");vertical_blank(0);
  rstn_pixel=0;@(negedge clk_pixel);if(shape_display!==0 || shape_pending!==0) $fatal(1,"CDC reset");
  $display("PASS actual top shape result CDC: independent clocks, both toggle directions, stable labels within HDMI frame, blank commits, reset");$finish;
 end
endmodule
'''
simulate('shape_cdc',tb,[])
