"""Legacy segmentation oracle at current top ROI coordinates; field adaptive/OCR paths are checked separately."""
from pathlib import Path
import re
import plate_reference as ref
from run_canny import simulate
top=Path('example_top.v').read_text(encoding='utf-8')
params=re.search(r'plate_segmenter #(.*?) u_plate_segmenter\(',top,re.S).group(1).replace('.ENABLE_NZ_OCR(1)', '.ENABLE_NZ_OCR(0)')
params=params.replace('.ADAPTIVE_THRESHOLD(1)', '.ADAPTIVE_THRESHOLD(0)').replace('.MIN_HEIGHT(12)', '.MIN_HEIGHT(24)').replace('.BLACK_INK(1)', '.BLACK_INK(0)')
coords='\n'.join(re.search(r'wire\s+\[[^\]]+\]\s+'+n+r'=.*?;',top).group(0) for n in ['roi_x','roi_y'])
assert '.in_x(roi_x),.in_y(roi_y)' in top and '.in_gray(gray_data)' in top
def actual(name,tb,files,**kw):
 tb=tb.replace('plate_segmenter #(.X_START(2),.Y_START(2),.SOURCE_WIDTH(832),.SOURCE_HEIGHT(320))', 'plate_segmenter #'+params)
 tb=tb.replace('reg [11:0] x=0,y=0;',coords.replace('full_view_x','ix').replace('full_view_y','iy')+'\nreg [11:0] x=0,y=0;')
 tb=tb.replace('.in_x(ix),.in_y(iy)', '.in_x(roi_x),.in_y(roi_y)')
 tb=tb.replace('for(yy=0;yy<320;yy=yy+1) for(xx=0;xx<832;xx=xx+1)', 'for(yy=0;yy<477;yy=yy+1) for(xx=0;xx<848;xx=xx+1)')
 tb=tb.replace('ix=xx+2;iy=yy+2;', 'ix=xx;iy=yy;')
 tb=tb.replace('gray=captured[f*266240+yy*832+xx];', 'gray=(xx>=8 && xx<840 && yy>=78 && yy<398) ? captured[f*266240+(yy-78)*832+(xx-8)] : (xx+yy)%256;')
 tb=tb.replace('for(side=0;side<2;', 'for(side=1;side<2;').replace('y=512+yy*4;', 'y=552+yy*4;')
 simulate(name,tb,files,**kw)
ref.simulate=actual
ref.run_cases([('fullframe_positive',ref.sample('AUY359'),6,128),
 ('fullframe_negative',ref.sample('DMN112',negative=True),6,128)],'plate_capture_1013',source_size=(832,320))
