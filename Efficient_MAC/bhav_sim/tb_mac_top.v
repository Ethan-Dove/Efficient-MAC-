`timescale 1ns/1ps

module tb_mac_top;

    reg        clk;
    reg        rst_n;
    reg        float;
    reg [15:0] A;
    reg [15:0] B;
    reg [31:0] accumulator;

    wire [31:0] OUT_fx;
    wire [31:0] OUT_fp;

    mac_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .float(float),
        .A(A),
        .B(B),
        .accumulator(accumulator),
        .OUT_fx(OUT_fx),
        .OUT_fp(OUT_fp)
    );

    integer fd;
    integer count;
    reg [256*8-1:0] tv_path;

    initial begin
        if (!$value$plusargs("tv=%s", tv_path))
            tv_path = "Efficient_MAC/bhav_sim/tv_inputs.txt";

        if (!$test$plusargs("no_vcd")) begin
            $dumpfile("dump_mac_top.vcd");
            $dumpvars(1, tb_mac_top);
        end

        $monitor("Time=%0t | float=%b | A=%h B=%h acc=%h | OUT_fx=%h OUT_fp=%h",
                 $time, float, A, B, accumulator, OUT_fx, OUT_fp);

        fd = $fopen(tv_path, "r");
        if (fd == 0) begin
            $display("ERROR: Could not open %s", tv_path);
            $finish;
        end

        clk = 0; rst_n = 0;
        float = 0; A = 0; B = 0; accumulator = 0;
        #15 rst_n = 1;

        while (!$feof(fd)) begin
            @(posedge clk);
            count = $fscanf(fd, "%b %h %h %h\n", float, A, B, accumulator);
        end

        // Drain pipeline (3 cycles after last input)
        repeat (4) @(posedge clk);

        $fclose(fd);
        $finish;
    end

    always #5 clk = ~clk;

endmodule
