"""Build with local dependencies only; never download during build/startup."""
from pathlib import Path
import argparse
import os
import subprocess
import sys

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--dist-dir", default="dist", help="Output folder relative to host/")
args = parser.parse_args()
env = os.environ.copy()
env["PYTHONPATH"] = os.pathsep.join([str(root / "build_deps"), str(root / "vendor")])
subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile",
                "--name", "Ti60PlateControl", "--distpath", str(root / args.dist_dir),
                "--workpath", str(root / "build"), "--specpath", str(root),
                "--add-data", str(root / "static") + os.pathsep + "static",
                "--add-data", str(root / "vendor" / "pyserial-3.5.dist-info") + os.pathsep + "vendor/pyserial-3.5.dist-info",
                "--paths", str(root / "vendor"), "--hidden-import", "serial.tools.list_ports_windows",
                str(root / "app.py")], cwd=root, env=env, check=True)
