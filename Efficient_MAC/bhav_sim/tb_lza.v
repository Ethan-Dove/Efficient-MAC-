`timescale 1ns/1ps

module tb_lza;

    reg  [57:0] A;
    reg  [57:0] B;

    wire [5:0]  count;
    wire        valid;

    integer i;

    lza dut (
        .A(A),
        .B(B),
        .count(count),
        .valid(valid)
    );

    initial begin
        $dumpfile("dump_lza.vcd");
        $dumpvars(0, tb_lza);

        // Leading zero anticipation
        for (i = 0; i < 20; i = i + 1) begin
            A = {$random, $random};
            // Try close values to create variable leading zeros
            B = ~A + ($random % 5);
            #10;
            A = {$random, $random};
            B = {$random, $random};
            #10;
        end

        #100;
        $finish;
    end

endmodule
