"""Direct Icarus path: ivlpp -> ivl -> vvp.

The bundled iverilog driver exits 127 / crashes on this machine, exactly as the
Canny hand-off reported, so every simulation uses the same isolated path:
preprocess with ivlpp.exe, compile with ivl.exe plus a generated configuration,
run the resulting vvp with vvp.exe.  Nothing is installed.

  python tools/run_sim.py --tag NAME --root TOP --tb tests/x.v
                          [--src src/a.v ...] [--inc DIR ...] [--plus +K=V ...]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent
TOOLS = Path(r"C:\qian\ti60_A_960x720_60fps_stable\tools\sim\mingw64")
BIN = TOOLS / "bin"
IVL = TOOLS / "lib" / "ivl"
WORK = PROJ / "build" / "sim"
LOGS = PROJ / "logs"

# ivl.exe / vvp.exe live in lib/ivl but need the DLLs that sit in bin/.
SIMENV = {**os.environ,
          "PATH": str(BIN) + os.pathsep + str(IVL) + os.pathsep + os.environ.get("PATH", ""),
          "PYTHONDONTWRITEBYTECODE": "1"}

CFG_TEMPLATE = """root:{root}
basedir:{ivl}
module:{ivl}\\system.vpi
module:{ivl}\\vhdl_sys.vpi
module:{ivl}\\vhdl_textio.vpi
module:{ivl}\\v2005_math.vpi
module:{ivl}\\va_math.vpi
module:{ivl}\\v2009.vpi
generation:2012
generation:no-specify
generation:no-interconnect
generation:assertions
generation:xtypes
generation:io-range-error
generation:no-strict-ca-eval
generation:no-strict-expr-width
generation:shared-loop-index
generation:no-verilog-ams
generation:icarus-misc
warnings:n
ignore_missing_modules:false
out:{out}
iwidth:32
widthcap:65536
"""


def run(cmd, log):
    t0 = time.time()
    with open(log, "w", encoding="utf-8") as fh:
        code = subprocess.run([str(c) for c in cmd], cwd=str(PROJ), stdout=fh,
                              stderr=subprocess.STDOUT,
                              env=SIMENV).returncode
    return code, round(time.time() - t0, 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--tb", required=True)
    ap.add_argument("--src", action="append", default=[])
    ap.add_argument("--inc", action="append", default=[])
    ap.add_argument("--plus", action="append", default=[])
    ap.add_argument("--keep-pp", action="store_true")
    a = ap.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    pp = WORK / (a.tag + ".pp.v")
    cfg = WORK / (a.tag + ".cfg")
    vvp = WORK / (a.tag + ".vvp")

    # ivlpp has no -I switch: `include paths stay relative to the project root.
    srcs = [a.tb] + a.src
    code, secs = run([IVL / "ivlpp.exe", "-L", "-o", pp, *srcs],
                     LOGS / (a.tag + "_preprocess.log"))
    rec = {"tag": a.tag, "stage": "ivlpp", "exit": code, "seconds": secs}
    (PROJ / "verification").mkdir(exist_ok=True)
    with open(PROJ / "verification" / "commands.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
    if code != 0:
        print(f"FAIL {a.tag}: ivlpp exit {code}, see logs/{a.tag}_preprocess.log")
        return 1

    cfg.write_text(CFG_TEMPLATE.format(root=a.root, ivl=str(IVL), out=str(vvp)),
                   encoding="utf-8")
    code, secs = run([IVL / "ivl.exe", "-v", "-C", cfg, "-C", IVL / "vvp.conf", "--", pp],
                     LOGS / (a.tag + "_compile.log"))
    rec = {"tag": a.tag, "stage": "ivl", "exit": code, "seconds": secs}
    with open(PROJ / "verification" / "commands.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
    if code != 0 or not vvp.exists():
        print(f"FAIL {a.tag}: ivl exit {code}, see logs/{a.tag}_compile.log")
        return 1

    code, secs = run([BIN / "vvp.exe", vvp, *a.plus], LOGS / (a.tag + "_run.log"))
    rec = {"tag": a.tag, "stage": "vvp", "exit": code, "seconds": secs,
           "plusargs": a.plus, "log": f"logs/{a.tag}_run.log"}
    with open(PROJ / "verification" / "commands.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
    text = (LOGS / (a.tag + "_run.log")).read_text(encoding="utf-8", errors="replace")
    tail = text.splitlines()
    for line in tail[-12:]:
        print("   ", line)
    # A run only counts as a pass when the bench itself printed no failure.
    # vvp exits 0 even when a test bench reports FAIL, so the log is authoritative.
    bad = [ln for ln in tail if ln.lstrip().startswith("FAIL")]
    if not a.keep_pp:
        for p in (pp,):
            p.unlink(missing_ok=True)
    if code != 0:
        return 1
    if bad:
        print(f"FAIL {a.tag}: {len(bad)} failure line(s) in logs/{a.tag}_run.log")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
