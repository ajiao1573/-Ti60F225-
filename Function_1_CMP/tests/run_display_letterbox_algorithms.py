"""Independent Sobel/Canny model and shape fixtures at the new odd frame height."""
from pathlib import Path
import sys
import run_canny
original=run_canny.simulate
run_canny.simulate=lambda name,*a,**kw:original('display_letterbox_'+name,*a,**kw)
saved=sys.argv
try:
 if '--shape' not in sys.argv:
  code=Path('tests/run_sobel_noise.py').read_text(encoding='utf-8')
  code=code.split('# Repeated noisy flat field')[0].replace('w,h=(848,636)','w,h=(848,477)')
  sys.argv=['run_sobel_noise.py','--full']
  exec(compile(code,'tests/run_sobel_noise.py','exec'),{'__name__':'__main__'})
 else:
  code=Path('tests/run_shape_full.py').read_text(encoding='utf-8')
  code=code.replace('W,H=848,636','W,H=848,477')
  code=code.replace('(y-318)**2<=230**2','(y-238)**2<=180**2')
  code=code.replace('y<=619','y<=460').replace('*603','*444').replace('y<=634','y<=475').replace('510<=y','400<=y')
  code=code.replace('shape_detect dut(', 'shape_detect #(.WIDTH(848),.HEIGHT(477)) dut(')
  code=code.replace('848x636','848x477').replace('RAM row 634','RAM row 475').replace('2696640','2022480')
  exec(compile(code,'tests/run_shape_full.py','exec'),{'__name__':'__main__'})
finally:
 sys.argv=saved;run_canny.simulate=original
