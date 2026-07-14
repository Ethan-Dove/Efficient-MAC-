`timescale 1ns/1ps

module tb_merged_multiplier;

    reg        float;
    reg [15:0] A;
    reg [15:0] B;

    wire [31:0] mul_sum_vec;
    wire [31:0] mul_carry_vec;

    integer i;

    merged_multiplier dut (
        .float(float),
        .A(A),
        .B(B),
        .mul_sum_vec(mul_sum_vec),
        .mul_carry_vec(mul_carry_vec)
    );

    initial begin
        $dumpfile("dump_merged_multiplier.vcd");
        $dumpvars(0, tb_merged_multiplier);

        // Paper Karatsuba FLP + parallel FIX 8-bit multiplier
        float = 0; A = 0; B = 0;
        #10;
        // FIX mode: Ah/Al and Bh/Bl
        float = 0;
        for (i = 0; i < 20; i = i + 1) begin
            A = $random; B = $random;
            #10;
        end
        // FLP mode: 11-bit mantissas (hidden bit set), upper 5 bits zeroed
        float = 1;
        for (i = 0; i < 20; i = i + 1) begin
            A = 16'h0400; A[9:0] = $random;
            B = 16'h0400; B[9:0] = $random;
            #10;
        end

        #100;
        $finish;
    end

endmodule
