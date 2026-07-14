`timescale 1ns/1ps

module tb_rounder;

    reg  [57:0] mantissa_norm;

    wire [22:0] mantissa_out;
    wire        round_carry;

    integer i;

    rounder dut (
        .mantissa_norm(mantissa_norm),
        .mantissa_out(mantissa_out),
        .round_carry(round_carry)
    );

    initial begin
        $dumpfile("dump_rounder.vcd");
        $dumpvars(0, tb_rounder);

        // IEEE 754 RNE on 58-bit mantissa
        for (i = 0; i < 20; i = i + 1) begin
            mantissa_norm = {$random, $random};
            // Force interesting G,R,S bits
            mantissa_norm[33:31] = $random;
            #10;
        end

        #100;
        $finish;
    end

endmodule
