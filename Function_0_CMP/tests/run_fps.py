from pathlib import Path
from run_canny import simulate
simulate('fps_osd',Path('tests/tb_fps_osd.sv').read_text(),['src/threshold_osd.v'])
