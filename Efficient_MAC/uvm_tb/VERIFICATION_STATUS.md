# UVM Verification Status

## Environment

| Item | Detail |
|---|---|
| Local simulator | Questa Intel FSE 2024.3 (`questa_fse`) |
| Server simulator | Synopsys VCS 2020.03-SP1-1 |
| UVM version | 1.2 |
| RTL language | SystemVerilog (IEEE 1800-2012) |

---

## Compilation — PASS

Both RTL and UVM TB compile cleanly under Questa with 0 errors, 0 warnings.

```
vlog -sv [...] -L uvm_lib -f filelist.f
-- Compiling module booth_encoder
-- Compiling module mult3
-- Compiling module mult8
-- Compiling module merged_multiplier
-- Compiling module align_shifter
-- Compiling module lza
-- Compiling module carry_propagate_adder
-- Compiling module normalization_shifter
-- Compiling module rounder
-- Compiling module mac_top
-- Compiling interface mac_if
-- Compiling module tb_top
Errors: 0, Warnings: 0
```

One compatibility fix was required when moving from VCS to Questa:
- `mac_scoreboard.sv`: replaced VCS-specific `logic [31:0]'(expr)` cast with portable
  `{{24{x[7]}}, x}` sign extension and direct `!==` comparison.

---

## Local Simulation (Questa FSE) — BLOCKED: edition limitation

Questa Intel **FPGA Starter Edition** does not include the `svverification`
license feature required for `randomize()` and `covergroup`. This is a hard
edition restriction — not a configuration issue.

**Errors encountered and resolved during investigation:**

| Issue | Root cause | Resolution |
|---|---|---|
| `Unable to checkout a license` | No `MGLS_LICENSE_FILE` set | Added license to `~/.bashrc` |
| `Could not link vsim_auto_compile.so` | Questa GCC 10.3 `ld` incompatible with glibc 2.36+ `.relr.dyn` section | Replaced `questa_fse/gcc-10.3.0.../ld` with symlink to system `ld` 2.46 |
| `Failure to checkout svverification license` | Questa FSE edition does not include SV verification features | Edition limitation — use VCS server |

**Compile step passes cleanly (0 errors, 0 warnings)** — the RTL and UVM TB are
syntactically correct and tool-compatible. Only the simulation execution step
requires the full verification license.

## Server Simulation (VCS) — RECOMMENDED

Run on the HKUST ECE server where full VCS + UVM license is available:

```bash
source /usr/eelocal/synopsys/vcs-vq2020.03-sp1-1/.cshrc
cd Efficient_MAC/uvm_tb/run
make sim_all
make cov_report
```

Expected output:
```
UVM_INFO SCOREBOARD [PASS] pass=NNN fail=0 total=NNN
UVM_INFO COVERAGE   Functional coverage: 100.00%
```

---

## Test Plan

| Test | Sequence | Transactions | Purpose |
|---|---|---|---|
| `mac_directed_test` | `mac_directed_seq` | 10 directed | Replicate original TB vectors |
| `mac_corner_test` | `mac_corner_seq` | ~415 | FP specials, overflow, sign combos |
| `mac_random_test` | `mac_random_seq` | 1000 random | Constrained-random discovery |

---

## Coverage Targets

| Bin | Description | Target |
|---|---|---|
| `mode_cp` | FIX and FLP modes exercised | 100% |
| `fp_exp_a/b` | Zero / normal / NaN-Inf exponents | 100% |
| `sign_combo` | All four PP/PN/NP/NN combinations | 100% |
| `acc_zero` | Zero and non-zero accumulator | 100% |
| `mode_x_sign` | All mode × sign cross products | 100% |
| `mode_x_exp_a` | All mode × exponent cross products | 100% |
