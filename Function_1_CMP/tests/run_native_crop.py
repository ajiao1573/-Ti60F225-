"""Native-source crop: bottom-of-1080p coordinates and exact sampled pixels."""
from pathlib import Path
import ast
from run_canny import simulate
tree=ast.parse(Path('tests/run_dynamic_crop.py').read_text())
tb=next(n.value.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tb' for t in n.targets))
tb=tb.replace('[9:0]','[10:0]').replace('.DYNAMIC_ROI(1),','.DYNAMIC_ROI(1),.SINGLE_BUFFER(1),')
start=tb.index(' run_case(17,23,333,137,400,200,1);')
end=tb.index(' // No candidate',start)
tb=tb[:start]+ ' run_case(1650,1040,128,32,1920,1080,9);\n'+tb[end:]
tb=tb.replace('#30000000','#90000000').replace('PASS dynamic ROI:8 pixel-exact up/down/mixed-scale cases','PASS native1080 ROI:y1040..1071 pixel-exact source crop')
simulate('native_crop',tb,['src/plate_segmenter.v'],timeout=300)
