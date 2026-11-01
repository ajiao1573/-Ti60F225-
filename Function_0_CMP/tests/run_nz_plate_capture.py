"""Run lock/recognition against actual top ROI parameters and 848x477 frames."""
from pathlib import Path
import re,runpy
import run_canny
original=run_canny.simulate
top=Path('example_top.v').read_text(encoding='utf-8')
params=re.search(r'plate_segmenter #(.*?) u_plate_segmenter\(',top,re.S).group(1)
coords='\n'.join(re.search(r'wire\s+\[[^\]]+\]\s+'+name+r'=.*?;',top).group(0)
 for name in ['roi_x','roi_y']).replace('full_view_x','ix').replace('full_view_y','iy')

def actual(name,tb,files,**kw):
    raw=[int(line,16) for line in Path('tests/generated/nz_lock_input.hex').read_text().splitlines()]
    xgrid={8+i*832//256:i for i in range(256)}
    ygrid={78+i*320//96:i for i in range(96)}
    with Path('tests/generated/nz_capture_input.hex').open('w') as out:
        for frame in range(5):
            for y in range(477):
                sy=ygrid.get(y)
                out.write(''.join(f'{raw[frame*24576+sy*256+xgrid[x]] if sy is not None and x in xgrid else 245:02x}\n' for x in range(848)))
    tb=tb.replace('reg [10:0] ix=0;reg [9:0] iy=0;', 'reg [10:0] ix=0;reg [9:0] iy=0;\n'+coords)
    tb=tb.replace('plate_segmenter #(.X_START(2),.Y_START(2),.ENABLE_NZ_OCR(1))','plate_segmenter #'+params)
    tb=tb.replace('.in_x(ix),.in_y(iy)', '.in_x(roi_x),.in_y(roi_y)')
    tb=tb.replace('images[0:122879]','images[0:2022479]').replace('nz_lock_input.hex','nz_capture_input.hex')
    tb=tb.replace('for(y=0;y<96;y=y+1) for(x=0;x<256;x=x+1)', 'for(y=0;y<477;y=y+1) for(x=0;x<848;x=x+1)')
    tb=tb.replace('ix=x+2;iy=y+2;gray=images[index*24576+y*256+x];','ix=x;iy=y;gray=images[index*404496+y*848+x];')
    tb=tb.replace('#100000000;', '#200000000;')
    original('nz_plate_capture_1013',tb,files,**kw)
run_canny.simulate=actual
runpy.run_path('tests/run_nz_plate_lock.py',run_name='__main__')