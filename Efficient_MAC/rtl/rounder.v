`timescale 1ns/1ps
// IN:  sum_norm [57:0] — normalized 58-bit mantissa from normalization_shifter
// IN:  exp_norm [7:0]  — normalized exponent
// OUT: mant_fp  [22:0] — rounded 23-bit mantissa (IEEE 754 RNE)
// OUT: exp_fp   [7:0]  — final exponent after rounding carry
module rounder(
    input  wire [57:0] sum_norm,
    input  wire [7:0]  exp_norm,
    output wire [22:0] mant_fp,
    output wire [7:0]  exp_fp
);
    wire [22:0] frac;
    wire G, R, S, round_up;
    wire [23:0] frac_rounded;

    assign frac         = sum_norm[56:34];   // [57]=hidden 1, [56:34]=23b mantissa
    assign G            = sum_norm[33];
    assign R            = sum_norm[32];
    assign S            = |sum_norm[31:0];
    assign round_up     = G & (R | S | frac[0]);
    assign frac_rounded = {1'b0, frac} + {23'd0, round_up};
    assign mant_fp      = frac_rounded[22:0];
    assign exp_fp       = exp_norm + {7'b0, frac_rounded[23]};
endmodule
