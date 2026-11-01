"""Emit the ml_scan vectors from the frozen reference chain.

Reads one demo image through the read-only reference pipeline (3-frame temporal
Canny, exactly as ``refpipe.frame3``), then dumps

  gray.hex    filtered_gray, 16 pixels per 128-bit word
  edge.hex    edge map,      64 pixels per 64-bit word
  prot.hex    protect map,   64 pixels per 64-bit word
  exp.hex     the expected candidate list in emission order, one 64-bit point
              word per line, packed exactly like ``gen_core_vectors.pack_points``
  meta.json   fingerprints + counts

The expected list is produced by ``refpipe.points_of`` -- the same frozen code
that produced the classifier vectors -- so the bench compares the RTL against the
reference, never against a re-derived rule.

   python tools/gen_scan_vectors.py [--image NAME]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

PROJ = Path(__file__).resolve().parents[1]
REF = Path(r"C:/Users/17734/Documents/Codex/2026-10-26/c-users-17734-documents-codex-2026/outputs/FINITE_FEATURE_CORE_V1")
sys.path.insert(0, str(REF / "src"))

import refpipe as rp  # noqa: E402

W, H = 960, 720
SIDE_CODE = {"T": 0, "R": 1, "B": 2, "L": 3}
DEMOS = Path(r"C:/qian/ML_DEMO_IMAGES")


def pack_gray(g):
    a = np.asarray(g, np.uint16).reshape(-1)
    assert a.size == W * H, a.size
    rows = []
    for i in range(0, a.size, 16):
        v = 0
        for k in range(16):
            v |= int(a[i + k]) << (8 * k)
        rows.append(f"{v:032x}")
    return rows


def pack_bits(m, per=64):
    a = (np.asarray(m).reshape(-1) != 0).astype(np.uint8)
    assert a.size == W * H, a.size
    rows = []
    for i in range(0, a.size, per):
        v = 0
        for k in range(per):
            v |= int(a[i + k]) << k
        rows.append(f"{v:0{per // 4}x}")
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", default="OK/cast_ok_0_1074.jpeg")
    args = ap.parse_args()
    path = DEMOS / args.image
    cf, fr = rp.frame3(path)
    pts = rp.points_of(fr, cf)

    out = PROJ / "verification" / "scan"
    out.mkdir(parents=True, exist_ok=True)
    (out / "gray.hex").write_text("\n".join(pack_gray(fr["filtered_gray"])) + "\n",
                                  encoding="ascii")
    (out / "edge.hex").write_text("\n".join(pack_bits(fr["edge"])) + "\n", encoding="ascii")
    (out / "prot.hex").write_text("\n".join(pack_bits(fr["protect"])) + "\n", encoding="ascii")

    words = []
    for i in range(pts["n_points"]):
        w = (int(pts["x"][i]) & 0x3FF) | ((int(pts["y"][i]) & 0x3FF) << 10) \
            | ((SIDE_CODE[pts["side"][i]] & 3) << 20) \
            | ((int(pts["slot"][i]) & 0x7F) << 22) \
            | ((int(pts["step"][i]) & 0xFF) << 29) \
            | ((int(pts["protect"][i]) & 1) << 37) | (1 << 38)
        words.append(f"{w:016x}")
    (out / "exp.hex").write_text("\n".join(words) + "\n", encoding="ascii")

    by_side = {s: sum(1 for v in pts["side"] if v == s) for s in ("L", "R", "T", "B")}
    meta = {
        "image": str(path),
        "image_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "n_points": pts["n_points"],
        "by_side": by_side,
        "max_step": int(max(pts["step"])) if pts["n_points"] else 0,
        "protect_ones": int(np.count_nonzero(fr["protect"])),
        "edge_ones": int(np.count_nonzero(fr["edge"])),
        "packing": {
            "gray": "16 px / 128-bit word, px 0 in bits 7:0",
            "edge": "64 px / 64-bit word, px 0 in bit 0",
            "protect": "64 px / 64-bit word, px 0 in bit 0",
            "point": "x[9:0] y[19:10] side[21:20] slot[28:22] step[36:29] prot[37] gram[38]",
        },
    }
    (out / "meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print(json.dumps(meta, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
