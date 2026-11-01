"""Checked hardware arithmetic model for the gear-6 outer-contour core.

Why this file exists
--------------------
``FINITE_FEATURE_CORE_V1/src/fx.py`` checks the *result* of every node against a
declared width, but several of its *internal* temporaries are computed with
Python's unbounded integers:

  * ``num = a << k`` inside ``div_q``            (dividend, up to 98 bit)
  * ``twice = r << 1``                           (doubled remainder)
  * ``q + 1``                                    (rounding carry)
  * ``isqrt_q``'s ``r + x // r`` and ``isqrt_r``'s ``4*x`` / ``4*a*a+4*a+1``
  * ``fc << 5``, ``(D20*u0 + E20*v0) << 7``, ``(n >> 25) * inv`` in the
    geometry / residual stages (up to 71 bit)
  * ``z << (-k)`` (left shift) inside ``to_coefficients``

A hardware implementation cannot rely on those.  This module re-implements the
same chain with a declared signed width for **every** temporary, raises
``HWFail`` on any violation, and therefore states exactly what the RTL needs.

It must be *bit-identical* to the read-only reference; ``tools/run_audit.py``
asserts that on the six images and on primitive boundary cases.
"""

from __future__ import annotations

class FixedFailure(Exception):
    """Explicit finite-width failure; ``reason`` is the reported reason code."""

    def __init__(self, reason, detail=""):
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason
        self.detail = detail

# --------------------------------------------------------------- node table ---
# tag -> (signed bits, note).  Includes the temporaries the reference leaves
# unbounded; those names end in ".prod", ".shl", ".twice", ".carry", ".sqr".
W = {}


def decl(tag, bits, note=""):
    old = W.get(tag)
    if old is not None and old[0] != bits:
        raise RuntimeError(f"node {tag} redeclared {bits} != {old[0]}")
    W[tag] = (bits, note)


def put(tag, v, bits=None):
    """Range-check ``v`` against the declared width of ``tag``.

    ``bits`` given explicitly declares an *internal* temporary on the fly (it
    still gets its own ledger entry, so the audit reports its true width).
    """
    if bits is None:
        if tag not in W:
            raise RuntimeError(f"undeclared node {tag}")
        b = W[tag][0]
    else:
        b = bits
    lim = 1 << (b - 1)
    if not isinstance(v, int):
        raise TypeError(f"{tag}: non-integer {type(v)}")
    if v >= lim or v < -lim:
        raise FixedFailure("overflow", f"node {tag} value {v} does not fit signed {b} bit")
    mx, cnt = LED.setdefault(tag, [0, 0])
    a = v if v >= 0 else -v
    if a > mx:
        LED[tag][0] = a
    LED[tag][1] += 1
    return v


# tag -> [max abs, count]
LED = {}


def reset_ledger():
    for k in LED:
        LED[k] = [0, 0]


# ------------------------------------------------------------------ formats ---
QC = 13
QS = 28
KG = 14
Q_RHO = 40
Q_T = 16

FIT_BAND_MM = 25
MIN_FIT_POINTS = 40
MIN_ADMIT = 24
PIVOT_MIN = 1 << 16
OPERAND_LIM = 1 << 30
N_SCAN = 472
W_IMG = 960
H_IMG = 720

# shared datapath limits ------------------------------------------------------
OP_MAX = 47            # |operand| < 2^47 : the single hardware multiplier input
PROD_W = 96            # 48x48 signed product register
ACC_W = 104            # accumulator / shift bus (covers the 98-bit dividend)
DIV_NUM_BITS = 98      # widest shifted dividend the divider accepts
DIV_QUOT_W = 96        # quotient register; every call site bounds it further


def _w(tag, bits, note=""):
    decl(tag, bits, note)
    return tag


# ------------------------------------------------------------------ widths ---
for _t, _b, _n in [
    ("coord.u", 14, "u = 2x - 2*med(x)"),
    ("coord.med2", 12, "2*median(x) or 2*median(y)"),
    ("coord.U", 14, "U = u * 2^(QC-m)"),
    ("coord.shift", 24, "u * t1 before the range check"),
    ("mono.sq", 27, "U*U, U*V, V*V"),
    ("mono.prod", 28, "exact 14 x 14 product"),
    ("gram.entry", 62, "sum of <=472 products of two monomials"),
    ("gram.prod", 54, "exact 27 x 27 product"),
    ("gram.add", 63, "one accumulation step before the check"),
    ("gram.rhs", 36, "sum of <=472 monomials"),
    ("gram.rhs_add", 37, "one rhs accumulation step"),
    ("gram.gamma", 31, "Jacobi-scaled Gram entry"),
    ("gram.gamma.prod", 64, "4*A20*C20 etc (declared operand bound 47)"),
    ("gram.rhs_scaled", 29, "scaled right-hand side"),
    ("gram.rhs.shl", 52, "A[i][5] << p (p >= 0 rescaling)"),
    ("solve.shift.k", 8, "column shift amount, -32..31"),
    ("solve.sum.k", 10, "shift_i + shift_j"),
    ("solve.rs.quot", 62, "rshift_r quotient before the node check"),
    ("solve.pivot", 36, "normalised pivot row entry"),
    ("solve.pivot.div", 57, "A[k][j] << QS dividend"),
    ("solve.prod", 62, "multiplier * row entry"),
    ("solve.prod.exact", 110, "exact 47 x 47 product register"),
    ("solve.acc", 62, "one elimination update"),
    ("solve.acc.diff", 63, "A[i][j] - (f*A[k][j] >> QS)"),
    ("solve.z", 42, "scaled solution component"),
    ("coef.A", 42, "A',B',C' at Q32"),
    ("coef.D", 42, "D',E' at Q32"),
    ("coef.shl", 72, "z << (-k) inside to_coefficients"),
    ("coef.q24", 32, "A24..E24 at Q24"),
    ("coef.g20", 30, "A20..E20 at Q20"),
    ("det.q40", 60, "4AC-B^2 at Q40"),
    ("det.prod", 64, "4*A20*C20 / B20*B20"),
    ("det.diff", 65, "difference before the check"),
    ("num.q40", 60, "BE-2CD / BD-2AE at Q40"),
    ("num.diff", 63, "difference before the check"),
    ("center.q13", 16, "ellipse centre in U' units"),
    ("center.div", 75, "numU << QC dividend"),
    ("fc.q40", 62, "conic value at the centre, Q40"),
    ("fc.quad.prod1", 48, "A20 * u0"),
    ("fc.quad.prod2", 64, "(A20*u0) * u0"),
    ("fc.quad.sum", 65, "quadratic-form accumulation"),
    ("fc.lin.prod", 48, "D20 * u0"),
    ("fc.lin.shl", 56, "(D20*u0 + E20*v0) << 7"),
    ("fc.sum", 63, "quad>>6 + lin - 2^40"),
    ("fc.q31", 40, "Fc at Q31"),
    ("d2.q40", 58, "(A-C)^2+B^2 at Q40"),
    ("s1.q20", 28, "A+C+isqrt(D2) at Q20"),
    ("axis.num", 56, "-2*Fc*(A+C+sqrt(D2)) at Q40"),
    ("axis.num.prod", 64, "-2*fc20 * s1"),
    ("axis2.q32", 36, "a^2,b^2 at Q32"),
    ("axis.den", 56, "(-2*fc20) << 32 dividend"),
    ("axis.q16", 20, "a,b at Q16"),
    ("q0.q45", 48, "quadratic form at the centre, Q45"),
    ("q0.fc.shl", 67, "fc << 5 before the cancellation"),
    ("q0.du", 60, "D*u0 + E*v0"),
    ("q0.sum", 68, "fc<<5 + 2^45 - D*u0 - E*v0"),
    ("q0.q50", 52, "quadratic form at the centre, Q50"),
    ("res.num", 62, "expanded residual numerator at Q50"),
    ("res.n.prod1", 48, "A24 * U"),
    ("res.n.prod2", 64, "(A24*U) * U"),
    ("res.n.lin", 60, "(D24*U + E24*V) << 13"),
    ("res.n.sum", 63, "residual accumulation"),
    ("res.rho.prod", 96, "(n>>25) * inv  -- 71 bit, exceeds 62"),
    ("res.rho.shl", 96, "product >> 16"),
    ("res.t.prod", 64, "500 * (rho - 2^40)"),
    ("inv.q31", 34, "1/(-Fc) at Q31"),
    ("inv.num", 63, "1 << 62 dividend"),
    ("t.q16", 32, "t per mille at Q16"),
    ("t.diff2", 34, "2*t_raw - med2"),
    ("t.med2", 31, "2*median(t_raw) at Q16"),
    ("t.int", 16, "t per mille, rounded"),
    ("hist.idx", 10, "histogram bin index"),
    ("feat.t", 14, "t per mille"),
    ("feat.count", 16, "counts"),
    ("feat.area", 24, "sum of max(0,t-8)"),
    ("feat.std2", 24, "sum of t^2"),
    ("feat.step", 24, "sum of gray steps"),
    ("feat.q10", 16, "Q10 ratio 0..2048"),
    ("feat.ratio", 20, "ARATIO/RN before domain check"),
    ("feat.prod", 40, "1024*a16 / 1024*(a+b)<<(m-1)"),
    ("cls.acc", 29, "frozen classifier accumulator"),
    ("cls.prod", 48, "21 x 16 classifier product"),
]:
    _w(_t, _b, _n)


# --------------------------------------------------------------- primitives ---
def _op(a, tag):
    """Multiplier operand bound."""
    if a >= (1 << OP_MAX) or a < -(1 << OP_MAX):
        raise FixedFailure("arith_operand", f"{tag}: operand {a} exceeds 2^47")
    return a


def mul(a, b, dst, prod):
    """Exact product; the product node itself is width-declared, then ``dst``."""
    _op(a, prod)
    _op(b, prod)
    p = a * b
    put(prod, p)
    return put(dst, p) if dst != prod else p


def rshift_r(v, k, dst=None, tag="rs"):
    """round(v / 2**k) half-to-even; every temporary is width-declared."""
    if k < 0:
        s = v << (-k)
        put(tag + ".shl", s, ACC_W)
        return put(dst, s) if dst else s
    if k == 0:
        return put(dst, v) if dst else v
    if k > 96:
        raise FixedFailure("shift_range", f"{tag}: k={k}")
    d = 1 << k
    q, r = divmod(v, d)              # floor, 0 <= r < d
    half = d >> 1
    twice = r << 1                   # doubled remainder: k+1 bit
    put(tag + ".twice", r, k + 1)
    put(tag + ".twice2", twice, k + 2)
    if twice > d or (twice == d and (q & 1)):
        q += 1
        put(tag + ".carry", q, 96)
    return put(dst, q) if dst else q


def div_q(a, b, k, sig, dst, tag="divq"):
    """Same semantics as fx.div_q, with the operand-scaling branch explicit.

    The reference shrinks *both* operands by the same power of two when the
    shifted dividend would not fit; that is an approximation of a/b, not an
    identity.  ``SCALE_LOG`` records every time it happens so the audit can
    report it instead of claiming the ratio is preserved.
    """
    if b == 0:
        raise FixedFailure("zero_denominator", tag)
    if k < 0:
        raise FixedFailure("precision_loss", f"{tag}: negative quotient shift")
    neg = (a < 0) != (b < 0)
    a0, b0 = a, b
    a = -a if a < 0 else a
    b = -b if b < 0 else b
    if a == 0:
        return put(dst, 0) if dst else 0
    s = a.bit_length() + k - 62         # identical to the reference budget
    if s > 0:
        if b.bit_length() - s < sig:
            raise FixedFailure(
                "precision_loss", f"{tag}: divisor keeps {b.bit_length() - s} bits < {sig}")
        a = rshift_r(a, s, None, tag + ".num")
        b = rshift_r(b, s, None, tag + ".den")
        SCALE_LOG.append({"tag": tag, "s": s, "a_bits": a.bit_length(),
                          "b_bits": b.bit_length(), "sig": sig})
        if a == 0 or b == 0:
            raise FixedFailure("precision_loss", f"{tag}: operand vanished")
    put(tag + ".den", b, 48)
    num = a << k
    put(tag + ".num", num, DIV_NUM_BITS)
    q, r = divmod(num, b)
    twice = r << 1
    put(tag + ".twice", twice, b.bit_length() + 2)
    if twice > b or (twice == b and (q & 1)):
        q += 1
        put(tag + ".carry", q, DIV_QUOT_W + 1)
    q = -q if neg else q
    put(tag + ".quot", q, DIV_QUOT_W)
    if CAP_ON[0]:
        CAP.append((2, a0, b0, k, sig, q, 0))
    return put(dst, q) if dst else q


SCALE_LOG = []
CAP = []            # (op, a, b, k, sig, q, fail) recorded for the RTL vector set
CAP_ON = [False]


def isqrt_q(x, dst=None):
    """floor(sqrt(x)); the restoring unit sees a 62-bit radicand."""
    if x < 0:
        raise FixedFailure("sqrt_negative", str(x))
    put("sqrt.in", x, 62)
    if x == 0:
        if CAP_ON[0]:
            CAP.append((3, x, 0, 0, 0, 0, 0))
        return put(dst, 0) if dst else 0
    r = 1 << ((x.bit_length() + 1) // 2)
    while True:
        nr = (r + x // r) >> 1
        if nr >= r:
            if CAP_ON[0]:
                CAP.append((3, x, 0, 0, 0, r, 0))
            return put(dst, r) if dst else r
        r = nr


def isqrt_r(x, dst):
    """round(sqrt(x)) with an exact tie test (4x >= 4a^2+4a+1)."""
    a = isqrt_q(x)
    put("sqrt.q", a, 32)
    l4 = 4 * x
    put("sqrt_r.l4", l4, 46)
    rhs = 4 * a * a + 4 * a + 1
    put("sqrt_r.rhs", rhs, 46)
    res = a + 1 if l4 >= rhs else a
    if CAP_ON[0]:
        CAP.append((4, x, 0, 0, 0, res, 0))
    return put(dst, res) if dst else res


def div_t(a, b, k, dst, tag="divt"):
    """truncating (toward zero) division of ``a << k`` by ``b``.

    Only used for ``OUT_STD``'s ``sum(t^2) / N_ADMIT``, where both operands are
    non-negative so truncation equals the reference's ``//``.  The divider is
    the same 98-bit restoring unit as ``div_q``; only the rounding step is
    dropped.
    """
    if b == 0:
        raise FixedFailure("zero_denominator", tag)
    if k < 0:
        raise FixedFailure("precision_loss", f"{tag}: negative quotient shift")
    neg = (a < 0) != (b < 0)
    am = -a if a < 0 else a
    bm = -b if b < 0 else b
    s = am.bit_length() + k - 62
    if s > 0:
        am = rshift_r(am, s, None, tag + ".num")
        bm = rshift_r(bm, s, None, tag + ".den")
    put(tag + ".den", bm, 48)
    num = am << k
    put(tag + ".num", num, DIV_NUM_BITS)
    q = num // bm
    q = -q if neg else q
    put(tag + ".quot", q, DIV_QUOT_W)
    return put(dst, q) if dst else q


def round_div_half_even(num, den, dst, tag="rdhe"):
    if den == 0:
        raise FixedFailure("zero_denominator", tag)
    neg = (num < 0) != (den < 0)
    num = -num if num < 0 else num
    den = -den if den < 0 else den
    q, r = divmod(num, den)
    twice = r << 1
    put(tag + ".twice", twice, den.bit_length() + 2)
    if twice > den or (twice == den and (q & 1)):
        q += 1
        put(tag + ".carry", q, 32)
    q = -q if neg else q
    put(tag + ".quot", q, 40)
    return put(dst, q) if dst else q


# ------------------------------------------------------- coordinate medians ---
def _kth_u10(vals, k, name):
    """k-th smallest of 10-bit values via three histogram passes (16/16/4)."""
    b1 = [0] * 16
    for v in vals:
        idx = v >> 6
        put("hist.idx", idx)
        b1[idx] += 1
    base, lo1 = 0, None
    for i, c in enumerate(b1):
        if base + c > k:
            lo1 = i << 6
            break
        base += c
    if lo1 is None:
        raise FixedFailure("median_rank_range", name)
    k -= base
    b2 = [0] * 16
    for v in vals:
        if lo1 <= v < lo1 + 64:
            b2[(v - lo1) >> 2] += 1
    base, lo2 = 0, None
    for i, c in enumerate(b2):
        if base + c > k:
            lo2 = lo1 + (i << 2)
            break
        base += c
    if lo2 is None:
        raise FixedFailure("median_rank_range", name)
    k -= base
    b3 = [0] * 4
    for v in vals:
        if lo2 <= v < lo2 + 4:
            b3[v - lo2] += 1
    base = 0
    for i, c in enumerate(b3):
        if base + c > k:
            return lo2 + i
        base += c
    raise FixedFailure("median_rank_range", name)


def median2(vals, name):
    n = len(vals)
    if n == 0:
        raise FixedFailure("median_set_empty", name)
    lo = _kth_u10(vals, (n - 1) // 2, name)
    hi = _kth_u10(vals, n // 2, name)
    return put("coord.med2", lo + hi)


def condition(xs, ys):
    cx2 = median2(xs, "x")
    cy2 = median2(ys, "y")
    u, v = [], []
    for x, y in zip(xs, ys):
        u.append(put("coord.u", 2 * x - cx2))
        v.append(put("coord.u", 2 * y - cy2))
    R = max(max(abs(t) for t in u), max(abs(t) for t in v))
    if R == 0:
        raise FixedFailure("degenerate_point_set", "all points identical")
    m = R.bit_length()
    if m > QC:
        raise FixedFailure("coordinate_range", f"|u| needs {m} bits > Q{QC}")
    t1 = 1 << (QC - m)
    U = [put("coord.U", put("coord.shift", t * t1)) for t in u]
    V = [put("coord.U", put("coord.shift", t * t1)) for t in v]
    return {"cx2": cx2, "cy2": cy2, "m": m, "t1": t1, "U": U, "V": V, "n": len(xs),
                "R": R}


# ---------------------------------------------------------------- the chain ---
def gram(rows, mask):
    G = [[0] * 5 for _ in range(5)]
    r = [0] * 5
    for i, keep in enumerate(mask):
        if not keep:
            continue
        c = [rows[a][i] for a in range(5)]
        for a in range(5):
            r[a] = put("gram.rhs_add", r[a] + c[a])
            for b in range(a, 5):
                pr = mul(c[a], c[b], "gram.prod", "gram.prod")
                G[a][b] = put("gram.add", G[a][b] + pr)
    for a in range(5):
        put("gram.rhs", r[a])
        for b in range(a, 5):
            put("gram.entry", G[a][b])
            G[b][a] = G[a][b]
    return G, r


def solve(G, r):
    shift = []
    for j in range(5):
        d = G[j][j]
        if d <= 0:
            raise FixedFailure("gram_not_positive", f"diagonal {j} = {d}")
        k = (d.bit_length() - 2 * KG) // 2
        put("solve.shift.k", k)
        shift.append(k)
    A = [[0] * 6 for _ in range(5)]
    for i in range(5):
        for j in range(5):
            put("solve.sum.k", shift[i] + shift[j])
            A[i][j] = rshift_r(G[i][j], shift[i] + shift[j], "gram.gamma")
        A[i][5] = rshift_r(r[i], shift[i], "gram.rhs_scaled")
    mx = max(abs(A[i][5]) for i in range(5))
    if mx == 0:
        raise FixedFailure("singular", "zero right-hand side")
    p = (QS - 1) - mx.bit_length()
    put("gram.rhs.shl", 0)
    for i in range(5):
        if -p > 0:
            put("gram.rhs.shl", A[i][5] << (-p))
        A[i][5] = rshift_r(A[i][5], -p, "gram.rhs_scaled")

    pivots = []
    for k in range(5):
        pr = max(range(k, 5), key=lambda i: abs(A[i][k]))
        piv = A[pr][k]
        pivots.append(piv)
        if abs(piv) < PIVOT_MIN:
            raise FixedFailure("pivot_too_small", f"pivot {k} = {piv} < {PIVOT_MIN}")
        if pr != k:
            A[k], A[pr] = A[pr], A[k]
        for j in range(k + 1, 6):
            A[k][j] = div_q(A[k][j], piv, QS, 20, "solve.pivot", "solve.pivot")
        A[k][k] = 1 << QS
        for i in range(5):
            if i == k:
                continue
            f = A[i][k]
            if f == 0:
                continue
            for j in range(k + 1, 6):
                if abs(f) >= OPERAND_LIM or abs(A[k][j]) >= OPERAND_LIM:
                    raise FixedFailure("ill_conditioned",
                                       f"elimination operand exceeds {OPERAND_LIM}")
                pr = mul(f, A[k][j], "solve.prod", "solve.prod")
                sh = rshift_r(pr, QS, None, "solve.prod")
                A[i][j] = put("solve.acc", put("solve.acc.diff", A[i][j] - sh))
            A[i][k] = 0
    z = [put("solve.z", A[i][5]) for i in range(5)]
    return z, {"shift": shift, "pivots": pivots, "rhs_scale": p}


def to_coefficients(z, shift, rhs_scale):
    s = rhs_scale
    ka, kd = 58 - QS, 45 - QS
    A = rshift_r(z[0], shift[0] + s - ka, "coef.A", "coef")
    B = rshift_r(z[1], shift[1] + s - ka, "coef.A", "coef")
    C = rshift_r(z[2], shift[2] + s - ka, "coef.A", "coef")
    D = rshift_r(z[3], shift[3] + s - kd, "coef.D", "coef")
    E = rshift_r(z[4], shift[4] + s - kd, "coef.D", "coef")
    return A, B, C, D, E


def geometry(A, B, C, D, E):
    A20 = rshift_r(A, 12, "coef.g20")
    B20 = rshift_r(B, 12, "coef.g20")
    C20 = rshift_r(C, 12, "coef.g20")
    D20 = rshift_r(D, 12, "coef.g20")
    E20 = rshift_r(E, 12, "coef.g20")
    p4ac = mul(4 * A20, C20, "det.prod", "det.prod")
    pbb = mul(B20, B20, "det.prod", "det.prod")
    det = put("det.q40", put("det.diff", p4ac - pbb))
    if det <= 0:
        raise FixedFailure("not_ellipse", f"det {det} <= 0")
    if A20 <= 0:
        raise FixedFailure("not_ellipse", "A <= 0")
    pbe = mul(B20, E20, "num.q40", "num.q40")
    pcd2 = mul(2 * C20, D20, "num.q40", "num.q40")
    numU = put("num.q40", put("num.diff", pbe - pcd2))
    pbd = mul(B20, D20, "num.q40", "num.q40")
    pae2 = mul(2 * A20, E20, "num.q40", "num.q40")
    numV = put("num.q40", put("num.diff", pbd - pae2))
    u0 = div_q(numU, det, QC, 22, "center.q13", "center.u")
    v0 = div_q(numV, det, QC, 22, "center.q13", "center.v")
    if abs(u0) >= (1 << 15) or abs(v0) >= (1 << 15):
        raise FixedFailure("center_range", f"centre ({u0},{v0}) outside +-4")

    au = mul(A20, u0, "fc.quad.prod1", "fc.quad.prod1")
    auu = mul(au, u0, "fc.quad.prod2", "fc.quad.prod2")
    bu = mul(B20, u0, "fc.quad.prod1", "fc.quad.prod1")
    buv = mul(bu, v0, "fc.quad.prod2", "fc.quad.prod2")
    cv = mul(C20, v0, "fc.quad.prod1", "fc.quad.prod1")
    cvv = mul(cv, v0, "fc.quad.prod2", "fc.quad.prod2")
    quad = put("fc.quad.sum", put("fc.quad.sum", auu + buv) + cvv)
    du = mul(D20, u0, "fc.lin.prod", "fc.lin.prod")
    ev = mul(E20, v0, "fc.lin.prod", "fc.lin.prod")
    lin = put("fc.lin.shl", put("fc.quad.sum", du + ev) << 7)
    quad6 = rshift_r(quad, 6, None, "fcq")
    fc = put("fc.q40", put("fc.sum", quad6 + lin - (1 << 40)))
    if fc >= 0:
        raise FixedFailure("not_ellipse", f"Fc {fc} >= 0")
    fc31 = rshift_r(fc, 9, "fc.q31")
    if fc31 == 0:
        raise FixedFailure("precision_loss", "Fc underflows Q31")

    ac = put("fc.quad.sum", A20 - C20)
    ac2 = mul(ac, ac, "d2.q40", "d2.q40")
    bb = mul(B20, B20, "d2.q40", "d2.q40")
    d2 = put("d2.q40", put("fc.quad.sum", ac2 + bb))
    sq = isqrt_q(d2)
    s1 = put("s1.q20", put("fc.quad.sum", A20 + C20 + sq))
    if s1 <= 0:
        raise FixedFailure("not_ellipse", "A+C+sqrt((A-C)^2+B^2) <= 0")

    fc20 = rshift_r(fc, 20, None, "axis")
    num_a = put("axis.num", mul(-2 * fc20, s1, "axis.num.prod", "axis.num.prod"))
    a2 = div_q(num_a, det, 32, 22, "axis2.q32", "axis.a")
    put("axis.den", (-2 * fc20) << 32)
    b2 = div_q(-2 * fc20, s1, 32, 20, "axis2.q32", "axis.b")
    if a2 <= 0 or b2 <= 0:
        raise FixedFailure("not_ellipse", "non-positive squared semi-axis")
    a = isqrt_r(a2, "axis.q16")
    b = isqrt_r(b2, "axis.q16")
    if a < b:
        a, b = b, a
    du0 = mul(D, u0, "q0.du", "q0.du")
    ev0 = mul(E, v0, "q0.du", "q0.du")
    fcs = put("q0.fc.shl", fc << 5)
    q0_45 = put("q0.q45", put("q0.sum", fcs + (1 << 45) - du0 - ev0))
    q0_50 = put("q0.q50", q0_45 << 5)
    return {"u0": u0, "v0": v0, "fc40": fc, "fc31": fc31, "det40": det,
            "a16": a, "b16": b, "q0_50": q0_50,
            "A20": A20, "B20": B20, "C20": C20, "D20": D20, "E20": E20}


def residuals(U, V, A24, B24, C24, D24, E24, q0_50, fc31):
    inv = div_q(1 << 62, -fc31, 0, 28, "inv.q31", "inv")
    out = []
    for UU, VV in zip(U, V):
        a1 = mul(A24, UU, "res.n.prod1", "res.n.prod1")
        a2 = mul(a1, UU, "res.n.prod2", "res.n.prod2")
        b1 = mul(B24, UU, "res.n.prod1", "res.n.prod1")
        b2 = mul(b1, VV, "res.n.prod2", "res.n.prod2")
        c1 = mul(C24, VV, "res.n.prod1", "res.n.prod1")
        c2 = mul(c1, VV, "res.n.prod2", "res.n.prod2")
        n = put("res.n.sum", put("res.n.sum", a2 + b2) + c2)
        d1 = mul(D24, UU, "res.n.prod1", "res.n.prod1")
        e1 = mul(E24, VV, "res.n.prod1", "res.n.prod1")
        lin = put("res.n.lin", put("res.n.sum", d1 + e1) << 13)
        n = put("res.num", n + lin)
        n = put("res.num", n + q0_50)
        hi = n >> 25
        put("res.num", hi, 40)
        pr = mul(hi, inv, "res.rho.prod", "res.rho.prod")
        rho = put("res.rho.shl", pr >> 16)
        dt = put("res.rho.shl", rho - (1 << Q_RHO))
        put("res.t.prod", mul(500, dt, "res.t.prod", "res.t.prod"))
        out.append(rshift_r(500 * dt, 24, "t.q16", "t"))
    return out


HIST_LO = -(1 << 22)
HIST_L1 = (1 << 14, 512)
HIST_L2 = (1 << 6, 256)
HIST_L3 = (1, 64)


def _kth_hist(sel, k):
    (w1, n1), (w2, n2), (w3, n3) = HIST_L1, HIST_L2, HIST_L3
    b1 = [0] * n1
    for v in sel:
        b1[(v - HIST_LO) >> 14] += 1
    base, lo1 = 0, None
    for i, c in enumerate(b1):
        if base + c > k:
            lo1 = HIST_LO + i * w1
            break
        base += c
    if lo1 is None:
        raise FixedFailure("median_rank_range")
    k -= base
    b2 = [0] * n2
    for v in sel:
        if lo1 <= v < lo1 + w1:
            b2[(v - lo1) >> 6] += 1
    base, lo2 = 0, None
    for i, c in enumerate(b2):
        if base + c > k:
            lo2 = lo1 + i * w2
            break
        base += c
    if lo2 is None:
        raise FixedFailure("median_rank_range")
    k -= base
    b3 = [0] * n3
    for v in sel:
        if lo2 <= v < lo2 + w3 * n3:
            b3[v - lo2] += 1
    base = 0
    for i, c in enumerate(b3):
        if base + c > k:
            return lo2 + i
        base += c
    raise FixedFailure("median_rank_range")


def t_offset_hist(tq):
    lim = 60 * (1 << Q_T)
    sel = [v for v in tq if -lim <= v <= lim]
    if not sel:
        raise FixedFailure("median_set_empty", "no |t|<=60 sample")
    n = len(sel)
    a = _kth_hist(sel, (n - 1) // 2)
    b = _kth_hist(sel, n // 2)
    return put("t.med2", a + b), n


def round_t(tq, med2):
    d2 = put("t.diff2", 2 * tq - med2)
    return rshift_r(d2, Q_T + 1, "t.int", "t")


def _mask_hash(mask):
    import hashlib
    return hashlib.sha256(bytes(1 if m else 0 for m in mask)).hexdigest()[:16]


def fit(xs, ys, iters=3):
    if len(xs) < MIN_FIT_POINTS:
        raise FixedFailure("too_few_scan_points", f"{len(xs)} < {MIN_FIT_POINTS}")
    cond = condition(xs, ys)
    U, V = cond["U"], cond["V"]
    U2 = [put("mono.sq", mul(t, t, "mono.sq", "mono.prod")) for t in U]
    UV = [put("mono.sq", mul(a, b, "mono.sq", "mono.prod")) for a, b in zip(U, V)]
    V2 = [put("mono.sq", mul(t, t, "mono.sq", "mono.prod")) for t in V]
    rows = [U2, UV, V2, U, V]
    mask = [True] * len(xs)
    trace, coef, geo, tq = [], None, None, None
    for it in range(iters):
        G, r = gram(rows, mask)
        z, diag = solve(G, r)
        A, B, C, D, E = to_coefficients(z, diag["shift"], diag["rhs_scale"])
        coef = (A, B, C, D, E)
        geo = geometry(A, B, C, D, E)
        A24 = rshift_r(A, 8, "coef.q24")
        B24 = rshift_r(B, 8, "coef.q24")
        C24 = rshift_r(C, 8, "coef.q24")
        D24 = rshift_r(D, 8, "coef.q24")
        E24 = rshift_r(E, 8, "coef.q24")
        tq = residuals(U, V, A24, B24, C24, D24, E24, geo["q0_50"], geo["fc31"])
        newmask = [abs(v) <= FIT_BAND_MM * (1 << Q_T) for v in tq]
        nsel = sum(newmask)
        trace.append({"iteration": it, "fit_count": sum(mask), "next_count": nsel,
                      "mask_exante": _mask_hash(mask),
                      "mask_expost": _mask_hash(newmask),
                      "pivots_q26": diag["pivots"], "column_shift": diag["shift"],
                      "rhs_scale": diag["rhs_scale"],
                      "coefficients_q32": [A, B, C, D, E],
                      "det_q40": geo["det40"], "fc_q40": geo["fc40"],
                      "center_q13": [geo["u0"], geo["v0"]],
                      "axis_q16": [geo["a16"], geo["b16"]],
                      "t_max_abs_q16": max(abs(v) for v in tq)})
        if nsel < MIN_ADMIT:
            mask = [True] * len(xs)
            break
        mask = newmask
    med2, nmed = t_offset_hist(tq)
    t = [round_t(v, med2) for v in tq]
    return {"cond": cond, "coef": coef, "geo": geo, "t_raw_q16": tq, "t": t,
            "med2": med2, "n_median_set": nmed, "trace": trace, "mask": mask}


# --------------------------------------------------------------- the 13 dims ---
T_OUT_MM = 8
T_IN_MM = -8
ADMIT_OUT_MM = 60
ADMIT_NEAR_MM = 15
ADMIT_IN_MM = -15
FEATS = ["OUT_MAX", "IN_MAX", "OUT_FRAC", "IN_FRAC", "OUT_AREA", "OUT_STD",
         "OUT_RUN", "COVER", "GCONTRAST", "GWEAK8", "PROTECT", "ARATIO", "RN"]


def features(t, sides, slots, step, prot, axis, m):
    """One ascending pass per side; equal to the reference's per-side sort.

    Points arrive in (side, slot) ascending order from the scanner, so
    "neighbour slot" is "previous / next array entry with the same side".
    Support for point i needs t[i-1] and t[i+1]; the pass therefore finalises
    point i-1 while point i is in flight (a one-entry lookahead).
    """
    n = len(t)
    sup = [False] * n
    for i in range(n):
        if i == 0 or i + 1 >= n:
            continue
        if sides[i - 1] != sides[i] or sides[i + 1] != sides[i]:
            continue
        if slots[i - 1] != slots[i] - 1 or slots[i + 1] != slots[i] + 1:
            continue
        ta, tb = t[i - 1], t[i + 1]
        sup[i] = (6 < ta <= ADMIT_OUT_MM) and (6 < tb <= ADMIT_OUT_MM)
    admit = []
    for i in range(n):
        ti = t[i]
        if ti < ADMIT_IN_MM:
            admit.append(False)
        elif ti <= ADMIT_NEAR_MM:
            admit.append(True)
        elif ti <= ADMIT_OUT_MM:
            admit.append(bool(sup[i]))
        else:
            admit.append(False)
    n_ad = sum(admit)
    if n_ad < MIN_ADMIT:
        return {"FEATURE_VALID": 0, "REASON": "too_few_admitted", "N_ADMIT": n_ad,
                "admit": admit, "support": sup}

    # ---- single ascending pass over the admitted points -------------------
    out_max = -32768
    in_max = -32768
    cnt_out = 0
    cnt_in = 0
    area = 0
    std2 = 0
    ssum = 0
    pcount = 0
    run = 0
    cur = 0
    last_slot = -2
    last_side = -1
    win = []            # last 8 (side, slot, step) of admitted points
    best = None
    nwin = 0
    for i in range(n):
        if not admit[i]:
            # a missing slot breaks the run; the 8-window only sees admitted
            cur = 0
            last_slot = -2
            continue
        ti = put("feat.t", t[i])
        if ti > out_max:
            out_max = ti
        if -ti > in_max:
            in_max = put("feat.t", -ti)
        if ti >= T_OUT_MM:
            cnt_out += 1
            area = put("feat.area", area + (ti - T_OUT_MM))
        if ti <= T_IN_MM:
            cnt_in += 1
        std2 = put("feat.std2", std2 + put("feat.std2", ti * ti))
        ssum = put("feat.step", ssum + step[i])
        if prot[i]:
            pcount += 1
        # longest run of admitted, t >= 8, slot-adjacent, same side
        if ti >= T_OUT_MM:
            adj = (sides[i] == last_side) and (slots[i] == last_slot + 1) and cur > 0
            cur = cur + 1 if adj else 1
        else:
            cur = 0
        last_slot = slots[i] if ti >= T_OUT_MM else -2
        last_side = sides[i]
        if cur > run:
            run = cur
        # 8-window on the admitted stream
        win.append((sides[i], slots[i], step[i]))
        if len(win) > 8:
            win.pop(0)
        if len(win) == 8:
            if all(w[0] == win[0][0] for w in win) and win[7][1] - win[0][1] == 7:
                s = sum(w[2] for w in win)
                v = s // 8
                nwin += 1
                if best is None or v < best:
                    best = v
    gw = best if best is not None else 0

    f = {}
    f["OUT_MAX"] = put("feat.t", out_max)
    f["IN_MAX"] = put("feat.t", in_max)
    f["OUT_FRAC"] = round_div_half_even(1024 * cnt_out, n_ad, "feat.q10", "frac_out")
    f["IN_FRAC"] = round_div_half_even(1024 * cnt_in, n_ad, "feat.q10", "frac_in")
    f["OUT_AREA"] = round_div_half_even(area, 100, "feat.q10", "area")
    f["OUT_STD"] = put("feat.t", isqrt_q(div_t(std2, n_ad, 0, None, "std")))
    f["OUT_RUN"] = put("feat.count", run)
    f["COVER"] = round_div_half_even(1024 * n_ad, N_SCAN, "feat.q10", "cover")
    f["GCONTRAST"] = round_div_half_even(ssum, n_ad, "feat.q10", "gcontrast")
    f["GWEAK8"] = put("feat.q10", gw)
    f["GWEAK8_WINDOWS"] = nwin
    f["PROTECT"] = round_div_half_even(1024 * pcount, n_ad, "feat.q10", "protect")
    a16, b16 = axis
    if b16 <= 0:
        raise FixedFailure("zero_denominator", "minor axis is zero")
    f["ARATIO"] = round_div_half_even(put("feat.prod", 1024 * a16), b16, "feat.ratio", "aratio")
    num = put("feat.prod", 1024 * (a16 + b16))
    num = put("feat.prod", num << (m - 1) if m >= 1 else num >> (1 - m))
    f["RN"] = round_div_half_even(num, 1440 << 16, "feat.ratio", "rn")
    f["FEATURE_VALID"] = 1
    f["REASON"] = "ok"
    f["N_ADMIT"] = n_ad
    f["admit"] = admit
    f["support"] = sup
    f["GCONTRAST_SUM"] = ssum
    return f


def classify(feat_vec, params):
    """Frozen integer classifier: A = q0 + sum q_i x_i ; A >= 0 -> NG."""
    for name, v, d in zip(params["features"], feat_vec, params["domains"]):
        if not d[0] <= v <= d[1]:
            raise FixedFailure("input_domain", f"{name} = {v} outside [{d[0]},{d[1]}]")
    acc = params["offset_integer"]
    put("cls.acc", acc)
    for v, w, pb in zip(feat_vec, params["weights_integer"], params["product_bits"]):
        pr = v * w
        put("cls.prod", pr, pb)
        acc += pr
        put("cls.acc", acc)
    return acc, (1 if acc >= 0 else 0)
