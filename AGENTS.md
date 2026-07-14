# AGENTS.md — ELEC-5160 Efficient MAC Unit

## Project Overview

This repo implements an **Efficient Fixed/Floating-Point Merged Mixed-Precision MAC Unit** for deep learning processors, based on a full-custom ASIC design flow targeting **TSMC 180 nm** (tcb018g3d3 standard cells, Rev 280a).

Supported precisions: INT8, INT16, FP16, FP32. The merged architecture minimises area and power by sharing hardware across precision modes.

Top-level module: `efficient_mac` (Verilog).

---

## Environment Detection — Local vs. Synopsys VM

**Before running any simulation or flow step, determine which environment you are in:**

| Signal | Environment |
|--------|-------------|
| `/usr/eelocal/synopsys/` exists | Synopsys VM — use VCS / DC / Innovus |
| `/usr/eelocal/synopsys/` absent | Local machine — use pixi (iverilog / GTKWave) |

You can check with:
```sh
test -d /usr/eelocal/synopsys && echo "VM" || echo "LOCAL"
```

**Never invoke `vcs`, `dc_shell`, or `innovus` on a local machine — they do not exist there.**
**Never invoke `pixi run sim` on the Synopsys VM for final sign-off — it only runs RTL-level iverilog.**

---

## Local Setup (iverilog + GTKWave via pixi)

Tools are managed through [pixi](https://pixi.sh) and declared in `pixi.toml`.

Recommended VS Code extensions for local Verilog development:

| Extension | ID |
|-----------|----|
| Verilog-HDL/SystemVerilog | `mshr-h.veriloghdl` |
| TerosHDL | `teros-technology.teroshdl` |

Install pixi once, then install the toolchain:
```sh
curl -fsSL https://pixi.sh/install.sh | bash
pixi install   # pulls iverilog + gtkwave from conda-forge
```

### Local simulation commands

```sh
pixi run sim    # compile RTL with iverilog + run with vvp
pixi run wave   # open Efficient_MAC/bhav_sim/dump.vcd in GTKWave
```

**Testbench requirement for local use:** `rtl/stim.v` must emit a VCD dump (iverilog cannot produce `.vpd`):
```verilog
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, stim);
end
```

Equivalent manual commands (no pixi):
```sh
iverilog -g2001 -o simv Efficient_MAC/rtl/efficient_mac.v Efficient_MAC/rtl/stim.v
vvp simv
gtkwave dump.vcd
```

---

## Synopsys VM Setup

Source all required EDA tools before running any flow step:

```csh
source /usr/eelocal/synopsys/vcs-vq2020.03-sp1-1/.cshrc   # VCS simulator
source /usr/eelocal/synopsys/syn-vp2019.03-sp5/.cshrc      # Design Compiler
source /usr/eelocal/cadence/ic617hf/.cshrc                  # Cadence IC
source /usr/eelocal/cadence/innovus211/.cshrc               # Innovus P&R
```

The project-level `.cshrc_user` at the repo root sources all of the above.

---

## Directory Structure

```
Efficient_MAC/
├── rtl/          # Verilog RTL source (efficient_mac.v, stim.v)
├── bhav_sim/     # Behavioral (RTL) simulation
├── syn/          # Logic synthesis (Design Compiler)
├── ddc/          # Synthesised design databases (output)
├── net/          # Gate-level netlists + SDF/SDC (output)
├── rpt/          # Timing / area / power reports (output)
├── gate_sim/     # Pre-layout gate-level simulation
├── par/          # Place & Route (Innovus)
├── par_sim/      # Post-layout simulation
```

Technology library path: `/dfs/app/tsmc_icdc/tsmc180/tsmc180_MS_RF_G/SC/tcb018g3d3/Rev280a/`

---

## ASIC Design Flow

### Step 1 — Behavioral Simulation

**Primary verification (local, recommended):**
```sh
python3 scripts/parallel_verify.py --recompile   # full 100k-vector run, forced recompile
python3 scripts/parallel_verify.py               # use cached binary if RTL unchanged
```

Options:

| Flag | Default | Description |
|---|---|---|
| `--recompile` | off | Force `iverilog` recompile before running |
| `--jobs N` | `min(24, cpu_count)` | Parallel `vvp` worker count |
| `--seed S` | `42` | Master PRNG seed |

**Manual single-batch waveform inspection (local):**
```sh
.pixi/envs/default/bin/iverilog -g2001 \
    -o Efficient_MAC/bhav_sim/tb_mac_top_sim \
    Efficient_MAC/bhav_sim/tb_mac_top.v \
    Efficient_MAC/rtl/*.v

.pixi/envs/default/bin/vvp Efficient_MAC/bhav_sim/tb_mac_top_sim \
    +tv=Efficient_MAC/bhav_sim/tv_inputs.txt \
    > Efficient_MAC/bhav_sim/mac_top_out.txt

pixi run wave   # open dump_mac_top.vcd in GTKWave
```

**Synopsys VM (VCS):**
```sh
cd Efficient_MAC/bhav_sim
./run          # compiles RTL with VCS
./run1         # runs simulation (40 000 000 time units)
./run2         # launches DVE waveform viewer
./clean        # removes compiled artefacts
```

VCS flags: `-full64 -timescale=1ns/1ps -debug_all -top stim`

### Step 2 — Logic Synthesis (Design Compiler)

```sh
cd Efficient_MAC/syn
./run          # runs dc_shell -f run.tcl | tee run.log
./clean        # removes reports/results/work
```

Key constraints in `run.tcl`:
- Clock: 4 ns period (250 MHz target)
- Input/output delay: 0.2 ns
- Wire-load model: `TSMC128K_Conservative`
- Outputs written to `../net/` (netlist + SDF + SDC) and `../rpt/` (timing, area, power)

### Step 3 — Gate-Level Simulation

```sh
cd Efficient_MAC/gate_sim
./run          # compiles synthesised netlist + SDF back-annotation
./run1         # runs simulation
./run2         # launches DVE
```

Uses: `../net/efficient_mac_Syn.v` + SDF `../net/efficient_mac.sdf`
Cell library: `tcb018g3d3.v` (TSMC 180 nm Verilog models)

### Step 4 — Place & Route (Innovus)

```sh
cd Efficient_MAC/par
innovus -64 -init innovus.cmd
```

Key settings in `innovus.cmd`:
- Floorplan: aspect ratio 0.8, utilisation 0.7, 10 µm margins
- Power rings on METAL1 (H) / METAL2 (V)
- Clock tree synthesis via `ccopt_design`
- Routing: SI-driven NanoRoute
- Signoff: OCV / CPPR, 50 worst paths
- Exports: `../par/efficient_mac.v`, `../par/efficient_mac.sdf`, `../par/efficient_mac.gds`

MMMC corners (`mmmc.view`):
| Corner      | Library   | Use        |
|-------------|-----------|------------|
| corner_cmax | lib_slow  | Setup (max)|
| corner_rcmax| lib_slow  | Setup (max)|
| corner_cmin | lib_fast  | Hold (min) |
| corner_rcmin| lib_fast  | Hold (min) |

### Step 5 — Post-Layout Simulation

```sh
cd Efficient_MAC/par_sim
./run          # compiles post-route netlist with SDF
./run1         # runs simulation (400 000 time units — shorter than RTL)
./run2         # launches DVE
./clean        # removes artefacts
```

---

## Report Compilation

The project report lives in `Report.qmd` (Quarto Markdown).

```sh
quarto render Report.qmd --to pdf
```

Images pasted directly into VS Code are auto-saved alongside the `.qmd`. Use the Quarto VS Code extension for live preview.

---

## Key Files

| File | Purpose |
|------|---------|
| `Efficient_MAC/rtl/mac_top.v` | Top-level MAC pipeline (3 stages) |
| `Efficient_MAC/rtl/merged_multiplier.v` | Karatsuba 11-bit multiplier core (FLP + FIX dual-mode) |
| `Efficient_MAC/rtl/booth_multiplier_8x8_dual.v` | Radix-4 Booth 8×8 multiplier, signed/unsigned |
| `Efficient_MAC/rtl/cla_4bit.v` / `cla_16bit.v` | Carry look-ahead adder hierarchy |
| `Efficient_MAC/rtl/csa_4to2_16bit.v` | 16-bit 4:2 carry-save adder |
| `Efficient_MAC/rtl/csa_4to2_16bit_add2.v` | 4:2 CSA with +2 correction for two's-complement subtraction |
| `scripts/parallel_verify.py` | Primary verification driver: 100k directed-random vectors, 12 batches |
| `Efficient_MAC/bhav_sim/tb_mac_top.v` | Data-driven testbench (reads `tv_inputs.txt`) |
| `Efficient_MAC/bhav_sim/VERIFICATION_GUIDE.md` | Full verification strategy, commands, bug report |
| `Efficient_MAC/syn/run.tcl` | DC synthesis script |
| `Efficient_MAC/par/innovus.cmd` | Innovus P&R command log |
| `Efficient_MAC/par/mmmc.view` | Multi-mode multi-corner setup |
| `Report.qmd` | Project report source |

---

## Current Verification Status

Last run: `scripts/parallel_verify.py --recompile` — 2026-05-18  
Log: `Efficient_MAC/bhav_sim/logs/verify_20260518_203117.log`  
Pass criterion: **exact bit match against `float_ref()` (float64 IEEE 754 reference)**

| Suite | Vectors | Pass | Fail |
|---|---|---|---|
| `fix_random_0,1` | 25,000 | 25,000 | **0** |
| `flp_add_0,1` | 18,000 | 8,052 | 9,948 |
| `flp_sub_low_0,1,2` | 27,000 | 25,854 | 1,146 |
| `flp_sub_high_0` | 9,000 | 945 | 8,055 |
| `flp_cancel_0,1` | 14,000 | 1,719 | 12,281 |
| `flp_boundary_0,1` | 7,000 | 3,121 | 3,879 |
| **TOTAL** | **100,000** | **64,691** | **35,309** |

FIX mode: clean. FLP failures (47.1% of FLP vectors) split into two root causes:

1. **Karatsuba overflow** (~2,832 vectors): `sum_X[8]` dropped when X0+X1>255 — produces errors of hundreds to millions of ULP. See `Efficient_MAC/bhav_sim/VERIFICATION_GUIDE.md` bug report.
2. **RTL vs float64 rounding discrepancy** (~32,477 vectors): the RTL and the `fp_ref()` pipeline mirror agree with each other but diverge from `float_ref()` by 1–30 ULP. Concentrated in cancellation (87.7% fail rate) and far-path subtraction (89.5% fail rate) where the 58-bit fixed-point field has insufficient dynamic range to preserve all significant bits before rounding.

---

## Conventions

- RTL must be written in synthesisable Verilog (no unsupported SystemVerilog constructs for DC 2019).
- Avoid inferring latches (`hdlin_check_no_latch true` is enforced in `.synopsys_dc.setup`).
- All buses use `signal[MSB:LSB]` naming style (`bus_naming_style {%s[%d]}`).
- Do not commit tool-generated output directories (`ddc/`, `rpt/`, `net/*.v`, `par/*.gds`, `par/*.enc`, `*simv*`, `*.vpd`) — see `.gitignore`.
