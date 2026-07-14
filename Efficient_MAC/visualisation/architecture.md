# Efficient Fixed/Floating-Point Merged MAC Architecture

Block diagram of the 3-stage pipelined, mixed-precision multiply-accumulate unit precisely mapped to the verified Verilog structural modules and exact signal widths.

Preview in VS Code or any Markdown viewer that supports Mermaid.

```mermaid
graph TD
    classDef reg fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#000;
    classDef logicBlock fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000;
    classDef io fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#000;

    ACC([accumulator 32]):::io
    FLOAT([float 1]):::io
    A([A 16]):::io
    B([B 16]):::io

    IN_REG[INPUT REGISTERS]:::reg

    ACC --> IN_REG
    FLOAT --> IN_REG
    A --> IN_REG
    B --> IN_REG

    %% --------------------------------
    %% STAGE 1
    %% --------------------------------
    INPUT_PROC([input_processing.v]):::logicBlock
    IN_REG -->|A_r1, B_r1, acc_r1| INPUT_PROC

    INV_ADD([invert_addend.v]):::logicBlock
    INV_CTRL([invert_control.v]):::logicBlock
    ALN_CTRL([align_control.v]):::logicBlock
    ALN_SHF([align_shifter.v]):::logicBlock
    MUL([merged_multiplier.v]):::logicBlock
    CMIX_MUX{c_mix MUX}:::logicBlock

    INPUT_PROC -->|addend_fp 24| INV_ADD
    INPUT_PROC -->|addend_fix 32| CMIX_MUX
    INPUT_PROC -->|sign 3| INV_CTRL
    IN_REG -.->|float_r1| INV_CTRL
    INPUT_PROC -->|exp_acc 8, exp_ab 10| ALN_CTRL
    INPUT_PROC -->|manta_fp 11, mantb_fp 11, A 16, B 16| MUL
    IN_REG -.->|float_r1| MUL
    IN_REG -.->|float_r1| CMIX_MUX

    INV_CTRL -->|inv_addend_ctrl 1| INV_ADD
    INV_CTRL -->|eop_fp 1| ALN_SHF
    INV_ADD -->|inv_addend 58| ALN_SHF

    ALN_CTRL -->|shift_amt 6| ALN_SHF
    ALN_CTRL -->|exp_align 8| PIPE_REG1
    ALN_SHF -->|c_align 58| CMIX_MUX

    PIPE_REG1[PIPELINE REG 1]:::reg

    INV_CTRL -->|sign_fp 1, eop_fp 1| PIPE_REG1
    ALN_SHF -->|comp 1, stk 1| PIPE_REG1
    CMIX_MUX -->|c_mix 58| PIPE_REG1
    MUL -->|result 32| PIPE_REG1

    %% --------------------------------
    %% STAGE 2
    %% --------------------------------
    INC([incrementer.v]):::logicBlock
    CPA([carry_propagate_adder.v]):::logicBlock
    CINGEN([cin_gen.v]):::logicBlock
    LZA([lza_lzc.v]):::logicBlock
    COMP([complementer.v]):::logicBlock
    COUT_MUX{cout MUX}:::logicBlock

    PIPE_REG1 -->|c_mix_r2 57:32| INC
    PIPE_REG1 -->|c_mix_r2 57:32, mul_result_r2 32| LZA
    PIPE_REG1 -->|c_mix_r2 31:0| LZA

    PIPE_REG1 -->|eop_fp_r2, stk_r2, comp_r2| CINGEN
    CINGEN -->|cin 1| CPA

    PIPE_REG1 -->|mul_result_r2 32| CPA
    PIPE_REG1 -->|c_mix_r2 31:0| CPA

    CPA -->|cout 1| COUT_MUX
    INC -->|inc_out 27| COUT_MUX
    PIPE_REG1 -->|c_mix_r2 57:32| COUT_MUX

    COUT_MUX -->|sum_high 27| COMP
    CPA -->|sum_low 32| COMP
    PIPE_REG1 -->|eop_fp_r2 1, sign_fp_r2 1| COMP

    PIPE_REG2[PIPELINE REG 2 / FIXED-POINT OUTPUT REG]:::reg

    LZA -->|count 6, valid 1| PIPE_REG2
    COMP -->|sum_fp 58, sign_fp_out 1| PIPE_REG2
    CPA -->|sum_low 32| PIPE_REG2
    PIPE_REG1 -->|exp_align_r2 8| PIPE_REG2

    OUT_FIX([OUT_fx 32]):::io
    PIPE_REG2 -->|sum_low 32| OUT_FIX

    %% --------------------------------
    %% STAGE 3
    %% --------------------------------
    NORM([normalization_shifter.v]):::logicBlock
    RND([rounder.v]):::logicBlock

    PIPE_REG2 -->|exp_align_r3 8| NORM
    PIPE_REG2 -->|count_r3 6, valid_r3 1| NORM
    PIPE_REG2 -->|sum_norm_in 58| NORM

    NORM -->|sum_norm_out 58, exp_norm 8| RND

    FLP_REG[FLOATING-POINT OUTPUT REG]:::reg

    RND -->|mant_fp 23, exp_fp 8| FLP_REG
    PIPE_REG2 -->|sign_fp_r3 1| FLP_REG

    OUT_FP([OUT_fp 32]):::io
    FLP_REG -->|sign 1, exp 8, mant 23| OUT_FP
```

---

## Signal Glossary

| Signal | Width | Stage | Description |
|---|---|---|---|
| `eop_fp` | 1 | 1 | Effective operation: 1 = subtract (sign_p ≠ sign_acc), 0 = add |
| `inv_addend_ctrl` | 1 | 1 | = eop_fp; selects bitwise inversion of addend_fp in invert_addend |
| `inv_addend` | 58 | 1 | Inverted or straight 58-bit accumulator field from invert_addend |
| `shift_amt` | 6 | 1 | Right-shift to align accumulator: `ea + eb + 134 − ec`, clamped [0,57] |
| `exp_align` | 8 | 1→3 | Exponent of bit 57 of the 58-bit field: `(ea+eb+134) & 0xFF` |
| `c_mix` | 58 | 1 | FLP: aligned (possibly inverted) accumulator; FIX: zero-padded `addend_fix` |
| `comp` | 1 | 1 | Fill-with-ones flag from align_shifter (shift_amt > 35) |
| `stk` | 1 | 1 | Sticky bit: OR of all bits shifted out of the 58-bit window |
| `result` | 32 | 1 | Multiplier output: 32-bit product from merged_multiplier |
| `cin` | 1 | 2 | Carry-in to CPA: `= eop_fp` (completes ones-complement addition) |
| `sum_high` | 27 | 2 | Upper 27 bits of 58-bit sum: `cout ? inc_out : {1'b0, c_mix_r2[57:32]}` |
| `is_neg` | 1 | 2 | `eop_fp & ~sum_high[26]`: subtraction with negative result → negate |
| `sign_fp_out` | 1 | 2 | Result sign: `is_neg ? ~sign_fp : sign_fp` |
| `sum_fp` | 58 | 2 | Post-complement 58-bit sum (pass-through or 2's-complement negated) |
| `count` | 6 | 2 | LZA predicted shift (F-string, parallel with CPA); passed to Stage 3 |
| `actual_shift` | 6 | 3 | Exact LZC of `sum_norm_in` (ascending loop, highest set bit wins) |
| `sum_norm_out` | 58 | 3 | Left-shifted normalized mantissa |
| `exp_norm` | 8 | 3 | `exp_align − actual_shift` |

---

## Key Design Notes

**Karatsuba split** — FP16 11-bit mantissa: `mah = mant[10:8]` (3 bits), `mal = mant[7:0]` (8 bits). Product = `mal·mbl + mah·mbh·2^16 + cross·2^8`. The cross term uses the same `mult8` hardware that handles INT8 in FIX mode.

**58-bit accumulation field layout**
```
 bit 57                              bit 0
  |← accumulator mantissa (24b) →|            |← product (22b) →|
  [57:34]                                      [21:0]
  ↑ MSB of acc lands at 57 − shift_amt
```

**Ones-complement subtraction** — When `eop_fp=1`, the accumulator mantissa is bit-inverted by `invert_addend` and the lower 34 bits of `c_align` are filled with 1s. `cin=eop_fp=1` completes the two's complement across the CPA boundary. If `sum_high[26]` is not set (no end-around carry), the result is negative and `complementer` performs a true 2's-complement negation.

**Exact LZC in normalization** — `normalization_shifter` performs an exact ascending-loop LZC on the post-complement `sum_norm_in` for all cases. The `count`/`valid` ports forwarded from `lza_lzc` are connected but not used by the current implementation; they are retained for a future LZA-corrected normalisation path.

**Known defect — Karatsuba middle-term overflow** — The sums `X0+X1` and `Y0+Y1` are 9-bit values but truncated to 8 bits before the middle Booth multiplier. This corrupts the cross term for ~4.2% of normal FP16 operand pairs and is the root cause of the 47.1% FLP failure rate.
