`timescale 1ns/1ps

module tb_normalization_shifter;

    reg  [57:0] mantissa_in;
    reg  [5:0]  count;
    reg         valid;

    wire [57:0] mantissa_out;

    integer i;

    normalization_shifter dut (
        .mantissa_in(mantissa_in),
        .count(count),
        .valid(valid),
        .mantissa_out(mantissa_out)
    );

    initial begin
        $dumpfile("dump_normalization_shifter.vcd");
        $dumpvars(0, tb_normalization_shifter);

        for (i = 0; i < 20; i = i + 1) begin
            mantissa_in = {$random, $random};
            count = $unsigned($random) % 58;
            valid = $random % 2;
            #10;
        end

        #100;
        $finish;
    end

endmodule
