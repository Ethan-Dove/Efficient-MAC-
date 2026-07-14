`timescale 1ns/1ps
// IN:  sum_high    [26:0] — upper 27 bits from end-around carry mux
// IN:  sum_low     [31:0] — lower 32 bits from CPA
// IN:  eop_fp      [1]    — 1=subtraction
// IN:  sign_fp     [1]    — pipelined result sign from Stage 1
// OUT: sum_fp      [57:0] — 2's-complement negated if is_neg, else passthrough
// OUT: sign_fp_out [1]    — final sign: flipped if is_neg
// OUT: is_neg      [1]    — eop_fp & ~sum_high[26]: subtraction with no end-around carry
module complementer(
    input  wire [26:0] sum_high,
    input  wire [31:0] sum_low,
    input  wire        eop_fp,
    input  wire        sign_fp,
    output wire [57:0] sum_fp,
    output wire        sign_fp_out,
    output wire        is_neg
);
    wire [57:0] sum_58;
    assign sum_58 = {sum_high[25:0], sum_low};

    // Subtraction with no end-around carry means result is negative
    assign is_neg      = eop_fp & ~sum_high[26];
    assign sum_fp      = is_neg ? (~sum_58 + 1'b1) : sum_58;
    assign sign_fp_out = is_neg ? ~sign_fp : sign_fp;
endmodule
