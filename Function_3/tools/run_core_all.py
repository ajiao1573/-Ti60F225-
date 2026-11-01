"""Run the numeric-core checkpoint bench over every generated vector set.

Six images x (full point set, quarter-rate subset) = 12 runs.  The module
``ml_num_core`` is compiled once per tag because the bench picks its vectors
through plusargs; a run only counts as passing when the bench prints
``TEST:PASS``.  Results are appended to ``verification/core_results.json``.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

PROJ = Path(__file__).resolve().parents[1]
CORE = PROJ / "verification" / "core"
LOGS = PROJ / "logs"


def main():
    man = json.loads((CORE / "manifest.json").read_text(encoding="utf-8"))
    counts = {r["tag"]: r["n_points"] for r in man["runs"]}
    tags = sorted(p.name[:-len(".pts.hex")] for p in CORE.glob("*.pts.hex"))
    if not tags:
        print("no vector sets; run tools/gen_core_vectors.py first")
        return 1
    rows = []
    bad = 0
    for tag in tags:
        pts = CORE / f"{tag}.pts.hex"
        exp = CORE / f"{tag}.exp.hex"
        npts = counts[tag]
        t0 = time.time()
        cmd = [sys.executable, str(PROJ / "tools" / "run_sim.py"),
               "--tag", "core_" + tag.replace(".", "_"),
               "--root", "tb_ml_num_core", "--tb", "tests/tb_ml_num_core.v",
               "--src", "src/ml_num_core.v", "--src", "src/ml_num_au.v",
               "--src", "src/ml_int13_classifier.v",
               "--plus", f"+PTS={pts.relative_to(PROJ).as_posix()}",
               "--plus", f"+EXP={exp.relative_to(PROJ).as_posix()}",
               "--plus", f"+N={npts}"]
        r = subprocess.run(cmd, cwd=str(PROJ), capture_output=True, text=True)
        log = LOGS / ("core_" + tag.replace(".", "_") + "_run.log")
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
        ok = "TEST:PASS" in text
        m = re.search(r"CK seen=(\d+) errs=(\d+) missing=(\d+)", text)
        m2 = re.search(r"core done after (\d+) cycles valid=(\d) reason=(\d+)", text)
        rows.append({"tag": tag, "n_points": npts, "pass": ok,
                     "checkpoints": int(m.group(1)) if m else None,
                     "errs": int(m.group(2)) if m else None,
                     "missing": int(m.group(3)) if m else None,
                     "cycles": int(m2.group(1)) if m2 else None,
                     "valid": int(m2.group(2)) if m2 else None,
                     "reason": int(m2.group(3)) if m2 else None,
                     "seconds": round(time.time() - t0, 1),
                     "log": f"logs/{log.name}"})
        if not ok:
            bad += 1
        print(f"{tag:44s} n={npts:3d} {'PASS' if ok else 'FAIL'} "
              f"ck={rows[-1]['checkpoints']} errs={rows[-1]['errs']} "
              f"cyc={rows[-1]['cycles']} {rows[-1]['seconds']}s", flush=True)
    (PROJ / "verification" / "core_results.json").write_text(
        json.dumps({"runs": rows, "failures": bad}, indent=1), encoding="utf-8")
    print(f"runs={len(rows)} failures={bad}")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
