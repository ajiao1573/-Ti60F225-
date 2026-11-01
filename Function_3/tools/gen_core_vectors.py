"""Replay the hardware model with checkpoints and emit the numeric-core vectors.

The numeric core (``src/ml_num_core.v``) is a hand-written sequencer, so the
test bench needs more than the final 13 features: it must be able to say *which
stage* diverged.  This script re-runs ``tools/hwmodel.py`` stage by stage -- the
same calls in the same order as ``hwmodel.fit`` -- records a named checkpoint
after every stage, and asserts that the replayed result is identical to
``hwmodel.fit`` / ``hwmodel.features`` / ``hwmodel.classify``.

Outputs (verification/core/):
  <tag>.pts.hex   944 words: point record i at 0x000+2i (raw) and 0x001+2i (U,V)
  <tag>.exp.hex   256 lines of 17 hex digits: {3'b0, set, value[63:0]}
  manifest.json   fingerprints + expected final results
``<tag>`` is the image stem for the full set and ``<stem>.sub`` for the
quarter-rate subset used while debugging (same code path, fewer points).
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJ / "tools"))
REF = Path(r"C:/Users/17734/Documents/Codex/2026-10-26/c-users-17734-documents-codex-2026/outputs/FINITE_FEATURE_CORE_V1")
POINTS = REF / "artifacts" / "points"
CLS = Path(r"C:/Users/17734/Documents/Codex/2026-10-27/outer-classifier-integer/outputs")

import hwmodel as hw  # noqa: E402

SIDE_CODE = {"T": 0, "R": 1, "B": 2, "L": 3}

CK_CX2, CK_CY2, CK_M, CK_T1, CK_R, CK_N = 1, 2, 3, 4, 5, 6
IT_BASE, IT_STRIDE = 16, 28
CK_MED2, CK_NMED = 100, 101
CK_T0, CK_T1ST, CK_TMID, CK_TLAST = 102, 103, 104, 105
CK_NADMIT = 110
CK_F0 = 120
CK_VALID, CK_REASON, CK_ITERS = 140, 141, 142
CK_ACC, CK_CLS = 200, 201

IT_NAMES = ["G00", "G01", "G11", "G22", "G33", "G44", "rhs0", "rhs4",
            "shift0", "shift1", "shift2", "shift3", "shift4", "p",
            "A", "B", "C", "D", "E", "det", "u0", "v0", "fc40", "a16", "b16",
            "q0_50", "fit_count", "next_count"]

REASON = {"ok": 0, "too_few_scan_points": 1, "median_set_empty": 2,
          "degenerate_point_set": 3, "coordinate_range": 4, "overflow": 5,
          "gram_not_positive": 6, "singular": 7, "pivot_too_small": 8,
          "ill_conditioned": 9, "not_ellipse": 10, "center_range": 11,
          "precision_loss": 12, "zero_denominator": 13, "too_few_admitted": 14,
          "median_rank_range": 15, "arith_operand": 16, "sqrt_negative": 17}


def replay(xs, ys, ck):
    """``hwmodel.fit`` verbatim, with a checkpoint recorded after each stage."""
    if len(xs) < hw.MIN_FIT_POINTS:
        raise hw.FixedFailure("too_few_scan_points", f"{len(xs)}")
    cond = hw.condition(xs, ys)
    for k, cid in (("cx2", CK_CX2), ("cy2", CK_CY2), ("m", CK_M),
                   ("t1", CK_T1), ("R", CK_R), ("n", CK_N)):
        ck[cid] = cond[k]
    U, V = cond["U"], cond["V"]
    U2 = [hw.put("mono.sq", hw.mul(t, t, "mono.sq", "mono.prod")) for t in U]
    UV = [hw.put("mono.sq", hw.mul(a, b, "mono.sq", "mono.prod")) for a, b in zip(U, V)]
    V2 = [hw.put("mono.sq", hw.mul(t, t, "mono.sq", "mono.prod")) for t in V]
    rows = [U2, UV, V2, U, V]
    mask = [True] * len(xs)
    iters = 0
    for it in range(3):
        base = IT_BASE + IT_STRIDE * it
        G, r = hw.gram(rows, mask)
        for idx, (a, b) in enumerate([(0, 0), (0, 1), (1, 1), (2, 2), (3, 3), (4, 4)]):
            ck[base + idx] = G[a][b]
        ck[base + 6] = r[0]
        ck[base + 7] = r[4]
        z, diag = hw.solve(G, r)
        for j in range(5):
            ck[base + 8 + j] = diag["shift"][j]
        ck[base + 13] = diag["rhs_scale"]
        A, B, C, D, E = hw.to_coefficients(z, diag["shift"], diag["rhs_scale"])
        for idx, v in enumerate((A, B, C, D, E)):
            ck[base + 14 + idx] = v
        geo = hw.geometry(A, B, C, D, E)
        for idx, k in enumerate(("det40", "u0", "v0", "fc40", "a16", "b16", "q0_50")):
            ck[base + 19 + idx] = geo[k]
        A24 = hw.rshift_r(A, 8, "coef.q24")
        B24 = hw.rshift_r(B, 8, "coef.q24")
        C24 = hw.rshift_r(C, 8, "coef.q24")
        D24 = hw.rshift_r(D, 8, "coef.q24")
        E24 = hw.rshift_r(E, 8, "coef.q24")
        tq = hw.residuals(U, V, A24, B24, C24, D24, E24, geo["q0_50"], geo["fc31"])
        newmask = [abs(v) <= hw.FIT_BAND_MM * (1 << hw.Q_T) for v in tq]
        nsel = sum(newmask)
        iters = it + 1
        ck[base + 26] = sum(mask)
        ck[base + 27] = nsel
        if nsel < hw.MIN_ADMIT:
            mask = [True] * len(xs)
            break
        mask = newmask
    med2, nmed = hw.t_offset_hist(tq)
    t = [hw.round_t(v, med2) for v in tq]
    ck[CK_MED2], ck[CK_NMED] = med2, nmed
    ck[CK_T0], ck[CK_T1ST] = t[0], t[1]
    ck[CK_TMID], ck[CK_TLAST] = t[len(t) // 2], t[-1]
    ck[CK_ITERS] = iters
    return {"cond": cond, "geo": geo, "t_raw_q16": tq, "t": t, "med2": med2,
            "n_median_set": nmed, "mask": mask, "iterations": iters}


def pack_points(xs, ys, sides, slots, steps, prots):
    words = {}
    for i, (x, y, side, slot, step, prot) in enumerate(
            zip(xs, ys, sides, slots, steps, prots)):
        words[2 * i] = (x & 0x3FF) | ((y & 0x3FF) << 10) | ((SIDE_CODE[side] & 3) << 20) \
            | ((slot & 0x7F) << 22) | ((step & 0xFF) << 29) \
            | ((prot & 1) << 37) | (1 << 38)
    return words


def emit(out, tag, xs, ys, sides, slots, steps, prots, params, note):
    ck = {}
    try:
        mine = replay(xs, ys, ck)
    except hw.FixedFailure as e:
        mine = None
        ck[CK_VALID] = 0
        ck[CK_REASON] = REASON.get(e.reason, 31)
        ck[CK_ITERS] = 0
        fail_reason = e.reason
    else:
        fail_reason = None
    if mine is not None:
        fmine = hw.features(mine["t"], sides, slots, steps, prots,
                            (mine["geo"]["a16"], mine["geo"]["b16"]), mine["cond"]["m"])
        ck[CK_VALID] = fmine["FEATURE_VALID"]
        ck[CK_REASON] = REASON.get(fmine["REASON"], 31)
        ck[CK_NADMIT] = fmine.get("N_ADMIT", 0)
        acc = cls = None
        if fmine["FEATURE_VALID"]:
            vec = [fmine[k] for k in hw.FEATS]
            for i, k in enumerate(hw.FEATS):
                ck[CK_F0 + i] = fmine[k]
            try:
                acc, cls = hw.classify(vec, params)
                ck[CK_ACC] = acc
                ck[CK_CLS] = cls
            except hw.FixedFailure as e:
                ck[CK_ACC] = 0
                ck[CK_CLS] = 3
    else:
        fmine = {"FEATURE_VALID": 0, "REASON": fail_reason}
        acc = cls = None

    words = pack_points(xs, ys, sides, slots, steps, prots)
    (out / f"{tag}.pts.hex").write_text(
        "\n".join(f"{words.get(a, 0):016x}" for a in range(944)) + "\n", encoding="ascii")
    lines = []
    for cid in range(256):
        if cid in ck:
            v = ck[cid] & ((1 << 64) - 1)
            lines.append(f"1{v:016x}")
        else:
            lines.append("0" + "0" * 16)
    (out / f"{tag}.exp.hex").write_text("\n".join(lines) + "\n", encoding="ascii")
    return {"tag": tag, "note": note, "n_points": len(xs),
            "checkpoints": len(ck), "iterations": (mine or {}).get("iterations", 0),
            "med2": (mine or {}).get("med2"), "n_median_set": (mine or {}).get("n_median_set"),
            "features": ({k: fmine[k] for k in hw.FEATS}
                         if fmine.get("FEATURE_VALID") else None),
            "n_admit": fmine.get("N_ADMIT"),
            "reason": fmine.get("REASON"),
            "classifier_accumulator": acc,
            "predicted": "NG" if cls == 1 else ("OK" if cls == 0 else "UNCLASSIFIED")}


def main():
    params = json.loads((CLS / "verified" / "parameters.json").read_text(encoding="utf-8"))
    out = PROJ / "verification" / "core"
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"checkpoints": {"it_base": IT_BASE, "it_stride": IT_STRIDE,
                                "it_names": IT_NAMES},
                "runs": [], "failures": []}
    files = sorted(POINTS.glob("*.points.json"))
    for f in files:
        d = json.loads(f.read_text(encoding="utf-8"))
        stem = f.name.replace(".points.json", "")
        xs, ys = d["x"], d["y"]
        sides, slots = d["side"], d["slot"]
        steps, prots = d["step"], d["protect"]
        hw.reset_ledger(); hw.SCALE_LOG.clear()
        manifest["runs"].append(emit(out, stem, xs, ys, sides, slots, steps, prots,
                                     params, "full"))
        # quarter-rate subset for fast bring-up of the sequencer
        idx = list(range(0, len(xs), 4))
        hw.reset_ledger(); hw.SCALE_LOG.clear()
        manifest["runs"].append(emit(
            out, stem + ".sub", [xs[k] for k in idx], [ys[k] for k in idx],
            [sides[k] for k in idx], [slots[k] for k in idx],
            [steps[k] for k in idx], [prots[k] for k in idx], params, "subset/4"))
        manifest["runs"][-2]["sha256_points_json"] = hashlib.sha256(f.read_bytes()).hexdigest()
        for r in manifest["runs"]:
            print(f"{r['tag']:44s} n={r['n_points']:3d} it={r['iterations']} "
                  f"ck={r['checkpoints']:3d} acc={r['classifier_accumulator']} "
                  f"pred={r['predicted']} reason={r['reason']}")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    print(f"runs={len(manifest['runs'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
