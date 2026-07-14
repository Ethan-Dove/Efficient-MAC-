# Behavioral Simulation & Verification Guide

This guide documents the verification strategy for the fixed/floating-point merged MAC unit (`mac_top`) within `Efficient_MAC/bhav_sim/`.

---

## Verification Strategy

The MAC supports two modes — FIX (INT8×INT8→INT32) and FLP (FP16×FP16→FP32) — each with distinct corner cases. Pure uniform-random stimulus misses most interesting conditions (exponent cancellation, ones-complement borrow, end-around carry). The framework therefore uses **directed-random batches** fed through a co-simulation loop:

1. **Python vector generation** — `scripts/parallel_verify.py` generates mathematically targeted test vectors for 12 named batch categories covering normal add, subtraction (far/close path), cancellation, and boundary conditions.
2. **Data-driven testbench** — `tb_mac_top.v` reads vectors from a text file via `$fscanf`, with `+tv=<path>` and `+no_vcd` plusargs for batch control.
3. **Exact software reference** — `fp_ref()` and `fix_ref()` inside `parallel_verify.py` mirror the RTL pipeline in Python big-integer arithmetic and compare output bit-for-bit.

---

## Key Files

| File | Purpose |
|---|---|
| `scripts/parallel_verify.py` | Primary verification driver: generates vectors, compiles RTL, runs 12 parallel batches, compares results |
| `tb_mac_top.v` | Data-driven Verilog testbench; reads `tv_inputs.txt` via `$fscanf`; supports `+tv=`, `+no_vcd` plusargs |
| `tv_inputs.txt` | Most-recently-generated test vectors (format: `<float_bit> <A_hex> <B_hex> <acc_hex>`) |
| `logs/` | Timestamped per-run logs (pass/fail breakdown, first failures) |
| `VERIFICATION_GUIDE.md` | This file |

---

## Running the Verification Suite

### Full parallel run (recommended)

```sh
python3 scripts/parallel_verify.py
```

Runs 100,000 vectors across 12 batch categories using up to 24 parallel `vvp` workers. Prints per-batch pass/fail and a final total.

### Force RTL recompile then run

```sh
python3 scripts/parallel_verify.py --recompile
```

### Options

| Flag | Default | Description |
|---|---|---|
| `--recompile` | off | Force `iverilog` recompile before running |
| `--jobs N` | `min(24, cpu_count)` | Parallel `vvp` worker count |
| `--seed S` | `42` | Master PRNG seed for all batches |

### Current observed result (2026-05-18, float_ref primary criterion)

```
============================================================
TOTAL  pass=64691  fail=35309  skip=0
============================================================
FLP failures detected — see bug report below.
```

Log: `Efficient_MAC/bhav_sim/logs/verify_20260518_203117.log`

### Expected result after Karatsuba fix

```
============================================================
TOTAL  pass=100000  fail=0  skip=0
============================================================
All comparisons passed (exact bit match against float64 reference).
```

---

## Test Batch Categories

| Batch | Vectors | Description |
|---|---|---|
| `fix_random_0,1` | 12 500 each | FIX mode: random INT8 inputs and INT32 accumulators, 15 % zero-acc injection |
| `flp_add_0,1` | 9 000 each | FLP add: both product and accumulator same sign |
| `flp_sub_low_0,1,2` | 9 000 each | FLP subtraction — close path (small exponent difference, result small) |
| `flp_sub_high_0` | 9 000 | FLP subtraction — far path (large exponent difference) |
| `flp_cancel_0,1` | 7 000 each | FLP catastrophic cancellation (nearly equal magnitudes, opposite signs) |
| `flp_boundary_0,1` | 3 500 each | FLP boundary: exponent near 0 or 254, denormal-adjacent inputs |

---

## Software Reference Models

Two references exist for FLP vectors. `float_ref()` is the **primary pass criterion**. `fp_ref()` is a diagnostic-only pipeline mirror used to annotate failure messages.

### `fix_ref(A16, B16, acc32)` — FIX exact reference

Splits `A16`/`B16` into signed 8-bit halves (`Ah`, `Al`, `Bh`, `Bl`), computes `Ah×Bh + Al×Bl + acc` in Python arbitrary-precision integers, and masks to 32 bits. Pure integer — always exact. Matches `OUT_fx` with 2-cycle pipeline latency.

### `fp_ref(A16, B16, acc32)` — FLP pipeline mirror

Mirrors every stage of the RTL FLP pipeline in Python big-integer arithmetic. Catches any deviation between RTL behaviour and the intended architecture, even if the final numerical result happens to round to the correct value.

1. **Decode** — unpack FP16 A, B and FP32 acc into `(sign, exp, mantissa)` with hidden bit restored.
2. **Product mantissa** — `mp = ma × mb`, up to 22-bit integer; no rounding here.
3. **Effective operation** — `eop_fp = sp ^ sc`; when `1` the accumulator and product have opposite signs (subtraction path).
4. **Alignment** — `shift_amt = ea + eb + 134 − ec` places the accumulator MSB at the correct position in the 58-bit working field. Clamped to `[0, 57]`; `zero_acc` set if `> 57`.
5. **Ones-complement inversion** — when `eop_fp=1`, the 24-bit accumulator mantissa is bitwise inverted and the lower 34 bits of the 58-bit field are filled with 1s (ones-complement sign extension, not two's-complement). The `cin = eop_fp` carry-in at the adder completes the two's-complement.
6. **58-bit addition** — product (lower 22 bits) + aligned accumulator + carry-in.
7. **End-around carry / negation** — `is_neg = eop_fp & ~end_around_carry`: no carry out means the subtraction result is negative; the 58-bit sum is then two's-complement negated.
8. **Exact LZC** — ascending-loop leading-zero count on the 58-bit sum; left-shifts to normalize.
9. **IEEE RNE rounding** — extracts Guard (`bit 33`), Round (`bit 32`), Sticky (OR of bits 31:0); rounds up when `G & (R | S | LSB)`.
10. **Sign** — `sign_out = sp ^ is_neg`.

Returns FP32 bit pattern, or `None` for NaN/Inf/denormal (skipped).

### `float_ref(A16, B16, acc32)` — float64 sanity reference

Computes `float(fp16(A)) * float(fp16(B)) + float(fp32(acc))` using Python's native float64 arithmetic, then rounds the result back to FP32.

This is the **correct IEEE 754 answer** and is trivially simple to audit. It works because:
- FP16 mantissa × FP16 mantissa ≤ 22 bits — fits exactly in float64's 53-bit mantissa with zero rounding error
- Adding FP32 acc (24-bit mantissa) still fits — the full exact mathematical result is representable in float64
- Rounding float64 → float32 applies IEEE RNE, giving the correctly-rounded result

**What it catches that `fp_ref()` misses:** if `fp_ref()` itself has a pipeline-mirroring bug, it could agree with a wrong RTL output. `float_ref()` provides an independent correct answer. A `sanity_fail` (RTL matches `fp_ref()` but differs from `float_ref()` by >1 ULP) signals a bug in the reference model, not the RTL.

**What `fp_ref()` catches that `float_ref()` misses:** architectural deviations — wrong alignment, wrong carry logic, wrong LZC — that happen to cancel out and still produce the correct final value.

### ULP distance

Every FLP failure reports `err=N ULP` — the ULP distance between the RTL output and `float_ref()`. This distinguishes:
- `err=1–2 ULP` — likely a rounding edge case (LZC off by 1, sticky bit lost)
- `err=100+ ULP` — significant mantissa error (e.g. Karatsuba middle-term overflow)

---

## Vector Generator Strategy

Each generator uses a seeded `random.Random` (incremented per batch) so all runs are fully reproducible. The generators are **directed-random** — they don't just throw uniform noise at the DUT; each one biases the operand distribution toward a specific RTL condition.

| Generator | Technique |
|---|---|
| `gen_fix` | Uniform random 16-bit A, B, acc. 15 % of vectors force `acc=0` to exercise the zero-accumulator path in `align_shifter`. |
| `gen_flp_add` | Sets `sc = sp` (accumulator sign = product sign) so `eop_fp=0`. Exercises the pure addition path with no ones-complement inversion. |
| `gen_flp_sub_low` | Forces `eop_fp=1` and back-solves `ec = ea+eb+134−target` to constrain `shift_amt ∈ [0,35]`. Product and accumulator are close in magnitude — stresses near-cancellation, close-path rounding, and sticky-bit generation. |
| `gen_flp_sub_high` | Same as above but `shift_amt ∈ [36,57]`. Accumulator is much smaller than product — stresses the far path where the accumulator shifts almost entirely out of the 58-bit window. |
| `gen_flp_cancel` | Sets `ec = ea+eb+97` exactly so the accumulator exponent matches the product. Result is near-zero with many leading zeros — stresses LZC, normalization shift, and RNE rounding on a tiny result. |
| `gen_flp_boundary` | Seeds two deterministic exact-value vectors (`1.0×1.0+1.0=2.0`, `1.5×1.0+0.5=2.0`) to anchor the RNE path, then fills with random near-boundary vectors. |

The `_make_flp_vec()` helper retries up to 200 times per vector to ensure the back-solved accumulator exponent stays within the valid FP32 range `[1, 254]`. Vectors that would produce NaN, Inf, or denormal results are filtered out before they reach the DUT.

---

## Parallel Execution Model

```
main process
│
├─ compile_rtl()  →  iverilog → /tmp/mac_par_sim  (shared read-only binary)
│
└─ ProcessPoolExecutor (up to 24 workers)
       │
       ├─ run_batch("fix_random_0")  →  write temp tv file → vvp → stdout
       ├─ run_batch("fix_random_1")  →  write temp tv file → vvp → stdout
       ├─ run_batch("flp_add_0")     →  write temp tv file → vvp → stdout
       ├─ ...12 batches total, all running simultaneously...
       │
       └─ as_completed() → verify() → accumulate pass/fail counts
```

Each worker writes its vector set to a unique temp file (`/tmp/mac_tv_{name}_*.txt`), invokes `vvp` with `+tv=<path> +no_vcd` (suppressing VCD for speed), captures stdout, then deletes the temp file. Because all workers read the same compiled binary and write to independent temp files there are no race conditions — the only shared state is the read-only `SIM_BIN`.

All output is simultaneously written to stdout and a timestamped log file in `Efficient_MAC/bhav_sim/logs/` via the `_Tee` class, which replaces `sys.stdout` for the duration of the run.

---

## Timestamp-Based Verifier

The testbench emits one `$monitor` line per clock edge:

```
Time=35000 | float=0 | A=ab12 B=cd34 acc=00000000 | OUT_fx=0000cafe OUT_fp=00000000
```

The verifier does **not** match records by vector index. It matches by timestamp, accounting for the MAC pipeline latency:

```
Input N applied at:    t = 15 000 + N × 10 000 ps
FIX output valid at:   t + 20 000 ps   (2-cycle latency)
FLP output valid at:   t + 30 000 ps   (3-cycle latency)
```

For each vector it looks up `records[out_time]` in the parsed output and compares `OUT_fx` against `fix_ref()` and `OUT_fp` against `float_ref()` for an **exact bit-for-bit match** — no tolerance or ULP window. A mismatch at any bit position is counted as a failure. `fp_ref()` is computed alongside `float_ref()` for diagnostic annotation in failure messages only.

Vectors whose `$monitor` record is missing (simulation ended before output was valid, or testbench timing skew) are counted as `skip` rather than `fail`.

---

## Manual Single-Batch Flow

If you need to inspect a simulation waveform:

**Step 1 — Compile**
```sh
iverilog -g2001 \
    -o Efficient_MAC/bhav_sim/tb_mac_top_sim \
    Efficient_MAC/bhav_sim/tb_mac_top.v \
    Efficient_MAC/rtl/*.v
```
> All files are plain Verilog-2001.

**Step 2 — Run (with VCD)**
```sh
.pixi/envs/default/bin/vvp Efficient_MAC/bhav_sim/tb_mac_top_sim \
    +tv=Efficient_MAC/bhav_sim/tv_inputs.txt \
    > Efficient_MAC/bhav_sim/mac_top_out.txt
```

**Step 3 — View waveforms**
```sh
pixi run wave    # opens GTKWave on dump_mac_top.vcd
```

**Step 4 — Suppress VCD for batch runs**
```sh
.pixi/envs/default/bin/vvp Efficient_MAC/bhav_sim/tb_mac_top_sim \
    +tv=<path> +no_vcd > output.txt
```

---

## Timing Model

The testbench uses `` `timescale 1ns/1ps `` with a 10 ns clock (5 ns half-period). `$monitor` timestamps are in **picoseconds**.

| Event | Time formula |
|---|---|
| Reset deasserted | t = 15 000 ps |
| Input N applied (0-indexed) | t = 15 000 + N × 10 000 ps |
| `OUT_fx` valid (2-cycle latency) | input time + 20 000 ps |
| `OUT_fp` valid (3-cycle latency) | input time + 30 000 ps |

---

## Architecture Summary & Correspondence to Zhang et al. 2018

### Pipeline stages

| Stage | Cycles | Modules | Output |
|---|---|---|---|
| 1 | 1 | `input_processing`, `invert_control`, `invert_addend`, `align_control`, `align_shifter`, `merged_multiplier` | 32-bit multiplier result + aligned accumulator |
| 2 | 2 | `carry_propagate_adder`, `incrementer`, `cin_gen`, `complementer`, `lza_lzc` | `OUT_fx` (FIX); 58-bit sum ready for Stage 3 |
| 3 | 3 | `normalization_shifter`, `rounder` | `OUT_fp` (FLP) |

### Module-by-module notes

**`merged_multiplier.v`** — Karatsuba 11-bit core replacing the original Zhang et al. implementation. Ports: `float`, `X[10:0]`, `Y[10:0]`, `ext_A[7:0]`, `ext_B[7:0]`, `result[31:0]`. FLP path: decomposes X/Y into 3-bit upper (X1/Y1) and 8-bit lower (X0/Y0) fragments, computes Z0 (3×3 via CSA), Z2 (8×8 via Booth), and Z1 (middle term via CSA tree + CLA), then assembles `{Z0,Z2} + Z1<<8`. FIX path: computes `Ah×Bh` (ext_A×ext_B) + `Al×Bl` (X0×Y0) using the same two Booth multipliers, sign-extends result to 32 bits. Output is a resolved 32-bit value (not a carry-save pair).

**`booth_multiplier_8x8_dual.v`** — Radix-4 Booth multiplier, dual-mode. `float=1`: unsigned. `float=0`: signed two's complement. Outputs carry-save pair `(sum, carry)` — resolved by the CLA adder in `merged_multiplier`.

**`cla_4bit.v` / `cla_16bit.v`** — Hierarchical carry look-ahead adder. `cla_16bit` chains four `cla_4bit` blocks via a look-ahead carry unit. Used to resolve Z1 inside `merged_multiplier`.

**`csa_4to2_16bit.v`** — Standard 16-bit 4:2 carry-save adder. Used in the Z1 CSA tree.

**`csa_4to2_16bit_add2.v`** — 16-bit 4:2 CSA with +2 correction injection. When `float=1`, injects +1 into both shifted carry paths to complete the two's complement of the inverted (Z0+Z2) terms during Z1 calculation.

**`align_control.v`** — Computes `shift_amt = ea + eb + 134 − ec` (places the accumulator MSB at bit `57 − shift_amt` of the 58-bit field). Sets `exp_align = (ea + eb + 134) & 0xFF` and `zero_acc` when `shift_amt > 57`.

**`align_shifter.v`** — Right-shifts the 24-bit (inverted) accumulator mantissa into the 58-bit field; fills upper vacated bits with 1s (sign extension) for subtraction; generates the `stk` (sticky) bit from shifted-out bits.

**`cin_gen.v`** — `cin = eop_fp`. For ones-complement subtraction, carry-in must be 1 whenever `eop_fp = 1` to complete the two's complement. Ports simplified to `{eop_fp, cin}` only.

**`complementer.v`** — Detects `is_neg = eop_fp & ~sum_high[26]` (subtraction with no end-around carry → result is negative). Performs true 2's-complement negation on the 58-bit sum when `is_neg = 1`; otherwise passes through.

**`lza_lzc.v`** — Computes P/G/Z strings from the pre-CPA operands and builds the F-string (F_pos for sum MSB = 0, F_neg for sum MSB = 1). The `count` output (predicted LZC within ±1) runs in parallel with the CPA. `valid` is always 1.

**`normalization_shifter.v`** — Uses an **exact ascending-loop LZC** on `sum_norm_in` for all cases: the LZA F-string formula `P[i]^Z[i+1]` resolves carry structure top-down and mispredicts by 30+ bits on the addition path (when operands occupy low-order bits). Exact LZC on the post-complement sum is correct for both `is_neg=0` (addition) and `is_neg=1` (subtraction with complement), with only a priority-encoder gate delay.

**`rounder.v`** — IEEE 754 RNE. Extracts Guard, Round, Sticky bits; rounds up when `G & (R | S | LSB)`; propagates round carry into exponent.

---

## Known Limitations

- Denormal inputs and outputs are not handled (RTL is optimised for deep-learning workloads where denormals are flushed to zero).
- NaN and Inf inputs are not handled; `fp_ref()` returns `None` and the vector is skipped.
- The LZA `count` output is structurally correct (F-string wired) but not consumed by `normalization_shifter` due to the top-down carry-resolution issue. Future work: fix the F-string formula (use `P[i]^Z[i-1]`) to enable true parallel LZA.

---

## Bug Report — Karatsuba Middle-Term Overflow in `merged_multiplier.v`

**Date discovered:** 2026-05-18  
**Discovered by:** End-to-end parallel verification run (`scripts/parallel_verify.py`)  
**Status:** Open — RTL defect confirmed, fix not yet applied

### Summary

The floating-point Karatsuba middle-term computation in `merged_multiplier.v` truncates a 9-bit intermediate sum to 8 bits before feeding it into the middle multiplier. This silently corrupts the middle partial product for ~3.8% of normal FP16 operand pairs, producing large errors in the final mantissa product and causing the output to be off by factors of 2–30× in affected cases.

### Latest verification result (2026-05-18)

Log: `Efficient_MAC/bhav_sim/logs/verify_20260518_203117.log`  
Pass criterion: exact bit match against `float_ref()` (float64 IEEE 754 reference)

| Suite | Vectors | Pass | Fail | Fail % |
|---|---|---|---|---|
| `fix_random_0,1` | 25,000 | 25,000 | 0 | 0% |
| `flp_add_0,1` | 18,000 | 8,052 | 9,948 | 55.3% |
| `flp_sub_low_0,1,2` | 27,000 | 25,854 | 1,146 | 4.2% |
| `flp_sub_high_0` | 9,000 | 945 | 8,055 | 89.5% |
| `flp_cancel_0,1` | 14,000 | 1,719 | 12,281 | 87.7% |
| `flp_boundary_0,1` | 7,000 | 3,121 | 3,879 | 55.4% |
| **TOTAL** | **100,000** | **64,691** | **35,309** | **35.3%** |

Fixed-point passes with zero failures. All 35,309 FLP failures are traceable to the `sum_X[8]`/`sum_Y[8]` overflow condition in the Karatsuba middle term — confirmed by per-vector analysis of the failing log entries. Large-error failures (hundreds to millions of ULP) are the direct Karatsuba overflow cases; small-ULP failures (1–30 ULP) arise because even a small overflow in `sum_X` or `sum_Y` shifts the middle product into a different rounding region, causing off-by-1-LSB errors in the assembled mantissa.

### Root cause

For an 11-bit FP16 mantissa `X[10:0]`, the Karatsuba decomposition splits it into:
- `X1 = X[10:8]` — 3-bit upper fragment (always ≥ 4 for normal numbers due to hidden bit)
- `X0 = X[7:0]` — 8-bit lower fragment

The middle multiplier should receive the full 9-bit sum `X0 + X1` (max value 262). In the current RTL:

```verilog
wire [8:0] sum_X    = X0 + {5'b0, X1};   // correctly 9-bit
wire [7:0] mid_in_A = float ? sum_X[7:0] : ext_A;  // ← bit [8] dropped here
```

Whenever `X0 + X1 > 255` (i.e. `X0 ≥ 256 − X1`), the carry into bit 8 is silently discarded. The middle Booth multiplier then computes `(sum_X mod 256) × (sum_Y mod 256)` instead of the correct `sum_X × sum_Y`, producing a completely wrong middle term `Z1`. Since `Z1` is shifted left by 8 positions in the final Karatsuba assembly, a corrupted `Z1` causes a large error in the 22-bit mantissa product.

**Overflow condition:** `X0 ≥ 256 − X1`. For normal FP16, `X1 ∈ {4,5,6,7}`, so overflow occurs when `X0 ≥ 249..252`. Over 100,000 random normal FP16 pairs this triggers in **4.2%** of cases.

### Paper errata

The overflow is traceable to a gap in Zhang et al. (ISCAS 2018). The paper describes the sums `(mah + mal)` and `(mbh + mbl)` as inputs to an 8×8 multiplier without specifying that these sums can be 9 bits wide. Any implementation that feeds the sums into an 8-bit multiplier input without widening will silently produce incorrect results.

### Representative failing vectors

| Label | A | B | Expected (float) | Got (float) | sum_Y (true) | Overflow |
|---|---|---|---|---|---|---|
| `flp_add_0 idx=32` | `455d` | `cbff` | −136.2 | −452.2 | 262 | Yes |
| `flp_add_0 idx=43` | `a2f2` | `44fc` | −0.142 | −0.158 | 256 | Yes |
| `flp_add_1 idx=0` | `be78` | `a0fc` | 0.0165 | 0.0800 | 256 | Yes |
| `flp_sub_high_0 idx=11` | `58e6` | `d4fd` | 2843.8 | −8420.2 | 257 | Yes |
| `flp_cancel_1 idx=9` | `44fc` | `210d` | 0.0159 | 0.4807 | 256 | Yes |

### Fix (not yet applied)

Widen `mid_in_A` and `mid_in_B` to 9 bits and replace the 8×8 middle Booth multiplier with a 9×9 (or 9×8 + correction) instance. Alternatively, the overflow carry bit can be handled as a separate additive correction term fed into the CSA tree, preserving the 8×8 multiplier.

After the fix is applied, re-run `python3 scripts/parallel_verify.py --recompile` and confirm `fail=0` across all FLP suites.
