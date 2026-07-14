`timescale 1ns/1ps

module tb_align_shifter;

    reg  [31:0] accumulator;
    reg  [5:0]  shift_amt;

    wire [57:0] shifted_acc;

    integer i;

    align_shifter dut (
        .accumulator(accumulator),
        .shift_amt(shift_amt),
        .shifted_acc(shifted_acc)
    );

    initial begin
        $dumpfile("dump_align_shifter.vcd");
        $dumpvars(0, tb_align_shifter);

        // Accumulator shifting (0 to 57)
        for (i = 0; i < 20; i = i + 1) begin
            accumulator = $random;
            shift_amt = $unsigned($random) % 58;
            #10;
        end

        #100;
        $finish;
    end

endmodule
