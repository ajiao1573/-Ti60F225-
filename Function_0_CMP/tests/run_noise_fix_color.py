import runpy
import run_canny
original=run_canny.simulate
def current(name,tb,files,**kw):
 tb=tb.replace('.TEMPORAL_ENABLE(1),','.TEMPORAL_ENABLE(1),.CONFIG_GUARD(1),.MOTION_PROTECT(1),')
 tb=tb.replace('.temporal_requested(temporal)',".temporal_requested(temporal),.edge_configuration(12'h001),.edge_protect(ed!=0)")
 tb=tb.replace('vote=(a&b)|(a&c)|(b&c);','vote=a;')
 original('noise_fix_color_concurrency',tb,files,**kw)
run_canny.simulate=current
runpy.run_path('tests/run_temporal_color_speed.py',run_name='__main__')
