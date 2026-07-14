`timescale 1ns/1ps
module input_processing(
    input  wire [15:0] A_r1, B_r1,
    input  wire [31:0] acc_r1,
    output wire [23:0] addend_fp,
    output wire [31:0] addend_fix,
    output wire [2:0]  sign,
    output wire [7:0]  exp_acc,
    output wire [9:0]  exp_ab,
    output wire [10:0] manta_fp, mantb_fp,
    output wire [15:0] A, B,
    output wire        acc_is_zero
);
    assign addend_fp   = {1'b1, acc_r1[22:0]};
    assign addend_fix  = acc_r1;
    assign sign        = {A_r1[15], B_r1[15], acc_r1[31]};
    assign exp_acc     = acc_r1[30:23];
    assign exp_ab      = {A_r1[14:10], B_r1[14:10]};
    assign manta_fp    = {1'b1, A_r1[9:0]};
    assign mantb_fp    = {1'b1, B_r1[9:0]};
    assign A           = A_r1;
    assign B           = B_r1;
    assign acc_is_zero = (acc_r1[30:0] == 31'd0);
endmodule
