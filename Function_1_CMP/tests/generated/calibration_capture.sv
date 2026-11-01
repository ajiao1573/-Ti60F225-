
module tb;
reg cam=0,sys=0;always #7 cam=~cam;always #5 sys=~sys;
reg rst=0,arm=0,v=0,s=0,e=0,rd=0;reg[10:0]x=0,y=0;reg[7:0]gray=0;reg[15:0]addr=0;
wire[7:0]data;wire ready;
calibration_capture d(cam,sys,rst,arm,v,s,e,x,y,gray,rd,addr,data,ready);
integer xx,yy,i,f;
function[7:0]value;input integer x,y,f;begin value=(x*3+y*5+f*17)&255;end endfunction
initial begin
 repeat(8)@(negedge cam);rst=1;
 if(ready)$fatal(1,"unarmed ready");
 for(f=0;f<2;f=f+1)begin
  @(negedge sys);arm=~arm;repeat(8)@(negedge cam);
  if(ready)$fatal(1,"stale capture ready");
  for(yy=0;yy<1080;yy=yy+1)for(xx=0;xx<1920;xx=xx+1)begin
   v=1;s=xx==0&&yy==0;e=xx==1919&&yy==1079;x=xx;y=yy;gray=value(xx,yy,f);@(negedge cam);
   if(ready)$fatal(1,"ready before final source pixel");
  end
  v=0;s=0;e=0;wait(ready);
  if(d.index!=57600)$fatal(1,"thumbnail budget %0d",d.index);
  for(i=0;i<57600;i=i+1)begin
   @(negedge sys);rd=1;addr=i;@(negedge sys);
   if(data!==value((i%320)*6,(i/320)*6,f))$fatal(1,"thumbnail address%0d value%0d",i,data);
  end
  rd=0;$display("PASS calibration frame%0d:57600 pixel-exact samples,complete-frame ACK,sys read",f);
 end
 $finish;
end
initial begin #100000000;$fatal(1,"capture timeout");end
endmodule
