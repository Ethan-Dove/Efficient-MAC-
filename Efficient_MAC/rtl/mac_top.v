`timescale 1ns/1ps
// IN:  clk        [1]    — clock
// IN:  rst_n      [1]    — active-low reset
// IN:  float      [1]    — mode select: 1=FP16, 0=INT8
// IN:  A          [15:0] — operand A: FP16 or INT8 packed {Ah[7:0], Al[7:0]}
// IN:  B          [15:0] — operand B: FP16 or INT8 packed {Bh[7:0], Bl[7:0]}
// IN:  accumulator[31:0] — accumulator: FP32 or INT32
// OUT: OUT_fx     [31:0] — fixed-point result (2-cycle latency)
// OUT: OUT_fp     [31:0] — floating-point result (3-cycle latency)
module mac_top(
    input  wire        clk, rst_n,
    input  wire        float,
    input  wire [15:0] A, B,
    input  wire [31:0] accumulator,
    output reg  [31:0] OUT_fx, OUT_fp
);
    // -------------------------------------------------------------------------
    // INPUT REGISTERS
    // -------------------------------------------------------------------------
    reg        float_r1;
    reg [15:0] A_r1, B_r1;
    reg [31:0] acc_r1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            float_r1 <= 0; A_r1 <= 0; B_r1 <= 0; acc_r1 <= 0;
        end else begin
            float_r1 <= float; A_r1 <= A; B_r1 <= B; acc_r1 <= accumulator;
        end
    end

    // -------------------------------------------------------------------------
    // STAGE 1
    // -------------------------------------------------------------------------
    wire [23:0] addend_fp;
    wire [57:0] inv_addend;
    wire [31:0] addend_fix;
    wire [2:0]  sign;
    wire [7:0]  exp_acc, exp_align;
    wire [9:0]  exp_ab;
    wire [10:0] manta_fp, mantb_fp;
    wire [15:0] A_w, B_w;
    wire        acc_is_zero, sign_fp, eop_fp, comp, stk, inv_addend_ctrl;
    wire [5:0]  shift_amt;
    wire [57:0] c_align, c_mix;
    wire [31:0] mul_result;

    input_processing in_proc(
        .A_r1(A_r1), .B_r1(B_r1), .acc_r1(acc_r1),
        .addend_fp(addend_fp), .addend_fix(addend_fix),
        .sign(sign), .exp_acc(exp_acc), .exp_ab(exp_ab),
        .manta_fp(manta_fp), .mantb_fp(mantb_fp), .A(A_w), .B(B_w),
        .acc_is_zero(acc_is_zero)
    );

    invert_control inv_ctrl(.float_mode(float_r1), .sign(sign), .sign_fp(sign_fp), .eop_fp(eop_fp), .inv_addend(inv_addend_ctrl));

    invert_addend inv_add(.addend_fp(addend_fp), .inv_addend_ctrl(inv_addend_ctrl), .inv_addend(inv_addend));

    align_control al_ctrl(.exp_acc(exp_acc), .exp_ab(exp_ab), .shift_amt(shift_amt), .exp_align(exp_align));

    align_shifter al_shift(
        .inv_addend(inv_addend), .shift_amt(shift_amt),
        .eop_fp(eop_fp),
        .c_align(c_align), .comp(comp), .stk(stk)
    );

    assign c_mix = float_r1 ? c_align : {26'd0, addend_fix};

    merged_multiplier mul_inst(
        .float(float_r1),
        .X(float_r1 ? manta_fp         : {3'b0, A_w[7:0]}),   // FP: 11b mantissa; INT: Al
        .Y(float_r1 ? mantb_fp         : {3'b0, B_w[7:0]}),   // FP: 11b mantissa; INT: Bl
        .ext_A(A_w[15:8]),                                     // INT: Ah (Booth mid-multiplier)
        .ext_B(B_w[15:8]),                                     // INT: Bh
        .result(mul_result)
    );

    // -------------------------------------------------------------------------
    // PIPELINE REG 1
    // -------------------------------------------------------------------------
    reg [57:0] c_mix_r2;
    reg [31:0] mul_result_r2;
    reg [7:0]  exp_align_r2;
    reg        sign_fp_r2, eop_fp_r2, comp_r2, stk_r2, float_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_mix_r2 <= 0; mul_result_r2 <= 0;
            exp_align_r2 <= 0; sign_fp_r2 <= 0; eop_fp_r2 <= 0;
            comp_r2 <= 0; stk_r2 <= 0; float_r2 <= 0;
        end else begin
            c_mix_r2 <= c_mix; mul_result_r2 <= mul_result;
            exp_align_r2 <= exp_align; sign_fp_r2 <= sign_fp; eop_fp_r2 <= eop_fp;
            comp_r2 <= comp; stk_r2 <= stk; float_r2 <= float_r1;
        end
    end

    // -------------------------------------------------------------------------
    // STAGE 2
    // -------------------------------------------------------------------------
    wire [31:0] sum_vec, carry_vec, sum_low;
    wire [26:0] inc_out, sum_high;
    wire [57:0] sum_fp;
    wire [5:0]  count;
    wire        cin, stk_add, cout, valid, sign_fp_out, is_neg;

    // final_out is resolved — feed directly as the two CPA operands
    assign sum_vec   = mul_result_r2;
    assign carry_vec = c_mix_r2[31:0];

    incrementer inc_inst(.c_mix(c_mix_r2[57:32]), .inc_out(inc_out));

    cin_gen cin_gen_inst(.eop_fp(eop_fp_r2), .stk(stk_r2), .comp(comp_r2), .cin(cin), .stk_add(stk_add));

    carry_propagate_adder cpa_inst(.sum_vec(sum_vec), .carry_vec(carry_vec), .cin(cin), .cout(cout), .sum_low(sum_low));

    // cout=1: end-around carry — use pre-incremented upper word
    // cout=0: no carry — use original c_mix upper word zero-extended to 27b
    assign sum_high = cout ? inc_out : {1'b0, c_mix_r2[57:32]};

    complementer comp_inst(
        .sum_high(sum_high), .sum_low(sum_low),
        .eop_fp(eop_fp_r2), .sign_fp(sign_fp_r2),
        .sum_fp(sum_fp), .sign_fp_out(sign_fp_out), .is_neg(is_neg)
    );

    lza_lzc lza_inst(
        .op1({c_mix_r2[57:32], mul_result_r2}),
        .op2({26'd0, c_mix_r2[31:0]}),
        .count(count), .valid(valid)
    );

    // -------------------------------------------------------------------------
    // PIPELINE REG 2 / FIXED-POINT OUTPUT REG
    // -------------------------------------------------------------------------
    reg [57:0] sum_norm_in;
    reg [7:0]  exp_align_r3;
    reg [5:0]  count_r3;
    reg        valid_r3, sign_fp_r3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            OUT_fx <= 0; sum_norm_in <= 0; count_r3 <= 0;
            valid_r3 <= 0; exp_align_r3 <= 0; sign_fp_r3 <= 0;
        end else begin
            OUT_fx <= sum_low; // FIX output ready
            sum_norm_in <= sum_fp;
            count_r3 <= count;
            valid_r3 <= valid;
            exp_align_r3 <= exp_align_r2;
            sign_fp_r3 <= sign_fp_out;
        end
    end

    // -------------------------------------------------------------------------
    // STAGE 3
    // -------------------------------------------------------------------------
    wire [57:0] sum_norm_out;
    wire [7:0]  exp_norm, exp_fp;
    wire [22:0] mant_fp;

    normalization_shifter norm_shifter(
        .sum_norm_in(sum_norm_in), .count(count_r3), .valid(valid_r3),
        .exp_align(exp_align_r3),
        .sum_norm_out(sum_norm_out), .exp_norm(exp_norm)
    );

    rounder rnd_inst(
        .sum_norm(sum_norm_out), .exp_norm(exp_norm),
        .mant_fp(mant_fp), .exp_fp(exp_fp)
    );

    // -------------------------------------------------------------------------
    // FLOATING-POINT OUTPUT REG
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) OUT_fp <= 0;
        else OUT_fp <= (sum_norm_out == 58'd0) ? 32'd0 : {sign_fp_r3, exp_fp, mant_fp};
    end
endmodule