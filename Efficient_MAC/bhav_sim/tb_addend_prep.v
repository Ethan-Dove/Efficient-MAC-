`timescale 1ns/1ps

module tb_addend_prep;

    reg  [31:0] accumulator;
    reg  [5:0]  shift_amt;
    reg         zero_acc;

    wire [57:0] c_align;

    integer i;

    addend_prep dut (
        .accumulator(accumulator),
        .shift_amt(shift_amt),
        .zero_acc(zero_acc),
        .c_align(c_align)
    );

    initial begin
        $dumpfile("dump_addend_prep.vcd");
        $dumpvars(0, tb_addend_prep);

        // FLP Accumulator gating & shifting
        for (i = 0; i < 20; i = i + 1) begin
            accumulator = $random;
            shift_amt = $unsigned($random) % 58;
            zero_acc = $random % 2;
            #10;
        end

        #100;
        $finish;
    end

endmodule
