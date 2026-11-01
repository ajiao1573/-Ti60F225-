from pathlib import Path
import json
from PIL import Image
from plate_reference import run_cases
root=Path('tests/plate_samples')
records=json.loads((root/'sources.json').read_text(encoding='utf-8'))
cases=[]
for r in records:
    image=Image.open(root/r['test_filename']).convert('L').resize((256,96),Image.Resampling.LANCZOS)
    cases.append((r['plate'],image,len(r['plate']),128))
run_cases(cases,'plate_photos')
