"""Production guarded/motion-aware voting at the new row width."""
import runpy
import run_canny
original=run_canny.simulate
def current(name,tb,files,**kw):
 tb=tb.replace('848','960').replace('847','959').replace('432','960').replace('awlen!=6','awlen!=7').replace('arlen!=6','arlen!=7')
 tb=tb.replace('for(yy=0;yy<6;yy=yy+1) begin\n   for(xx=0;', '''for(yy=0;yy<6;yy=yy+1) begin
   if(yy<3) for(xx=0;xx<960;xx=xx+1) begin
    if(dut.rfifo_empty || pixel!==8'((yy+xx)&255)) $fatal(1,"gray row alignment");
    de=1;@(negedge dc);
   end
   for(xx=0;''')
 original('960_guard',tb,files,**kw)
run_canny.simulate=current
runpy.run_path('tests/run_noise_fix_temporal.py',run_name='__main__')
