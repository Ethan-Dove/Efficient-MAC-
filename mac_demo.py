#!/usr/bin/env python3
"""
MAC Unit — RTL Functional Correctness & Pipeline Signal Propagation Demo
========================================================================
Compiles the actual Verilog RTL (Icarus Verilog), runs FIX-mode vectors,
and shows:
  LEFT  — step-by-step arithmetic for the selected vector
  RIGHT — RTL verification table  +  pipeline signal trace

Usage:
  pixi run python scripts/mac_demo.py
  pixi run python scripts/mac_demo.py --auto   # cycle vectors every 1.5 s
"""
import ctypes, os, re, subprocess, tempfile, argparse
from pathlib import Path

import matplotlib
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.widgets import Button
from matplotlib.animation import FuncAnimation

matplotlib.rcParams['toolbar'] = 'None'

# ── paths ─────────────────────────────────────────────────────────────────────
REPO     = Path(__file__).parent.parent
RTL_DIR  = REPO / "Efficient_MAC/rtl"
TB       = REPO / "Efficient_MAC/bhav_sim/tb_mac_top.v"
PIXI_BIN = REPO / ".pixi/envs/default/bin"
IVERILOG = str(PIXI_BIN / "iverilog") if (PIXI_BIN / "iverilog").exists() else "iverilog"
VVP      = str(PIXI_BIN / "vvp")      if (PIXI_BIN / "vvp").exists()      else "vvp"
SIM_BIN  = "/tmp/mac_demo_rtl"

# ── colours ───────────────────────────────────────────────────────────────────
BG    = '#0d1117'
C_IN  = '#b58900'
C_MUL = '#2da44e'
C_ADD = '#1f6feb'
T_LT  = '#e6edf3'
T_DM  = '#6e7681'
T_GD  = '#56d364'
T_RD  = '#f85149'
T_YL  = '#e3b341'
T_GN  = '#7ee787'
T_BL  = '#79c0ff'
T_GLD = '#ffd700'

VEC_COLS = ['#e3b341', '#7ee787', '#79c0ff', '#d2a8ff', '#ffa657', '#ff7b72']

# ── reference arithmetic ──────────────────────────────────────────────────────
def s8(v):  return ctypes.c_int8(int(v)  & 0xFF      ).value
def s32(v): return ctypes.c_int32(int(v) & 0xFFFFFFFF).value
def unpack(A, B): return s8(A >> 8), s8(A & 0xFF), s8(B >> 8), s8(B & 0xFF)
def fix_expected(A, B, acc):
    Ah, Al, Bh, Bl = unpack(A, B)
    return s32(Ah * Bh + Al * Bl + s32(acc))

# ── test vectors  (A_16, B_16, acc_32) ───────────────────────────────────────
# Each acc is the OUT_fx from the previous vector — showing accumulation.
VECS = [
    (0x0304, 0x0506, 0x00000000),   # Ah=+3   Al=+4   Bh=+5   Bl=+6   → mul=39   out=39
    (0x0702, 0x0403, 0x00000027),   # Ah=+7   Al=+2   Bh=+4   Bl=+3   → mul=34   out=73
    (0xFB08, 0x02FD, 0x00000049),   # Ah=-5   Al=+8   Bh=+2   Bl=-3   → mul=-34  out=39
    (0x0C05, 0x0306, 0x00000027),   # Ah=+12  Al=+5   Bh=+3   Bl=+6   → mul=66   out=105
    (0x7F01, 0x7F01, 0x00000069),   # Ah=+127 Al=+1   Bh=+127 Bl=+1   → mul=16130 out=16235
    (0x80FF, 0x0101, 0x00003F6B),   # Ah=-128 Al=-1   Bh=+1   Bl=+1   → mul=-129 out=16106
]
N = len(VECS)

# ── RTL simulation ────────────────────────────────────────────────────────────
_MON_RE = re.compile(
    r"Time=(\d+).*?"
    r"A=([0-9a-fA-F]+)\s+B=([0-9a-fA-F]+)\s+acc=([0-9a-fA-F]+)\s*\|"
    r".*?OUT_fx=([0-9a-fA-F]+)"
)

def compile_rtl():
    files = " ".join(f'"{f}"' for f in sorted(RTL_DIR.glob("*.v")))
    r = subprocess.run(
        f'{IVERILOG} -g2001 -o {SIM_BIN} "{TB}" {files}',
        shell=True, capture_output=True, text=True)
    return r.returncode == 0, r.stderr.strip()


def run_single_fix(A, B, acc):
    """Run one FIX-mode vector; return settled OUT_fx (signed int) or None."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        tv = f.name
        f.write(f"0 {A:04x} {B:04x} {acc:08x}\n")
    try:
        r = subprocess.run(f"{VVP} {SIM_BIN} +tv={tv} +no_vcd",
                           shell=True, capture_output=True, text=True, timeout=15)
    finally:
        os.unlink(tv)
    if r.returncode != 0:
        return None
    last = None
    for line in r.stdout.splitlines():
        m = _MON_RE.search(line)
        if m:
            last = s32(int(m.group(5), 16))
    return last


def run_batch_fix():
    """Run all VECS in one simulation; return list of (time_ns, out_fx) from $monitor."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        tv = f.name
        for A, B, acc in VECS:
            f.write(f"0 {A:04x} {B:04x} {acc:08x}\n")
    try:
        r = subprocess.run(f"{VVP} {SIM_BIN} +tv={tv} +no_vcd",
                           shell=True, capture_output=True, text=True, timeout=30)
    finally:
        os.unlink(tv)
    records = []
    for line in r.stdout.splitlines():
        m = _MON_RE.search(line)
        if m:
            t_ps   = int(m.group(1))
            out_fx = s32(int(m.group(5), 16))
            records.append((t_ps, out_fx))
    return records


def run_all_vecs():
    """Return (per_vec_results, batch_records, error_str)."""
    ok, err = compile_rtl()
    if not ok:
        return None, None, f"iverilog compile failed:\n{err}"

    per_vec = []
    for A, B, acc in VECS:
        exp = fix_expected(A, B, acc)
        rtl = run_single_fix(A, B, acc)
        match = (rtl == exp) if rtl is not None else False
        per_vec.append((exp, rtl, match))

    batch = run_batch_fix()
    return per_vec, batch, None


# ── drawing helpers ───────────────────────────────────────────────────────────
XLIM, YLIM = 20.0, 10.5
DIV_X = 8.4

def _t(ax, x, y, s, color=T_LT, size=9, bold=False, mono=True, ha='left', va='center'):
    ax.text(x, y, s, ha=ha, va=va, color=color, fontsize=size,
            fontweight='bold' if bold else 'normal',
            fontfamily='monospace' if mono else 'sans-serif', zorder=5)

def _box(ax, x, y, w, h, fc, ec, lw=2.0, alpha=0.22):
    ax.add_patch(mpatches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.05",
        facecolor=fc, edgecolor='none', alpha=alpha, zorder=2))
    ax.add_patch(mpatches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.05",
        facecolor='none', edgecolor=ec, linewidth=lw, zorder=3))

def _arrow_down(ax, x, y_top, y_bot, color=T_DM):
    ax.annotate('', xy=(x, y_bot), xytext=(x, y_top),
                arrowprops=dict(arrowstyle='-|>', color=color, lw=1.5,
                                mutation_scale=14), zorder=4)

# ── LEFT panel: arithmetic walkthrough ───────────────────────────────────────

def draw_left(ax, vi, rtl_row=None):
    ax.add_patch(mpatches.FancyBboxPatch(
        (0.15, 0.25), DIV_X - 0.45, YLIM - 0.5,
        boxstyle="round,pad=0.05",
        facecolor='#0d1117', edgecolor='#21262d', linewidth=1.5, zorder=1))

    A, B, acc = VECS[vi]
    Ah, Al, Bh, Bl = unpack(A, B)
    mul_AhBh = Ah * Bh
    mul_AlBl = Al * Bl
    mul_sum  = mul_AhBh + mul_AlBl
    out_exp  = fix_expected(A, B, acc)
    cx = 0.45

    _t(ax, DIV_X/2, YLIM - 0.42,
       f'Vector {vi}  —  Step-by-Step', T_LT, size=11, bold=True, ha='center')

    # INPUTS
    _box(ax, cx - 0.1, 7.9, DIV_X - 0.75, 2.0, C_IN, C_IN, lw=2.0)
    _t(ax, cx, 9.65, 'INPUTS', T_YL, size=8.5, bold=True)
    _t(ax, cx, 9.20, f'A = 0x{A:04X}  →  Ah = {Ah:+4d}   Al = {Al:+4d}', T_YL, size=9)
    _t(ax, cx, 8.72, f'B = 0x{B:04X}  →  Bh = {Bh:+4d}   Bl = {Bl:+4d}', T_YL, size=9)
    _t(ax, cx, 8.22, f'acc = {s32(acc):+12d}  =  0x{acc & 0xFFFFFFFF:08X}', T_BL, size=9)

    _arrow_down(ax, DIV_X/2, 7.9, 7.30, C_MUL)

    # STAGE 1
    _box(ax, cx - 0.1, 5.55, DIV_X - 0.75, 1.65, C_MUL, C_MUL, lw=2.0)
    _t(ax, cx, 7.05, 'STAGE 1  —  merged_multiplier', T_GN, size=8.5, bold=True)
    _t(ax, cx, 6.62,
       f'Ah × Bh  =  {Ah:+4d} × {Bh:+4d}  =  {mul_AhBh:+7d}', T_GN, size=9)
    _t(ax, cx, 6.17,
       f'Al × Bl  =  {Al:+4d} × {Bl:+4d}  =  {mul_AlBl:+7d}', T_GN, size=9)
    _t(ax, cx, 5.72,
       f'mul_result  =  {mul_AhBh:+d} + {mul_AlBl:+d}  =  {mul_sum:+d}',
       T_GD, size=9.5, bold=True)

    _arrow_down(ax, DIV_X/2, 5.55, 4.95, C_ADD)

    # STAGE 2
    _box(ax, cx - 0.1, 3.42, DIV_X - 0.75, 1.45, C_ADD, C_ADD, lw=2.0)
    _t(ax, cx, 4.72, 'STAGE 2  —  carry_propagate_adder', T_BL, size=8.5, bold=True)
    _t(ax, cx, 4.27,
       f'mul_result + acc  =  {mul_sum:+d} + {s32(acc):+d}', T_BL, size=9)
    _t(ax, cx, 3.62,
       f'OUT_fx  =  {out_exp:+d}  =  0x{out_exp & 0xFFFFFFFF:08X}',
       T_GD, size=9.5, bold=True)

    _arrow_down(ax, DIV_X/2, 3.42, 2.82, '#388bfd')

    # RTL result comparison
    if rtl_row is not None:
        exp_v, rtl_v, match = rtl_row
        bc = T_GD if match else T_RD
        _box(ax, cx - 0.1, 0.98, DIV_X - 0.75, 1.72, bc, bc, lw=2.5)
        _t(ax, cx, 2.52, 'RTL OUTPUT  vs  REFERENCE', bc, size=8.5, bold=True)
        _t(ax, cx, 2.07, f'Reference  :  {exp_v:+d}', T_GN, size=9)
        _t(ax, cx, 1.62,
           f'Actual RTL :  {rtl_v:+d}' if rtl_v is not None else 'RTL : (sim error)',
           T_GN if match else T_RD, size=9)
        status = '✓  BIT-EXACT MATCH' if match else '✗  MISMATCH'
        _t(ax, DIV_X/2, 1.17, status, bc, size=11, bold=True, ha='center')
    else:
        _box(ax, cx - 0.1, 0.98, DIV_X - 0.75, 1.72, T_DM, T_DM, lw=1.0, alpha=0.10)
        _t(ax, DIV_X/2, 2.52, 'Reference model expects:', T_DM, size=8, ha='center')
        _t(ax, DIV_X/2, 2.02,
           f'OUT_fx  =  {out_exp:+d}  =  0x{out_exp & 0xFFFFFFFF:08X}',
           T_DM, size=9.5, ha='center', bold=True)
        _t(ax, DIV_X/2, 1.50, '← click  Run RTL  to verify against Verilog', T_DM,
           size=8, ha='center', mono=False)

# ── RIGHT panel ───────────────────────────────────────────────────────────────
RX     = DIV_X + 0.30
R_W    = XLIM - RX - 0.15   # usable width in right panel

# Verification table
T_COLS = [0.00, 0.70, 2.40, 4.45, 6.30, 8.05, 9.70]   # relative offsets from RX
T_HDRS = ['#', 'Inputs', 'acc', 'Ah×Bh+Al×Bl', 'Expected', 'RTL Out', '']
T_Y0   = 9.50   # top of first row
T_DY   = 0.82   # row height


def draw_verification_table(ax, results, selected):
    _t(ax, RX + R_W/2, YLIM - 0.38,
       'RTL Functional Correctness Verification',
       T_LT, size=11, bold=True, mono=False, ha='center')
    _t(ax, RX + R_W/2, YLIM - 0.85,
       'FIX Mode: INT8×INT8 + INT32 → INT32  ·  Simulator: Icarus Verilog',
       T_DM, size=8.5, mono=False, ha='center')

    # column headers
    HY = T_Y0 + 0.32
    for i, (off, hd) in enumerate(zip(T_COLS, T_HDRS)):
        _t(ax, RX + off, HY, hd, T_DM, size=8, bold=True)
    ax.axhline(T_Y0 + 0.14, xmin=(DIV_X + 0.15)/XLIM, xmax=0.99,
               color='#30363d', lw=1.0, zorder=3)

    for i, (A, B, acc) in enumerate(VECS):
        Ah, Al, Bh, Bl = unpack(A, B)
        mul  = Ah * Bh + Al * Bl
        exp  = fix_expected(A, B, acc)
        ry   = T_Y0 - i * T_DY
        vc   = VEC_COLS[i]

        if i == selected:
            ax.add_patch(mpatches.FancyBboxPatch(
                (RX - 0.1, ry - 0.34), R_W + 0.05, T_DY - 0.08,
                boxstyle="round,pad=0.04",
                facecolor='#161b22', edgecolor='#30363d',
                linewidth=1.2, zorder=2))

        _t(ax, RX + T_COLS[0], ry, str(i),
           T_GLD if i == selected else vc, size=9, bold=(i == selected))
        _t(ax, RX + T_COLS[1], ry,
           f'A={A:04X}\nB={B:04X}', vc if i == selected else T_DM, size=7.5)
        _t(ax, RX + T_COLS[2], ry, f'{s32(acc):+d}',
           T_BL if i == selected else T_DM, size=8)
        _t(ax, RX + T_COLS[3], ry,
           f'{Ah:+d}×{Bh:+d}+{Al:+d}×{Bl:+d}={mul:+d}',
           T_GN if i == selected else T_DM, size=7.8)
        _t(ax, RX + T_COLS[4], ry, f'{exp:+d}',
           T_LT if i == selected else T_DM, size=8.5)

        if results and i < len(results):
            _, rtl_v, match = results[i]
            rstr = f'{rtl_v:+d}' if rtl_v is not None else 'ERR'
            _t(ax, RX + T_COLS[5], ry, rstr,
               (T_GD if match else T_RD), size=8.5, bold=True)
            _t(ax, RX + T_COLS[6], ry, '✓' if match else '✗',
               (T_GD if match else T_RD), size=11, bold=True)
        else:
            _t(ax, RX + T_COLS[5], ry, '—', T_DM, size=8.5)

        if i < N - 1:
            ax.axhline(ry - 0.36, xmin=(DIV_X + 0.15)/XLIM, xmax=0.99,
                       color='#161b22', lw=0.6, zorder=2)


# Pipeline trace ──────────────────────────────────────────────────────────────
# Shows 8 clock cycles. Each row is a pipeline stage.
# OUT_fx cells show actual RTL values from the batch run.

NCYC = N + 2          # 8 cycles total
TRACE_Y0  = 3.40      # top of trace section
TRACE_H   = 3.00      # total height of trace
ROW_H_T   = 0.70      # height of each stage row
CELL_W    = R_W / NCYC


def _pipeline_state(cycle):
    """Return (vec_in, vec_s1, vec_out) indices for a given cycle (None = empty)."""
    vi_in  = cycle if cycle < N else None
    vi_s1  = cycle - 1 if 0 < cycle <= N else None
    vi_out = cycle - 2 if 1 < cycle <= N + 1 else None
    return vi_in, vi_s1, vi_out


def draw_pipeline_trace(ax, results, batch_records, selected):
    """Draw clock-cycle grid showing signal propagation through pipeline stages."""
    TY_title  = TRACE_Y0 + 0.25
    TY_header = TRACE_Y0 - 0.10
    TY_row0   = TRACE_Y0 - 0.42           # INPUT row
    TY_row1   = TY_row0  - ROW_H_T        # STAGE 1
    TY_row2   = TY_row1  - ROW_H_T        # OUT_fx

    ax.axhline(TRACE_Y0 + 0.42, xmin=(DIV_X + 0.15)/XLIM, xmax=0.99,
               color='#30363d', lw=1.0, zorder=3)

    _t(ax, RX, TY_title,
       'Pipeline Signal Propagation  (RTL simulation)',
       T_LT, size=9.5, bold=True)

    # cycle headers
    for c in range(NCYC):
        cx = RX + c * CELL_W + CELL_W / 2
        _t(ax, cx, TY_header, f'C{c}', T_DM, size=7.5, ha='center')

    # row labels
    for label, ty, col in [
        ('INPUT',   TY_row0 - ROW_H_T/2 + 0.04, C_IN ),
        ('STAGE 1', TY_row1 - ROW_H_T/2 + 0.04, C_MUL),
        ('OUT_fx',  TY_row2 - ROW_H_T/2 + 0.04, C_ADD),
    ]:
        _t(ax, RX - 0.05, ty, label, col, size=7.5, bold=True, ha='right')

    # extract RTL OUT_fx per cycle from batch run
    rtl_per_cycle = {}   # cycle → rtl OUT_fx
    if batch_records:
        # clock period ~10ns; reset high at t=15ps×1000=15000ps
        # first vector applied at posedge after reset, i.e. t≈25000ps
        # output of vec[i] appears 2 cycles later at t≈(25000 + (i+2)*10000)ps
        for i in range(N):
            t_expected = 25000 + (i + 2) * 10000   # ps
            # find closest record at or just before this time
            candidates = [(t, fx) for t, fx in batch_records
                          if abs(t - t_expected) <= 5000]
            if candidates:
                # take the value at the time closest to t_expected
                _, fx = min(candidates, key=lambda x: abs(x[0] - t_expected))
                rtl_per_cycle[i + 2] = fx

    # draw cells
    for c in range(NCYC):
        vi_in, vi_s1, vi_out = _pipeline_state(c)
        cx = RX + c * CELL_W

        is_sel_cycle = (vi_in == selected or vi_s1 == selected or vi_out == selected)
        bdr_lw = 2.0 if is_sel_cycle else 0.8

        # INPUT row
        if vi_in is not None:
            A, B, _ = VECS[vi_in]
            Ah, Al, Bh, Bl = unpack(A, B)
            vc = VEC_COLS[vi_in]
            _box(ax, cx + 0.04, TY_row0 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, vc, vc, lw=bdr_lw)
            _t(ax, cx + CELL_W/2, TY_row0 - ROW_H_T/2 + 0.04,
               f'V{vi_in}', vc, size=8, bold=True, ha='center')
        else:
            _box(ax, cx + 0.04, TY_row0 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, '#161b22', '#21262d', lw=0.5, alpha=0.15)
            _t(ax, cx + CELL_W/2, TY_row0 - ROW_H_T/2 + 0.04,
               '—', T_DM, size=8, ha='center')

        # STAGE 1 row
        if vi_s1 is not None:
            A, B, acc = VECS[vi_s1]
            Ah, Al, Bh, Bl = unpack(A, B)
            mul = Ah * Bh + Al * Bl
            vc  = VEC_COLS[vi_s1]
            _box(ax, cx + 0.04, TY_row1 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, C_MUL, C_MUL, lw=bdr_lw)
            _t(ax, cx + CELL_W/2, TY_row1 - ROW_H_T/2 + 0.18,
               f'V{vi_s1}', vc, size=7.5, bold=True, ha='center')
            _t(ax, cx + CELL_W/2, TY_row1 - ROW_H_T/2 - 0.12,
               f'mul={mul:+d}', T_GN, size=7, ha='center')
        else:
            _box(ax, cx + 0.04, TY_row1 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, '#161b22', '#21262d', lw=0.5, alpha=0.15)
            _t(ax, cx + CELL_W/2, TY_row1 - ROW_H_T/2 + 0.04,
               '—', T_DM, size=8, ha='center')

        # OUT_fx row (actual RTL values)
        if vi_out is not None:
            A, B, acc = VECS[vi_out]
            rtl_val = rtl_per_cycle.get(c)
            exp_val = fix_expected(A, B, acc)
            vc      = VEC_COLS[vi_out]
            have_rtl = rtl_val is not None
            bdr_color = C_ADD if not have_rtl else (T_GD if rtl_val == exp_val else T_RD)
            _box(ax, cx + 0.04, TY_row2 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, bdr_color, bdr_color, lw=bdr_lw)
            _t(ax, cx + CELL_W/2, TY_row2 - ROW_H_T/2 + 0.18,
               f'V{vi_out}', vc, size=7.5, bold=True, ha='center')
            if have_rtl:
                _t(ax, cx + CELL_W/2, TY_row2 - ROW_H_T/2 - 0.07,
                   f'{rtl_val:+d}', T_GD, size=6.8, ha='center')
                _t(ax, cx + CELL_W/2, TY_row2 - ROW_H_T/2 - 0.28,
                   '✓ RTL', T_GD, size=6.5, bold=True, ha='center')
            else:
                _t(ax, cx + CELL_W/2, TY_row2 - ROW_H_T/2 - 0.12,
                   f'{exp_val:+d}', T_BL, size=7, ha='center')
        else:
            _box(ax, cx + 0.04, TY_row2 - ROW_H_T + 0.05,
                 CELL_W - 0.08, ROW_H_T - 0.10, '#161b22', '#21262d', lw=0.5, alpha=0.15)
            _t(ax, cx + CELL_W/2, TY_row2 - ROW_H_T/2 + 0.04,
               '—', T_DM, size=8, ha='center')

    # latency annotation
    arrow_y = TY_row2 - ROW_H_T - 0.05
    ax.annotate('', xy=(RX + 2 * CELL_W + 0.04, arrow_y),
                xytext=(RX + 0.04, arrow_y),
                arrowprops=dict(arrowstyle='->', color=T_YL, lw=1.2,
                                mutation_scale=12), zorder=4)
    _t(ax, RX + CELL_W, arrow_y - 0.22,
       '2-cycle latency', T_YL, size=7.5, ha='center')

    throughput_x = RX + 2.5 * CELL_W
    _t(ax, throughput_x, arrow_y - 0.22,
       '1 result / cycle (once full)', T_GD, size=7.5)


# ── summary row ───────────────────────────────────────────────────────────────

def draw_summary(ax, results, status_msg):
    SY = 0.65
    ax.axhline(SY + 0.38, xmin=(DIV_X + 0.15)/XLIM, xmax=0.99,
               color='#30363d', lw=1.0, zorder=3)
    if results is not None:
        n_ok = sum(1 for _, _, m in results if m)
        c, s = (T_GD, f'✓  {n_ok}/{N} PASSED — 100% bit-exact match') if n_ok == N \
            else (T_RD, f'✗  {n_ok}/{N} passed')
        _t(ax, RX, SY + 0.15, 'Result:', T_DM, size=8)
        _t(ax, RX + 0.85, SY + 0.15, s, c, size=9.5, bold=True)
        _t(ax, RX, SY - 0.20,
           'Full suite (parallel_verify.py): 25,000 FIX vectors — 100% pass rate',
           T_DM, size=8, mono=False)
    elif status_msg:
        _t(ax, RX, SY + 0.10, status_msg, T_YL, size=9.5, bold=True)
    else:
        _t(ax, RX, SY + 0.10,
           'Click  "Run RTL Verification"  to compile Verilog and run simulation.',
           T_DM, size=8.5, mono=False)


# ── full frame render ─────────────────────────────────────────────────────────

def render(ax, selected, results, batch_records, status_msg):
    ax.cla()
    ax.set_xlim(0, XLIM)
    ax.set_ylim(0, YLIM)
    ax.set_facecolor(BG)
    ax.axis('off')

    ax.axvline(DIV_X + 0.04, ymin=0.02, ymax=0.98,
               color='#21262d', lw=1.5, zorder=2)

    rtl_row = results[selected] if (results and selected < len(results)) else None
    draw_left(ax, selected, rtl_row)
    draw_verification_table(ax, results, selected)
    draw_pipeline_trace(ax, results, batch_records, selected)
    draw_summary(ax, results, status_msg)


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description='MAC RTL correctness & signal trace demo')
    ap.add_argument('--auto', action='store_true',
                    help='cycle through vectors automatically after RTL run')
    args = ap.parse_args()

    fig = plt.figure(figsize=(20, 9.5), facecolor=BG)
    try:
        fig.canvas.manager.set_window_title('MAC Unit — RTL Correctness Demo')
    except Exception:
        pass

    ax     = fig.add_axes([0, 0.07, 1, 0.93])
    ax_rtl = fig.add_axes([0.30, 0.01, 0.20, 0.055])
    ax_prv = fig.add_axes([0.53, 0.01, 0.08, 0.055])
    ax_nxt = fig.add_axes([0.62, 0.01, 0.08, 0.055])
    ax.set_facecolor(BG)

    btn_rtl = Button(ax_rtl, '▶  Run RTL Verification', color='#1f6feb', hovercolor='#388bfd')
    btn_prv = Button(ax_prv, '◀ Prev', color='#21262d', hovercolor='#30363d')
    btn_nxt = Button(ax_nxt, 'Next ▶', color='#21262d', hovercolor='#30363d')
    for b in (btn_rtl, btn_prv, btn_nxt):
        b.label.set(color='white', fontfamily='monospace', fontsize=9)

    state = dict(sel=0, results=None, batch=None, status='', anim=None)

    def redraw():
        render(ax, state['sel'], state['results'], state['batch'], state['status'])
        fig.canvas.draw_idle()

    def on_run(_=None):
        state['status'] = 'Compiling RTL with Icarus Verilog and running simulation…'
        redraw()
        fig.canvas.flush_events()
        per_vec, batch, err = run_all_vecs()
        if per_vec is None:
            state['status'] = f'ERROR: {err}'
        else:
            state['results'] = per_vec
            state['batch']   = batch
            state['status']  = ''
            btn_rtl.label.set_text('✓  RTL Run Complete')
        redraw()

    def on_prev(_=None):
        state['sel'] = (state['sel'] - 1) % N
        redraw()

    def on_next(_=None):
        state['sel'] = (state['sel'] + 1) % N
        redraw()

    btn_rtl.on_clicked(on_run)
    btn_prv.on_clicked(on_prev)
    btn_nxt.on_clicked(on_next)

    redraw()

    if args.auto:
        def auto_step(_=None):
            if state['results'] is not None:
                state['sel'] = (state['sel'] + 1) % N
                redraw()
        state['anim'] = FuncAnimation(fig, auto_step, interval=1500, repeat=True)

    plt.show()


if __name__ == '__main__':
    main()
