`timescale 1ns/1ps

module tb_csa_42;

    parameter N = 16;

    reg  [N-1:0] in0;
    reg  [N-1:0] in1;
    reg  [N-1:0] in2;
    reg  [N-1:0] in3;

    wire [N-1:0] sum;
    wire [N-1:0] cout;

    integer i;

    csa_42 #(.N(N)) dut (
        .in0(in0),
        .in1(in1),
        .in2(in2),
        .in3(in3),
        .sum(sum),
        .cout(cout)
    );

    initial begin
        $dumpfile("dump_csa_42.vcd");
        $dumpvars(0, tb_csa_42);

        in0 = 0; in1 = 0; in2 = 0; in3 = 0;
        for (i = 0; i < 20; i = i + 1) begin
            #10;
            in0 = $random; in1 = $random;
            in2 = $random; in3 = $random;
        end

        #100;
        $finish;
    end

endmodule
