"""Create an isolated, reproducible Efinity snapshot for the calibrated image."""
import hashlib,json,shutil,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--name',default='lens_corrected_build')
args=parser.parse_args()
if not args.name.replace('_','').isalnum():raise ValueError('name must be a single alphanumeric/underscore directory name')
target=ROOT/'work'/args.name
target.mkdir(parents=True,exist_ok=False)
for folder in ['src','ip']:
    shutil.copytree(ROOT/folder,target/folder)
(target/'tools').mkdir()
shutil.copy2(ROOT/'tools/build.py',target/'tools/build.py')
for name in ['example_top.v','Ti60_Demo.xml','Ti60_Demo.peri.xml','Ti60_Demo.pt.sdc','start_build.cmd']:
    shutil.copy2(ROOT/name,target/name)
files=[ROOT/'example_top.v',ROOT/'Ti60_Demo.xml',ROOT/'Ti60_Demo.peri.xml',ROOT/'Ti60_Demo.pt.sdc',
       ROOT/'docs/calibration/lens_profile_native1080.json',*sorted((ROOT/'src').rglob('*'))]
hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()}
(target/'SOURCE_SHA256.json').write_text(json.dumps(hashes,indent=2)+'\n')
print(target)
