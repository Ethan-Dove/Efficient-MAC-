`timescale 1ns/1ps
// IN:  float_mode   [1]   — 1=FP16 mode, 0=INT mode
// IN:  sign         [2:0] — {sign_a, sign_b, sign_acc} from input_processing
// OUT: sign_fp      [1]   — product sign: sign[2] ^ sign[1] (FP mode only)
// OUT: eop_fp       [1]   — effective operation: sign_fp ^ sign[0], 1=subtraction
// OUT: inv_addend   [1]   — 1-bit control to invert_addend module (= eop_fp)
module invert_control(
    input  wire       float_mode,
    input  wire [2:0] sign,
    output wire       sign_fp, eop_fp, inv_addend
);
    assign sign_fp    = float_mode ? (sign[2] ^ sign[1]) : 1'b0;
    assign eop_fp     = float_mode ? (sign_fp ^ sign[0]) : 1'b0;
    assign inv_addend = eop_fp;
endmodule
