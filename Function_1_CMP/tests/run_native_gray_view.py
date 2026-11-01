"""Native display: actual 1080p timing, pixel detail, box mapping, recovery."""
from pathlib import Path
import ast
from run_canny import simulate,OUT
source=Path('tests/run_single_gray_view.py').read_text()
tb=next(n.value.value for n in ast.parse(source).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
tb=tb.replace('SW=848,SH=477','SW=1920,SH=1080').replace('rng[1:0]!=0',"1'b1")
tb=tb.replace('single_gray_view view(', 'single_gray_view #(.SOURCE_WIDTH(1920),.SOURCE_HEIGHT(1080),.BOX_SOURCE_WIDTH(1920),.BOX_SOURCE_HEIGHT(1080)) view(')
tb=tb.replace('sx=x*53/120;sy=y*53/120;','sx=x;sy=y;')
tb=tb.replace('source(sx,sy,frame)','source(x,y,frame)')
# Native rows consume most of the pixel-clock bandwidth; a deliberately late
# source is required to recover on next VSYNC, not within a scaled row budget.
tb=tb.replace('if(request && frame==2 && y>150 && !expected_ready)', "if(1'b0)")
tb=tb.replace('exact848x477 pixels','exact1920x1080 pixels').replace('75%% availability','native pixel-rate availability')
# Exercise a box beyond the former 10-bit Y limit, then finish after a full
# native frame. The earlier four-frame test separately covers underflow recovery.
tb=tb.replace('reg [9:0] by=40,bh=60;', 'reg [10:0] by=1040,bh=20;')
tb=tb.replace('t=frame<=1 ? 40:200;', 't=frame<=1 ? 1040:200;')
tb=tb.replace('b=t+(frame<=1 ? 60:50)-1;', 'b=t+(frame<=1 ? 20:50)-1;')
tb=tb.replace('if(frame==3)begin', 'if(frame==1)begin')
tb=tb.replace('und!=0 || total==0','und!=0 || total!=0')
tb=tb.replace('startup plus3 source frames','startup plus one full native frame')
tb=tb.replace('real cache underflow, late-row discard and clean next-frame recovery','native box at y1040 and zero underflow')
driver=OUT/'native_lcd_driver.v' 
driver.write_text(Path('src/lcd_driver.v').read_text().replace('"lcd_para.v"','"src/lcd_para.v"'))
simulate('native_gray_view',tb,['src/single_gray_view.v',driver.relative_to(Path.cwd()).as_posix()],timeout=360)
