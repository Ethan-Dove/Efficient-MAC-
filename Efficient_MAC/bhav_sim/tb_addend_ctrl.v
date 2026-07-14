`timescale 1ns/1ps

module tb_addend_ctrl;

    reg  [7:0] exp_a;
    reg  [7:0] exp_b;
    reg  [7:0] acc_exp;
    reg        sign_p;
    reg        sign_acc;
    reg        acc_is_zero;

    wire [5:0] shift_amt;
    wire       do_sub;
    wire       zero_acc;
    wire [7:0] exp_ref;

    integer i;

    addend_ctrl dut (
        .exp_a(exp_a),
        .exp_b(exp_b),
        .acc_exp(acc_exp),
        .sign_p(sign_p),
        .sign_acc(sign_acc),
        .acc_is_zero(acc_is_zero),
        .shift_amt(shift_amt),
        .do_sub(do_sub),
        .zero_acc(zero_acc),
        .exp_ref(exp_ref)
    );

    initial begin
        $dumpfile("dump_addend_ctrl.vcd");
        $dumpvars(0, tb_addend_ctrl);

        // Shift amount and alignment control logic
        // Exponents for FP16 are 0-31, Accumulator FP32 exp
        for (i = 0; i < 20; i = i + 1) begin
            exp_a       = $unsigned($random) % 32;
            exp_b       = $unsigned($random) % 32;
            acc_exp     = 8'd127 + ($signed(exp_a) - 15) + ($signed(exp_b) - 15);
            sign_p      = $random;
            sign_acc    = $random;
            acc_is_zero = $random % 2;
            #10;
        end

        #100;
        $finish;
    end

endmodule
