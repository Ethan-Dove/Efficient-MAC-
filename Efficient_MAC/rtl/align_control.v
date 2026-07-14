`timescale 1ns/1ps
// IN:  exp_acc  [7:0]  — FP32 accumulator exponent
// IN:  exp_ab   [9:0]  — {exp_a[4:0], exp_b[4:0]} packed FP16 exponents
// OUT: shift_amt[5:0]  — right-shift to align accumulator: ea+eb+134-ec, clamped [0,57]
// OUT: exp_align[7:0]  — exponent of bit 57 of the 58-bit field: (ea+eb+134)&0xFF
module align_control(
    input  wire [7:0] exp_acc,
    input  wire [9:0] exp_ab,
    output wire [5:0] shift_amt,
    output wire [7:0] exp_align
);
    wire [4:0] exp_a, exp_b;
    assign exp_a = exp_ab[9:5];
    assign exp_b = exp_ab[4:0];
    assign shift_amt = (shift_amt_raw < 0) ? 6'd0 : (shift_amt_raw > 57) ? 6'd57 : shift_amt_raw[5:0];
    assign exp_align = {3'd0, exp_a} + {3'd0, exp_b} + 8'd134;
endmodule
