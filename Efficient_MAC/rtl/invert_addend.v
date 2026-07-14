`timescale 1ns/1ps
// IN:  addend_fp      [23:0] — FP32 accumulator mantissa (24-bit with hidden bit)
// IN:  inv_addend_ctrl[1]    — 1=invert (subtraction), from invert_control
// OUT: inv_addend     [57:0] — {~addend_fp, 34'h3FFFFFFFF} if ctrl=1, else {addend_fp, 34'd0}
module invert_addend(
    input  wire [23:0] addend_fp,
    input  wire        inv_addend_ctrl,
    output wire [57:0] inv_addend
);
    assign inv_addend = inv_addend_ctrl ? {~addend_fp, 34'h3FFFFFFFF} : {addend_fp, 34'd0};
endmodule
