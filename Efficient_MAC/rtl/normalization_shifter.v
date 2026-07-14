`timescale 1ns/1ps
// IN:  sum_norm_in [57:0] — post-complement 58-bit sum from complementer
// IN:  count       [5:0]  — LZA predicted shift (unused; exact LZC applied instead)
// IN:  valid       [1]    — always 1, forwarded from lza_lzc
// IN:  exp_align   [7:0]  — exponent of bit 57: (ea+eb+134)&0xFF
// OUT: sum_norm_out[57:0] — left-shifted normalized mantissa
// OUT: exp_norm    [7:0]  — exp_align - actual_shift
module normalization_shifter(
    input  wire [57:0] sum_norm_in,
    input  wire [5:0]  count,
    input  wire        valid,
    input  wire [7:0]  exp_align,
    output wire [57:0] sum_norm_out,
    output wire [7:0]  exp_norm
);
    // Exact LZC on the post-complement sum.
    reg [5:0] actual_shift;
    integer k;
    always @(*) begin
        actual_shift = 6'd57;   // default if all zeros
        for (k = 0; k <= 57; k = k + 1)  // ascending: highest set bit wins
            if (sum_norm_in[k])
                actual_shift = 57 - k;
    end

    assign sum_norm_out = sum_norm_in << actual_shift;
    assign exp_norm     = exp_align - {2'b0, actual_shift};
endmodule
