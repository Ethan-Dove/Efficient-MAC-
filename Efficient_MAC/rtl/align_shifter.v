`timescale 1ns/1ps
// IN:  inv_addend[57:0] — aligned (possibly inverted) 58-bit accumulator from invert_addend
// IN:  shift_amt [5:0]  — right-shift amount from align_control
// IN:  eop_fp    [1]    — 1=subtraction: fill upper vacated bits with 1s
// OUT: c_align   [57:0] — shifted accumulator word fed into c_mix mux
// OUT: comp      [1]    — 1 if |A*B| > |C| predicted (shift_amt > 35)
// OUT: stk       [1]    — sticky bit: OR of bits shifted out of the 58-bit window
module align_shifter(
    input  wire [57:0] inv_addend,
    input  wire [5:0]  shift_amt,
    input  wire        eop_fp,
    output reg  [57:0] c_align,
    output reg         comp, stk
);
    reg  [57:0] orig_val, shift_mask;
    wire [57:0] s1, s2, s3, s4, s5;
    wire [57:0] data_in, data_out;
    wire [5:0]  shift_ctrl;

    assign data_in    = inv_addend;
    assign shift_ctrl = shift_amt;

    assign s1 = shift_ctrl[0] ? {1'b0,  data_in[57:1]}  : data_in;
    assign s2 = shift_ctrl[1] ? {2'b0,  s1[57:2]}       : s1;
    assign s3 = shift_ctrl[2] ? {4'b0,  s2[57:4]}       : s2;
    assign s4 = shift_ctrl[3] ? {8'b0,  s3[57:8]}       : s3;
    assign s5 = shift_ctrl[4] ? {16'b0, s4[57:16]}      : s4;
    assign data_out = shift_ctrl[5] ? {32'b0, s5[57:32]} : s5;

    always @(*) begin
        orig_val   = eop_fp ? ~data_in : data_in;
        c_align    = eop_fp ? ({58{1'b1}} << (58 - shift_amt)) | data_out : data_out;
        shift_mask = (58'd1 << shift_amt) - 1'b1;
        stk        = |(orig_val & shift_mask);
        comp       = eop_fp & (shift_amt > 6'd35);
    end
endmodule
