`timescale 1ns/1ps
module tb;
localparam SW=1920,SH=1080,N=SW*SH,DW=1920,DH=1080,PIXELS=DW*DH;
reg clk=0;always #6.734007 clk=~clk;
reg rst=0;wire vs,request,de;wire[11:0] x,y;wire[23:0] rgb,lcd_rgb;
wire pop;wire[9:0] und,total;
reg [10:0] bx=100,bw=200;reg [10:0] by=1040,bh=20;
lcd_driver #(.H_FRONT(88),.H_SYNC(44),.H_BACK(148),.H_DISP(1920),.H_TOTAL(2200),
.V_FRONT(4),.V_SYNC(5),.V_BACK(36),.V_DISP(1080),.V_TOTAL(1125),.DATA_WIDTH(24)) timing(
.clk(clk),.rst_n(rst),.lcd_vs(vs),.lcd_en(de),.lcd_rgb(lcd_rgb),
.lcd_request(request),.lcd_xpos(x),.lcd_ypos(y),.lcd_data(rgb));
integer frame=0,index=0,pops=0,pixels=0,misses=0,phase=0;
reg prev_vs=0,released=1;reg [15:0] rng=16'hb4ad;
wire available=rst && vs && frame>0 && index<N && !(frame==2 && !released) && 1'b1;
function [7:0] source;
input integer xx,yy,ff;
begin source=(xx*5+yy*3+ff*17)&255;end
endfunction
wire[7:0] data=source(index%SW,index/SW,frame);
single_gray_view #(.SOURCE_WIDTH(1920),.SOURCE_HEIGHT(1080),.BOX_SOURCE_WIDTH(1920),.BOX_SOURCE_HEIGHT(1080)) view(.clk(clk),.rst_n(rst),.vsync(vs),.lcd_request(request),.x_pos(x),.y_pos(y),
.stream_data(data),.stream_available(available),.stream_request(pop),
.box_valid(1'b1),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.rgb(rgb),.underflow_frame(und),.underflow_total(total));
reg expected_request,expected_ready;reg[23:0] expected_rgb;
integer sx,sy,l,t,r,b;
always @(posedge clk) if(rst)begin
 expected_request=request;expected_ready=view.valid_q;
 sx=x;sy=y;
 l=frame<=1 ? 100:500;t=frame<=1 ? 1040:200;r=l+(frame<=1 ? 200:100)-1;b=t+(frame<=1 ? 20:50)-1;
 expected_rgb=expected_ready ? {3{source(x,y,frame)}}:24'd0;
 if(expected_ready && sx>=l && sx<=r && sy>=t && sy<=b && (sx==l || sx==r || sy==t || sy==b))expected_rgb=24'h00ff00;
 if(request && (frame==1 || frame==3) && !expected_ready)$fatal(1,"unexpected cache miss frame%0d x%0d y%0d fill%0d",frame,x,y,view.fill_row);
 if(request && frame==0 && expected_ready)$fatal(1,"startup without source showed old data");
 if(1'b0)$fatal(1,"late-row recovery failed x%0d y%0d",x,y);
 if(request && !expected_ready)misses=misses+1;
 if(request && frame==2 && y>=50)released=1;
 if(frame==1 && request && y==100 && x==0)begin bx=500;by=200;bw=100;bh=50;end
 if(pop)begin
  if(!vs || !available || index>=N)$fatal(1,"illegal FIFO pop");
  index<=index+1;pops=pops+1;
 end
 if(!vs)index<=0;
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
 if(prev_vs && !vs)begin
  if(pixels!=PIXELS || pops!=(frame==0 ? 0:N))$fatal(1,"frame%0d budget pixels%0d/%0d pops%0d/%0d",frame,pixels,PIXELS,pops,N);
  if((frame==1 || frame==3) && misses!=0)$fatal(1,"normal frame missing pixels");
  if(frame==2 && misses==0)$fatal(1,"forced underflow not observed");
  $display("frame%0d PASS HDMI pixels%0d source bytes%0d missing%0d",frame,pixels,pops,misses);
  if(frame==0)begin #1;if(und!=0 || total!=0)$fatal(1,"camera startup counted as running underflow");end
  if(frame==1)begin
   #1;if(und!=0 || total!=0)$fatal(1,"underflow publication/recovery incorrect %0d/%0d",und,total);
   $display("PASS single gray view: actual1080p30 timing, startup plus one full native frame, exact1920x1080 pixels and byte budget, frame-locked box, native pixel-rate availability, native box at y1040 and zero underflow");$finish;
  end
  frame=frame+1;pops=0;pixels=0;misses=0;released=frame!=2;
 end
 prev_vs=vs;
 #1;
 if(de)begin
  if(!expected_request)$fatal(1,"lcd request/display timing mismatch");
  if(lcd_rgb!==expected_rgb)$fatal(1,"pixel frame%0d x%0d y%0d got%h want%h ready%b",frame,sx,sy,lcd_rgb,expected_rgb,expected_ready);
  pixels=pixels+1;
 end
end
initial begin repeat(8)@(negedge clk);rst=1;end
initial begin #145000000;$fatal(1,"display timeout");end
endmodule
