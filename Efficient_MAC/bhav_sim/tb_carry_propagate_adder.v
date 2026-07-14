`timescale 1ns/1ps

module tb_carry_propagate_adder;

    reg  [31:0] sum_vec;
    reg  [31:0] carry_vec;
    reg  [31:0] acc_low;

    wire [31:0] result;
    wire        cout;

    integer i;

    carry_propagate_adder dut (
        .sum_vec(sum_vec),
        .carry_vec(carry_vec),
        .acc_low(acc_low),
        .result(result),
        .cout(cout)
    );

    initial begin
        $dumpfile("dump_carry_propagate_adder.vcd");
        $dumpvars(0, tb_carry_propagate_adder);

        // Resolves carry-save plus aligned accumulator
        for (i = 0; i < 20; i = i + 1) begin
            sum_vec   = $random;
            carry_vec = $random;
            acc_low   = $random;
            #10;
        end

        #100;
        $finish;
    end

endmodule
