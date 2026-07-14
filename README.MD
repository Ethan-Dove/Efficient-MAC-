# ELEC-5160 Design Project: Efficient MAC Unit

This project implements an **Efficient Fixed/Floating-Point Merged Mixed-Precision Multiply-Accumulate (MAC) Unit for Deep Learning Processors**, based on a full RTL-to-GDSII ASIC design flow. Based on Zhang et al., IEEE ISCAS 2018.

---

## 1. Project Overview

**Key Features:**
- Dual-mode operation: FP16×FP16→FP32 (training) and 2×INT8→INT32 (inference)
- Karatsuba-merged multiplier — only 4.6% area overhead vs standalone FLP MAC
- Fully pipelined: FIX result in 2 cycles, FLP result in 3 cycles
- RTL in **plain Verilog-2001** (`wire`/`reg`, `always @(*)`, `always @(posedge clk)`)
- Verified with a parallel Python/Icarus Verilog bit-exact co-simulation framework

---

## 2. Directory Structure

```
Efficient_MAC/
├── rtl/          16 RTL modules in plain Verilog-2001 (.v)
├── bhav_sim/     Behavioral simulation: testbench, test vectors, verification scripts
├── visualisation/ Architecture block diagram (architecture.md, Mermaid)
├── syn/          Synopsys Design Compiler synthesis
├── net/          Gate-level netlist + SDF
├── rpt/          Timing, area, power reports
├── par/          Cadence Innovus place & route
├── gate_sim/     Post-synthesis simulation
└── par_sim/      Post-layout simulation
```

---

## 3. RTL

RTL is written in **plain Verilog-2001** (`.v` extension). The 16 modules are structurally partitioned to match the paper's block diagram:

| Module | Stage | Role |
|---|---|---|
| `mac_top.v` | Top | 3-stage pipelined top-level; pipeline registers between stages |
| `input_processing.v` | 1 | Unpacks inputs into exponent, mantissa, and sign fields |
| `invert_control.v` | 1 | Computes `eop_fp` (effective subtract) and `sign_fp` |
| `invert_addend.v` | 1 | Ones-complement inversion of accumulator mantissa when `eop_fp=1` |
| `align_control.v` | 1 | Exponent difference → `shift_amt`, `exp_align` |
| `align_shifter.v` | 1 | Right-shifts 58-bit (possibly inverted) accumulator field; generates sticky bit |
| `merged_multiplier.v` | 1 | Karatsuba core: 3 Booth 8×8 multipliers + CLA + CSA; shared FLP/FIX |
| `carry_propagate_adder.v` | 2 | Resolves lower 32 bits of 58-bit sum; produces `cout` |
| `incrementer.v` | 2 | Pre-increments upper 27 bits for end-around carry path |
| `cin_gen.v` | 2 | `cin = eop_fp` (ones-complement carry-in for subtraction) |
| `complementer.v` | 2 | Detects `is_neg`; 2's-complement negates 58-bit sum when true |
| `lza_lzc.v` | 2 | LZA: P/G/Z → F-string → predicted LZC; runs parallel with CPA |
| `normalization_shifter.v` | 3 | Exact ascending-loop LZC on post-complement sum; left-shifts to normalize |
| `rounder.v` | 3 | IEEE 754 round-to-nearest-even (Guard/Round/Sticky) |
| `barrel_shifter.v` | — | Generic parametric barrel shifter (utility) |

---

## 4. Verification

### Parallel co-simulation (primary)

```sh
python3 scripts/parallel_verify.py            # full run, 100k vectors
python3 scripts/parallel_verify.py --recompile  # force RTL recompile first
```

Runs 100,000 vectors across 12 directed-random batch categories using up to 24 parallel `vvp` workers. See [`Efficient_MAC/bhav_sim/VERIFICATION_GUIDE.md`](Efficient_MAC/bhav_sim/VERIFICATION_GUIDE.md) for full details.

**Current result (2026-05-19):**

| Path | Vectors | Pass | Rate |
|---|---|---|---|
| FIX (INT8×INT8) | 25,000 | 25,000 | **100%** |
| FLP (FP16×FP16) | 75,000 | 39,691 | 52.9% |
| **Total** | **100,000** | **64,691** | **64.7%** |

FLP failures are due to a known Karatsuba middle-term 8-bit truncation defect in `merged_multiplier.v` (see Section 10 of the report).

---

## 5. Full ASIC Flow (University Server)

All steps below require SSH access to the HKUST ECE server.

```bash
source /usr/eelocal/synopsys/vcs-vq2020.03-sp1-1/.cshrc   # VCS
source /usr/eelocal/synopsys/syn-vp2019.03-sp5/.cshrc      # Design Compiler
source /usr/eelocal/cadence/innovus211/.cshrc               # Innovus
```

| Step | Directory | Command |
|---|---|---|
| Behavioral verification | `scripts/` | `python3 parallel_verify.py` |
| Synthesis | `syn/` | `./run` |
| Post-synth sim | `gate_sim/` | `./run` |
| Place & Route | `par/` | `./run` (Innovus) |
| Post-layout sim | `par_sim/` | `./run` |

---

## 6. Report

The report is authored in **Quarto Markdown** (`Report.qmd`) and compiles to PDF.

```bash
quarto render Report.qmd --to pdf
```

---

## 7. References

- Zhang, H., Lee, H. J., & Ko, S.-B. (2018). *Efficient Fixed/Floating-Point Merged Mixed-Precision Multiply-Accumulate Unit for Deep Learning Processors.* IEEE ISCAS 2018.
