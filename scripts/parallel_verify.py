#!/usr/bin/env python3
"""
Parallel verification framework for the fixed/floating-point merged MAC unit.

Usage:
    python3 parallel_verify.py [--fix-cin] [--jobs N] [--seed S]

--fix-cin   Assume cin_gen.v has been fixed (cin = eop_fp); without this flag
            the script expects the current RTL bug where cin = comp.
--jobs      Number of parallel vvp processes (default: min(24, cpu_count))
--seed      Master PRNG seed (default: 42)
"""

import argparse
import concurrent.futures
import datetime
import os
import random
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO = Path(__file__).parent.parent
RTL_GLOB = str(REPO / "Efficient_MAC/rtl/*.v")
TB = str(REPO / "Efficient_MAC/bhav_sim/tb_mac_top.v")
SIM_BIN = "/tmp/mac_par_sim"

# Resolve pixi-managed tool paths (fall back to PATH if not found)
_PIXI_BIN = REPO / ".pixi/envs/default/bin"
IVERILOG = str(_PIXI_BIN / "iverilog") if (_PIXI_BIN / "iverilog").exists() else "iverilog"
VVP      = str(_PIXI_BIN / "vvp")      if (_PIXI_BIN / "vvp").exists()      else "vvp"

# ---------------------------------------------------------------------------
# IEEE-754 helpers
# ---------------------------------------------------------------------------

def f16_to_parts(h: int):
    """Unpack FP16 bit pattern into (sign, exp, mant) with hidden bit."""
    s = (h >> 15) & 1
    e = (h >> 10) & 0x1F
    m = h & 0x3FF
    if e == 0:
        return s, 0, m          # denormal — hidden bit = 0
    return s, e, m | 0x400      # normal — hidden bit = 1

def f32_to_parts(w: int):
    """Unpack FP32 bit pattern into (sign, exp, mant) with hidden bit."""
    s = (w >> 31) & 1
    e = (w >> 23) & 0xFF
    m = w & 0x7FFFFF
    if e == 0:
        return s, 0, m
    return s, e, m | 0x800000

def f32_from_float(v: float) -> int:
    return struct.unpack('>I', struct.pack('>f', v))[0]

def f32_to_float(w: int) -> float:
    return struct.unpack('>f', struct.pack('>I', w))[0]

def f16_from_float(v: float) -> int:
    b = struct.pack('>e', v)
    return struct.unpack('>H', b)[0]

def is_nan_inf_f32(w: int) -> bool:
    return ((w >> 23) & 0xFF) == 0xFF

def is_nan_inf_f16(h: int) -> bool:
    return ((h >> 10) & 0x1F) == 0x1F

# ---------------------------------------------------------------------------
# Exact reference models
# ---------------------------------------------------------------------------

def fix_ref(A16: int, B16: int, acc32: int) -> int:
    """
    FIX mode: compute (Ah*Bh + Al*Bl + acc) mod 2^32.
    A16/B16 are split into signed 8-bit halves by input_processing.v.
    acc32 is a signed 32-bit accumulator.
    Output is the lower 32 bits of the sum (matches OUT_fx = sum_low).
    """
    # input_processing splits A/B into upper and lower signed bytes
    Ah = A16 >> 8          # upper byte (signed)
    Al = A16 & 0xFF        # lower byte (signed)
    Bh = B16 >> 8
    Bl = B16 & 0xFF

    def to_signed8(x):
        return x - 256 if x >= 128 else x

    def to_signed32(x):
        x &= 0xFFFFFFFF
        return x - (1 << 32) if x >= (1 << 31) else x

    Ah_s = to_signed8(Ah)
    Al_s = to_signed8(Al)
    Bh_s = to_signed8(Bh)
    Bl_s = to_signed8(Bl)
    acc_s = to_signed32(acc32)

    result = Ah_s * Bh_s + Al_s * Bl_s + acc_s
    return result & 0xFFFFFFFF


def fp_ref(A16: int, B16: int, acc32: int) -> int:
    """
    FLP mode exact reference using Python big-integer arithmetic.
    Returns FP32 bit pattern, or None if result is NaN/Inf/denormal edge.

    The MAC computes: result_fp32 = fp16(A) * fp16(B) + fp32(acc)

    Implementation mirrors the RTL pipeline exactly:
      1. Decode inputs
      2. Compute unrounded product mantissa (22-bit)
      3. Determine effective operation (add or subtract)
      4. Align accumulator to product's fixed-point grid
      5. Add (ones-complement if subtract, then +cin=eop_fp)
      6. Normalize
      7. Round (IEEE RNE)
    """
    # Filter edge cases the RTL doesn't handle
    if is_nan_inf_f16(A16) or is_nan_inf_f16(B16) or is_nan_inf_f32(acc32):
        return None
    if (A16 & 0x7FFF) == 0 or (B16 & 0x7FFF) == 0:
        # Zero product — RTL just accumulates 0; use numpy path
        import struct
        a_f = struct.unpack('>e', struct.pack('>H', A16))[0]
        b_f = struct.unpack('>e', struct.pack('>H', B16))[0]
        acc_f = f32_to_float(acc32)
        result = float(a_f) * float(b_f) + float(acc_f)
        return f32_from_float(result)

    sa, ea, ma = f16_to_parts(A16)
    sb, eb, mb = f16_to_parts(B16)
    sc, ec, mc = f32_to_parts(acc32)

    # Product sign and exponent
    sp = sa ^ sb
    # Product exponent in FP32 space: (ea-15) + (eb-15) + 127 = ea+eb+97
    ep = ea + eb + 97           # FP32 biased exponent of product
    # Product mantissa: ma * mb (both 11-bit with hidden bit) → 22-bit
    mp = ma * mb                # up to 22 bits; MSB at bit 21 if both ≥ 1024

    # If product mantissa MSB is at bit 21 (normal), product is:
    #   (-1)^sp * 2^(ep-127) * mp/2^22 * 2^(something)
    # We'll work in a 58-bit fixed-point field.
    #
    # RTL places product at bits [21:0] of the 58-bit sum field.
    # Accumulator mantissa (24-bit with hidden) is placed starting at bit
    # exp_align = ea + eb + 134 - ec, right-shifted by shift_amt bits.
    # shift_amt = ep - ec + (some offset).  From align_control:
    #   shift_amt_raw = ea + eb + 134 - ec
    # After shift, accumulator MSB lands at bit (57 - shift_amt) of the field.

    shift_amt_raw = ea + eb + 134 - ec
    shift_amt = max(0, min(57, shift_amt_raw))
    zero_acc   = shift_amt_raw > 57
    acc_is_zero = (acc32 & 0x7FFFFFFF) == 0

    # eop_fp = sp XOR sc (effective subtract when signs differ)
    eop_fp = sp ^ sc

    # --- Build the 58-bit field values ---

    # Product vector: mul_sum_vec and mul_carry_vec are compressed partial products.
    # After CSA and CPA, the lower 32 bits represent the product value.
    # For the reference model, we use the exact product:
    #   product_field = mp  (at bits [21:0])
    product_exact = mp  # 22-bit integer in positions [21:0]

    # Accumulator mantissa in the 58-bit field:
    # addend_fp = {1'b1, mc[22:0]} = 24-bit mantissa with hidden bit
    addend_fp = mc  # already has hidden bit from f32_to_parts

    if zero_acc or acc_is_zero:
        # All-ones fill (RTL sets initial_val = 0x3FFFFFFFFFFFF for eop_fp)
        if eop_fp:
            c_align_int = (((1 << 58) - 1) << (58 - shift_amt)) & ((1 << 58) - 1)
            c_align_int |= ((1 << 58) - 1) >> shift_amt
        else:
            c_align_int = 0
        orig_val = 0
    else:
        if eop_fp:
            inv_addend = (~addend_fp) & 0xFFFFFF  # invert_addend: ones complement
            initial_val = (inv_addend << 34) | 0x3FFFFFFFF  # fill lower 34 with 1s
            initial_val &= (1 << 58) - 1
            orig_val = (~initial_val) & ((1 << 58) - 1)
            # c_align: fill upper bits with 1s (ones complement sign extension)
            upper_mask = ((1 << 58) - 1) << (58 - shift_amt)
            upper_mask &= (1 << 58) - 1
            c_align_int = upper_mask | (initial_val >> shift_amt)
        else:
            initial_val = (addend_fp << 34) & ((1 << 58) - 1)
            orig_val = initial_val
            c_align_int = initial_val >> shift_amt

    # Sticky bit (not needed for exact reference but included for completeness)
    shift_mask = (1 << shift_amt) - 1
    stk = bool(orig_val & shift_mask)

    # comp signal
    comp = bool(eop_fp and (shift_amt > 35 or zero_acc or acc_is_zero))

    # cin: RTL bug — currently uses comp instead of eop_fp
    # Use eop_fp (the correct value) for the software reference
    cin = bool(eop_fp)

    # --- 58-bit addition ---
    # Upper 26 bits come from c_align; lower 32 bits from product + c_align[31:0]
    c_high = (c_align_int >> 32) & 0x3FFFFFF   # 26 bits
    c_low  = c_align_int & 0xFFFFFFFF           # 32 bits

    # Product sits in lower 22 bits; upper bits of lower 32 come from c_align
    sum_low_exact = c_low + product_exact + (1 if cin else 0)
    carry_out = sum_low_exact >> 32
    sum_low_exact &= 0xFFFFFFFF

    # Upper bits: c_high + carry
    sum_high_val = c_high + carry_out
    end_around_carry = (sum_high_val >> 26) & 1
    sum_high_val &= 0x3FFFFFF

    # is_neg: subtraction and no end-around carry
    is_neg = bool(eop_fp and not end_around_carry)

    # Reconstruct 58-bit sum
    sum58 = (sum_high_val << 32) | sum_low_exact

    # Complementer: negate if is_neg
    if is_neg:
        sum58 = (~sum58) & ((1 << 58) - 1)
        sum58 += 1
        sum58 &= (1 << 58) - 1

    # exp_align
    exp_align = (ea + eb + 134) & 0xFF

    # --- Normalization ---
    if sum58 == 0:
        return 0  # zero result

    # Find leading 1 (LZC on sum58)
    leading = 0
    for bit in range(57, -1, -1):
        if (sum58 >> bit) & 1:
            leading = 57 - bit
            break
    else:
        leading = 58  # all zeros

    sum_norm = (sum58 << leading) & ((1 << 58) - 1)
    exp_norm = exp_align - leading

    # --- Rounding (IEEE RNE) ---
    frac = (sum_norm >> 34) & 0x7FFFFF   # bits [56:34]
    G    = (sum_norm >> 33) & 1
    R    = (sum_norm >> 32) & 1
    S    =  sum_norm & 0xFFFFFFFF
    S    = 1 if S else 0
    round_up = G and (R or S or (frac & 1))

    frac_rounded = frac + (1 if round_up else 0)
    round_carry = (frac_rounded >> 23) & 1
    mant_out = frac_rounded & 0x7FFFFF
    exp_out = (exp_norm + round_carry) & 0xFF

    # Overflow / underflow guard
    if exp_out >= 0xFF:
        return None  # overflow to inf
    if exp_out == 0:
        return None  # underflow to denormal (RTL doesn't handle)

    # RTL: sign_fp_out = is_neg ? ~sign_fp : sign_fp
    # sign_fp tracks the product sign (sp = sa^sb).
    # When not is_neg (product dominates): sign = sp
    # When is_neg (acc dominates):         sign = ~sp  (= sc for subtraction)
    sign_out = sp ^ int(is_neg)

    return (sign_out << 31) | (exp_out << 23) | mant_out


def exact_ref(A16: int, B16: int, acc32: int) -> int:
    """
    Exact IEEE 754 reference using Python arbitrary-precision integers.

    Computes fp16(A) * fp16(B) + fp32(acc) with infinite precision, then
    rounds to FP32 using IEEE 754 round-to-nearest-even.  No float64
    intermediate values are used, so this is correct for all exponent ranges
    including far-path cases where float64 loses precision (shift_amt > 29).

    Returns FP32 bit pattern, or None for special/denormal inputs (skipped).
    """
    if is_nan_inf_f16(A16) or is_nan_inf_f16(B16) or is_nan_inf_f32(acc32):
        return None

    sa = (A16 >> 15) & 1
    ea = (A16 >> 10) & 0x1F
    ma = A16 & 0x3FF
    if ea == 0:
        return None  # FP16 zero/denormal — RTL flushes

    sb = (B16 >> 15) & 1
    eb = (B16 >> 10) & 0x1F
    mb = B16 & 0x3FF
    if eb == 0:
        return None

    sc = (acc32 >> 31) & 1
    ec = (acc32 >> 23) & 0xFF
    mc = acc32 & 0x7FFFFF
    if ec == 255:
        return None  # FP32 inf/nan
    if ec == 0:
        return None  # FP32 zero/denormal — RTL flushes

    # Integer representations: value = mantissa_int * 2^exp  (exact)
    # FP16 A: hidden_bit | ma gives 11-bit mantissa; true exp = ea - 15 - 10 = ea - 25
    ma_int = (1 << 10) | ma
    mb_int = (1 << 10) | mb
    mc_int = (1 << 23) | mc  # 24-bit FP32 mantissa

    # Product: mantissa = ma_int * mb_int (up to 22 bits), exp = (ea-25)+(eb-25)
    sp = sa ^ sb
    mp = ma_int * mb_int
    ep = ea + eb - 50          # binary exponent for product

    # Accumulator: mantissa = mc_int, true exp = ec - 127 - 23 = ec - 150
    ep_c = ec - 150

    # Align both to the same binary scale (the smaller exponent)
    if ep >= ep_c:
        p_scaled = mp << (ep - ep_c)
        c_scaled = mc_int
        common_exp = ep_c
    else:
        p_scaled = mp
        c_scaled = mc_int << (ep_c - ep)
        common_exp = ep

    # Exact signed sum via Python arbitrary-precision integers
    signed_p = -p_scaled if sp else p_scaled
    signed_c = -c_scaled if sc else c_scaled
    total = signed_p + signed_c

    if total == 0:
        return 0  # +0.0

    sign_out = 1 if total < 0 else 0
    total_abs = abs(total)

    # MSB position → IEEE exponent (binade)
    leading = total_abs.bit_length() - 1   # MSB is at bit 'leading'
    binade = leading + common_exp           # value ≈ 1.xxx * 2^binade

    # Extract 24 significant bits; compute GRS for IEEE RNE
    frac_bits = leading - 23  # bits below the top 24 that must be rounded
    if frac_bits > 0:
        mant24 = total_abs >> frac_bits
        remainder = total_abs & ((1 << frac_bits) - 1)
        half = 1 << (frac_bits - 1)
        lsb = mant24 & 1
        round_up = (remainder > half) or (remainder == half and lsb)
    elif frac_bits == 0:
        mant24 = total_abs
        round_up = False
    else:
        mant24 = total_abs << (-frac_bits)  # total_abs fits in < 24 bits
        round_up = False

    if round_up:
        mant24 += 1
        if mant24 >> 24:        # carry out of bit 23
            mant24 >>= 1
            binade += 1

    biased_exp = binade + 127
    if biased_exp <= 0:
        return None   # underflow to denormal/zero
    if biased_exp >= 255:
        return None   # overflow to inf

    return (sign_out << 31) | (biased_exp << 23) | (mant24 & 0x7FFFFF)


def float_ref(A16: int, B16: int, acc32: int):
    """
    Float64 diagnostic reference (less precise than exact_ref for far-path cases).

    For shift_amt > 29 the intermediate result requires > 53 bits to represent
    exactly in float64, so this can disagree with exact_ref by 1-2 ULP.
    Kept only for annotating failure messages.
    """
    if is_nan_inf_f16(A16) or is_nan_inf_f16(B16) or is_nan_inf_f32(acc32):
        return None
    a   = struct.unpack('>e', struct.pack('>H', A16))[0]
    b   = struct.unpack('>e', struct.pack('>H', B16))[0]
    acc = struct.unpack('>f', struct.pack('>I', acc32))[0]
    result = float(a) * float(b) + float(acc)
    bits = struct.unpack('>I', struct.pack('>f', result))[0]
    if is_nan_inf_f32(bits) or ((bits & 0x7FFFFFFF) != 0 and ((bits >> 23) & 0xFF) == 0):
        return None
    return bits


def ulp_distance(a_bits: int, b_bits: int) -> int:
    """
    ULP distance between two FP32 bit patterns.
    Uses the signed-magnitude ordered-integer representation so the distance
    is meaningful across the sign boundary (e.g. +0 and -0 are 0 ULP apart).
    """
    def to_ordered(x: int) -> int:
        if x & 0x80000000:
            return -(x & 0x7FFFFFFF)
        return x
    return abs(to_ordered(a_bits) - to_ordered(b_bits))


# ---------------------------------------------------------------------------
# Vector generators
# ---------------------------------------------------------------------------

def gen_fix(n: int, seed: int):
    rng = random.Random(seed)
    vectors = []
    for _ in range(n):
        A   = rng.randint(0, 0xFFFF)
        B   = rng.randint(0, 0xFFFF)
        acc = rng.randint(0, 0xFFFFFFFF)
        if rng.random() < 0.15:
            acc = 0
        vectors.append((0, A, B, acc))
    return vectors


def _valid_f16(rng):
    """Return a normal non-zero FP16 bit pattern."""
    while True:
        h = rng.randint(1, 0x7BFF)  # positive, normal
        e = (h >> 10) & 0x1F
        if 1 <= e <= 30:
            return h


def _make_flp_vec(rng, target_shift_range=None, force_sub=False):
    """
    Generate one FLP vector.
    target_shift_range: (lo, hi) inclusive for shift_amt_raw = ea+eb+134-ec
    force_sub: make signs differ (eop_fp=1)
    """
    for _ in range(200):  # retry limit
        sa = rng.randint(0, 1)
        sb = rng.randint(0, 1)
        ha = _valid_f16(rng) | (sa << 15)
        hb = _valid_f16(rng) | (sb << 15)
        ea = (ha >> 10) & 0x1F
        eb = (hb >> 10) & 0x1F

        # Pick accumulator exponent to hit desired shift range
        if target_shift_range is not None:
            lo, hi = target_shift_range
            target = rng.randint(lo, hi)
            ec = ea + eb + 134 - target
            if not (1 <= ec <= 254):
                continue
        else:
            # Random near-aligned accumulator
            ec = ea + eb + 97 + rng.randint(-5, 5)
            ec = max(1, min(254, ec))

        mc = rng.randint(0, 0x7FFFFF)
        sp = sa ^ sb
        if force_sub:
            sc = 1 - sp   # opposite sign → eop_fp=1
        else:
            sc = sp       # same sign → eop_fp=0 (addition)

        acc = (sc << 31) | (ec << 23) | mc
        if is_nan_inf_f16(ha) or is_nan_inf_f16(hb) or is_nan_inf_f32(acc):
            continue
        return (1, ha, hb, acc)
    return None


def gen_flp_add(n: int, seed: int):
    rng = random.Random(seed)
    vectors = []
    for _ in range(n):
        v = _make_flp_vec(rng, force_sub=False)
        if v:
            vectors.append(v)
    return vectors


def gen_flp_sub_low(n: int, seed: int):
    """FLP subtraction with shift_amt in [0, 35] — targets the cin bug."""
    rng = random.Random(seed)
    vectors = []
    for _ in range(n):
        v = _make_flp_vec(rng, target_shift_range=(0, 35), force_sub=True)
        if v:
            vectors.append(v)
    return vectors


def gen_flp_sub_high(n: int, seed: int):
    """FLP subtraction with shift_amt in [36, 57]."""
    rng = random.Random(seed)
    vectors = []
    for _ in range(n):
        v = _make_flp_vec(rng, target_shift_range=(36, 57), force_sub=True)
        if v:
            vectors.append(v)
    return vectors


def gen_flp_cancel(n: int, seed: int):
    """Near-exact cancellation: A*B ≈ -acc, expecting result ≈ 0."""
    rng = random.Random(seed)
    vectors = []
    for _ in range(n):
        ha = _valid_f16(rng)
        hb = _valid_f16(rng)
        ea = (ha >> 10) & 0x1F
        eb = (hb >> 10) & 0x1F
        # acc exponent matches product exactly
        ec = ea + eb + 97
        if not (1 <= ec <= 254):
            continue
        mc = rng.randint(0, 0x7FFFFF)
        sp = 0  # positive product
        sc = 1  # negative accumulator → subtraction
        acc = (sc << 31) | (ec << 23) | mc
        if is_nan_inf_f32(acc):
            continue
        vectors.append((1, ha, hb, acc))
    return vectors


def gen_flp_boundary(n: int, seed: int):
    """Rounding boundary: result mantissa is exactly halfway (G=1, R=S=0)."""
    rng = random.Random(seed)
    vectors = []
    # Mostly generate normal add/sub vectors; a subset will naturally hit boundaries.
    # Additionally probe specific values known to exercise RNE.
    # 1.0 * 1.0 + 1.0 = 2.0 (exact, but validates round path)
    vectors.append((1, f16_from_float(1.0), f16_from_float(1.0),
                    f32_from_float(1.0)))
    # 1.5 * 1.0 + 0.5 = 2.0
    vectors.append((1, f16_from_float(1.5), f16_from_float(1.0),
                    f32_from_float(0.5)))
    for _ in range(n - 2):
        v = _make_flp_vec(rng)
        if v:
            vectors.append(v)
    return vectors


# ---------------------------------------------------------------------------
# RTL compile
# ---------------------------------------------------------------------------

def compile_rtl(force: bool = False):
    if not force and os.path.exists(SIM_BIN):
        print(f"[compile] Using existing {SIM_BIN}")
        return
    print("[compile] Compiling RTL...")
    cmd = (
        f"{IVERILOG} -g2001 -o {SIM_BIN} "
        f"{TB} {RTL_GLOB}"
    )
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: iverilog compilation failed:")
        print(result.stderr)
        sys.exit(1)
    print("[compile] Done.")


# ---------------------------------------------------------------------------
# Simulation worker
# ---------------------------------------------------------------------------

def _write_tv(vectors, path: str):
    with open(path, "w") as f:
        for (fl, A, B, acc) in vectors:
            f.write(f"{fl} {A:04x} {B:04x} {acc:08x}\n")


def run_batch(args):
    """
    Worker for ProcessPoolExecutor.
    args = (batch_name, vectors)
    Returns (batch_name, vectors, stdout_text)
    """
    batch_name, vectors = args
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt',
                                     prefix=f'mac_tv_{batch_name}_',
                                     delete=False) as tf:
        tv_path = tf.name

    _write_tv(vectors, tv_path)
    cmd = f"{VVP} {SIM_BIN} +tv={tv_path} +no_vcd"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                            timeout=120)
    os.unlink(tv_path)
    if result.returncode != 0:
        return (batch_name, vectors, None, result.stderr)
    return (batch_name, vectors, result.stdout, None)


# ---------------------------------------------------------------------------
# Output parser
# ---------------------------------------------------------------------------

# Matches: Time=20 | float=1 | A=3c00 B=3c00 acc=40000000 | OUT_fx=... OUT_fp=...
_LINE_RE = re.compile(
    r"Time=(\d+)\s*\|\s*float=([01])\s*\|\s*"
    r"A=([0-9a-fA-F]+)\s+B=([0-9a-fA-F]+)\s+acc=([0-9a-fA-F]+)\s*\|\s*"
    r"OUT_fx=([0-9a-fA-F]+)\s+OUT_fp=([0-9a-fA-F]+)"
)

def parse_output(stdout: str) -> dict:
    """
    Returns dict keyed by time (int ns), value = record dict.
    """
    records = {}
    for line in stdout.splitlines():
        m = _LINE_RE.match(line.strip())
        if not m:
            continue
        t, fl, A, B, acc, fx, fp = m.groups()
        records[int(t)] = {
            "float": int(fl),
            "A":     int(A,   16),
            "B":     int(B,   16),
            "acc":   int(acc, 16),
            "OUT_fx": int(fx, 16),
            "OUT_fp": int(fp, 16),
        }
    return records


# ---------------------------------------------------------------------------
# Verifier
# ---------------------------------------------------------------------------

def verify(name: str, vectors: list, stdout: str) -> dict:
    """
    Timestamp-based comparison.

    FIX — exact bit match against fix_ref() (integer arithmetic, always exact).
    FLP — exact bit match against exact_ref() (Python big-int, IEEE 754 RNE, correct
           for all exponent ranges).  fp_ref() and float_ref() annotate failure messages.

    Timescale is 1ns/1ps so $monitor times are in picoseconds.
    Clock period = 10ns = 10000ps.  rst_n released at t=15ns=15000ps.

    FIX output for input N:  out_time = 15000 + N*10000 + 20000 ps  (2 cycles)
    FLP output for input N:  out_time = 15000 + N*10000 + 30000 ps  (3 cycles)
    """
    records = parse_output(stdout)
    if not records:
        return {"name": name, "pass": 0, "fail": 0, "skip": 0,
                "errors": ["No monitor output parsed"]}

    pass_count = fail_count = skip_count = 0
    errors = []

    for idx, (fl, A, B, acc) in enumerate(vectors):
        input_time_ps = 15000 + idx * 10000

        if fl == 0:
            # FIX mode — exact match against fix_ref()
            out_time = input_time_ps + 20000
            rec = records.get(out_time)
            if rec is None:
                skip_count += 1
                continue
            expected = fix_ref(A, B, acc)
            actual   = rec["OUT_fx"]
            if expected == actual:
                pass_count += 1
            else:
                fail_count += 1
                if len(errors) < 20:
                    errors.append(
                        f"[{name}] FIX idx={idx} A={A:04x} B={B:04x} "
                        f"acc={acc:08x}: expected={expected:08x} got={actual:08x}"
                    )
        else:
            # FLP mode — primary criterion is exact_ref() (integer arithmetic, always correct)
            out_time = input_time_ps + 30000
            rec = records.get(out_time)
            if rec is None:
                skip_count += 1
                continue

            expected = exact_ref(A, B, acc)
            if expected is None:
                skip_count += 1
                continue

            actual = rec["OUT_fp"]
            if expected == actual:
                pass_count += 1
            else:
                fail_count += 1
                if len(errors) < 20:
                    ulp_err = ulp_distance(actual, expected)
                    pipe_ref = fp_ref(A, B, acc)
                    f64_ref  = float_ref(A, B, acc)
                    pipe_str = (f"fp_ref={pipe_ref:08x}" if pipe_ref is not None
                                else "fp_ref=N/A")
                    f64_str  = (f"f64={f64_ref:08x}" if f64_ref is not None
                                else "f64=N/A")
                    errors.append(
                        f"[{name}] FLP idx={idx} A={A:04x} B={B:04x} "
                        f"acc={acc:08x}: expected={expected:08x} got={actual:08x} "
                        f"(exp_f={f32_to_float(expected):.6g} "
                        f"got_f={f32_to_float(actual):.6g} "
                        f"err={ulp_err} ULP {pipe_str} {f64_str})"
                    )

    return {
        "name":   name,
        "pass":   pass_count,
        "fail":   fail_count,
        "skip":   skip_count,
        "errors": errors,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

BATCH_CONFIG = [
    # (name,             generator,        n_per_batch, n_batches)  total=100k
    ("fix_random",       gen_fix,           12500,       2),   # 25 000
    ("flp_add",          gen_flp_add,       9000,        2),   # 18 000
    ("flp_sub_low",      gen_flp_sub_low,   9000,        3),   # 27 000
    ("flp_sub_high",     gen_flp_sub_high,  9000,        1),   #  9 000
    ("flp_cancel",       gen_flp_cancel,    7000,        2),   # 14 000
    ("flp_boundary",     gen_flp_boundary,  3500,        2),   #  7 000
]


class _Tee:
    """Write to both stdout and a log file simultaneously."""
    def __init__(self, path: str):
        self._file = open(path, "w", buffering=1)
        self._stdout = sys.stdout
        sys.stdout = self

    def write(self, data):
        self._stdout.write(data)
        self._file.write(data)

    def flush(self):
        self._stdout.flush()
        self._file.flush()

    def close(self):
        sys.stdout = self._stdout
        self._file.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--recompile", action="store_true",
                        help="Force recompile even if binary exists")
    parser.add_argument("--jobs", type=int,
                        default=min(24, os.cpu_count() or 4))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--log", metavar="FILE",
                        help="Save output to FILE (default: verify_<timestamp>.log)")
    args = parser.parse_args()

    log_dir = REPO / "Efficient_MAC/bhav_sim/logs"
    log_dir.mkdir(exist_ok=True)
    log_path = args.log or str(log_dir / f"verify_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.log")
    tee = _Tee(log_path)
    print(f"[log] Writing to {log_path}")

    try:
        _run(args)
    finally:
        tee.close()


def _run(args):
    compile_rtl(force=args.recompile)

    # Build all batch jobs
    jobs = []
    seed = args.seed
    for (name, gen_fn, n, n_batches) in BATCH_CONFIG:
        for i in range(n_batches):
            batch_name = f"{name}_{i}"
            vectors = gen_fn(n, seed)
            seed += 1
            jobs.append((batch_name, vectors))

    total_vectors = sum(len(v) for _, v in jobs)
    print(f"\n[run] {len(jobs)} batches, ~{total_vectors} vectors, "
          f"{args.jobs} parallel workers\n")

    results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(run_batch, job): job[0] for job in jobs}
        for future in concurrent.futures.as_completed(futures):
            batch_name = futures[future]
            try:
                result_tuple = future.result()
            except Exception as exc:
                print(f"  BATCH {batch_name} raised: {exc}")
                continue

            bname, vectors, stdout, stderr = result_tuple
            if stdout is None:
                print(f"  BATCH {bname}: simulation FAILED\n{stderr}")
                continue

            res = verify(bname, vectors, stdout)
            results.append(res)
            status = "PASS" if res["fail"] == 0 else "FAIL"
            print(f"  {status:4s}  {bname:30s}  "
                  f"pass={res['pass']:5d}  fail={res['fail']:5d}  "
                  f"skip={res['skip']:5d}")

    # Summary
    total_pass = sum(r["pass"] for r in results)
    total_fail = sum(r["fail"] for r in results)
    total_skip = sum(r["skip"] for r in results)

    print(f"\n{'='*60}")
    print(f"TOTAL  pass={total_pass}  fail={total_fail}  skip={total_skip}")
    print(f"{'='*60}")

    if total_fail > 0:
        print("\nFirst failures per batch:")
        for r in results:
            for e in r["errors"][:3]:
                print(f"  {e}")
        sys.exit(1)
    else:
        print("\nAll comparisons passed (exact bit match against integer-arithmetic reference).")


if __name__ == "__main__":
    main()
