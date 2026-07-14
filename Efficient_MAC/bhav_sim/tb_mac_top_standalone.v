`timescale 1ns/1ps
// Standalone self-checking testbench for mac_top
// Verilog-2001; suitable for post-PnR verification with SDF back-annotation
//
// Usage (RTL):
//   iverilog -g2001 -o /tmp/mac_sa Efficient_MAC/bhav_sim/tb_mac_top_standalone.v \
//            Efficient_MAC/rtl/*.v && vvp /tmp/mac_sa [+no_vcd]
//
// Usage (post-PnR with SDF):
//   iverilog -g2001 -DSDF_FILE=\"mac_top.sdf\" -o /tmp/mac_sa_pnr \
//            Efficient_MAC/bhav_sim/tb_mac_top_standalone.v mac_top_netlist.v \
//            && vvp /tmp/mac_sa_pnr [+no_vcd]

module tb_mac_top_standalone;

    // ── DUT signals ───────────────────────────────────────────────────────────
    reg         clk;
    reg         rst_n;
    reg         float_mode;
    reg  [15:0] A;
    reg  [15:0] B;
    reg  [31:0] accumulator;
    wire [31:0] OUT_fx;
    wire [31:0] OUT_fp;

    // ── Counters ──────────────────────────────────────────────────────────────
    integer pass_count;
    integer fail_count;

    // ── DUT ───────────────────────────────────────────────────────────────────
    mac_top dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .float       (float_mode),
        .A           (A),
        .B           (B),
        .accumulator (accumulator),
        .OUT_fx      (OUT_fx),
        .OUT_fp      (OUT_fp)
    );

    // ── Clock: 10 ns period ───────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── Reset ─────────────────────────────────────────────────────────────────
    task do_reset;
        begin
            rst_n      = 1'b0;
            float_mode = 1'b0;
            A          = 16'h0;
            B          = 16'h0;
            accumulator = 32'h0;
            repeat (3) @(posedge clk);
            #1 rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    // ── FIX-mode check (3-cycle pipeline latency) ─────────────────────────────
    // Apply inputs after a posedge, then wait 3 more posedges for OUT_fx.
    task check_fix;
        input [15:0] A_in;
        input [15:0] B_in;
        input [31:0] acc_in;
        input [31:0] exp_out;
        input [7:0]  vec_id;
        begin
            @(posedge clk); #1;
            A = A_in; B = B_in; accumulator = acc_in; float_mode = 1'b0;
            @(posedge clk); #1;   // input reg latches
            @(posedge clk); #1;   // pipeline reg 1
            @(posedge clk); #1;   // OUT_fx valid
            if (OUT_fx === exp_out) begin
                $display("PASS  FIX[%0d]  OUT_fx = %0d", vec_id, $signed(OUT_fx));
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  FIX[%0d]  OUT_fx = %0d  exp = %0d  (A=%04h B=%04h acc=%08h)",
                         vec_id, $signed(OUT_fx), $signed(exp_out), A_in, B_in, acc_in);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── FP-mode check (4-cycle pipeline latency) ──────────────────────────────
    // Apply inputs after a posedge, then wait 4 more posedges for OUT_fp.
    task check_fp;
        input [15:0] A_in;
        input [15:0] B_in;
        input [31:0] acc_in;
        input [31:0] exp_out;
        input [7:0]  vec_id;
        begin
            @(posedge clk); #1;
            A = A_in; B = B_in; accumulator = acc_in; float_mode = 1'b1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            @(posedge clk); #1;   // OUT_fp valid
            if (OUT_fp === exp_out) begin
                $display("PASS  FP [%0d]  OUT_fp = %08h", vec_id, OUT_fp);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  FP [%0d]  OUT_fp = %08h  exp = %08h  (A=%04h B=%04h acc=%08h)",
                         vec_id, OUT_fp, exp_out, A_in, B_in, acc_in);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Main ──────────────────────────────────────────────────────────────────
    initial begin
        pass_count = 0;
        fail_count = 0;

        if (!$test$plusargs("no_vcd")) begin
            $dumpfile("dump_mac_top_standalone.vcd");
            $dumpvars(0, tb_mac_top_standalone);
        end

        // SDF back-annotation for post-PnR (compile with -DSDF_FILE=\"path/to.sdf\")
        `ifdef SDF_FILE
            $sdf_annotate(`SDF_FILE, dut);
        `endif

        $display("========================================");
        $display("  MAC Top — Standalone Verification");
        $display("========================================");

        do_reset;

        // ── FIX mode: INT8 x INT8 + INT32 → INT32 ────────────────────────────
        $display("--- FIX mode (3-reg-stage latency) ---");

        // Basic accumulation chain (acc = previous result)
        //  id   A       B       acc            expected        Ah*Bh + Al*Bl + acc
        check_fix(16'h0304, 16'h0506, 32'h00000000, 32'h00000027,  0); //  3* 5 + 4* 6 +   0 =  39
        check_fix(16'h0702, 16'h0403, 32'h00000027, 32'h00000049,  1); //  7* 4 + 2* 3 +  39 =  73
        check_fix(16'hFB08, 16'h02FD, 32'h00000049, 32'h00000027,  2); // -5* 2 + 8*-3 +  73 =  39
        check_fix(16'h0C05, 16'h0306, 32'h00000027, 32'h00000069,  3); // 12* 3 + 5* 6 +  39 = 105
        check_fix(16'h7F01, 16'h7F01, 32'h00000069, 32'h00003F6B,  4); // 127*127+ 1* 1 + 105 = 16235
        check_fix(16'h80FF, 16'h0101, 32'h00003F6B, 32'h00003EEA,  5); //-128* 1 +-1* 1 +16235= 16106

        // Edge cases
        check_fix(16'h0000, 16'h0000, 32'h00000000, 32'h00000000,  6); // all zeros
        check_fix(16'h0101, 16'h0101, 32'h00000000, 32'h00000002,  7); //  1* 1 + 1* 1 = 2
        check_fix(16'h7F7F, 16'h7F7F, 32'h00000000, 32'h00007E02,  8); // 127*127+127*127 = 32258
        // KNOWN BUG: merged_multiplier sign-extends the 16-bit product 0x8000
        // to 0xFFFF8000 instead of zero-extending to 0x00008000, so RTL returns
        // -32768 instead of +32768.
        check_fix(16'h8080, 16'h8080, 32'h00000000, 32'h00008000,  9); //-128*-128+-128*-128 = 32768
        check_fix(16'h7F80, 16'h0101, 32'h00000000, 32'hFFFFFFFF, 10); // 127*1 + -128*1 = -1

        // Negative accumulator
        check_fix(16'h0505, 16'h0505, 32'hFFFFFFEC, 32'h0000001E, 11); // 50 + (-20) = 30

        // Sign combinations
        check_fix(16'hF003, 16'h0204, 32'h00000000, 32'hFFFFFFEC, 12); // -16*2 + 3*4 = -20
        check_fix(16'h7F00, 16'h0103, 32'h00000000, 32'h0000007F, 13); // 127*1 + 0*3 = 127
        check_fix(16'h7F01, 16'h017F, 32'h00000000, 32'h000000FE, 14); // 127*1 + 1*127 = 254
        check_fix(16'h0101, 16'hFFFF, 32'h00000000, 32'hFFFFFFFE, 15); // 1*-1 + 1*-1 = -2
        check_fix(16'h0A14, 16'h0305, 32'h00000000, 32'h00000082, 16); // 10*3 + 20*5 = 130
        // Cancellation: equal magnitude pos+neg → 0 remainder, non-zero acc
        check_fix(16'hFC04, 16'h0404, 32'h00000064, 32'h00000064, 17); // -4*4+4*4+100 = 100

        // ── FP mode: FP16 x FP16 + FP32 → FP32 ──────────────────────────────
        $display("--- FP mode (4-reg-stage latency) ---");

        // KNOWN BUG: when acc=0 the FP accumulator path injects +8 ULP into
        // the result (mantissa bits [2:0] = 3'b001 instead of 0). Non-zero acc
        // cases are unaffected (see FP[2,3] which pass).
        // 1.0 * 1.0 + 0.0 = 1.0   (FP16: 1.0=0x3C00; FP32: 1.0=0x3F800000)
        check_fp(16'h3C00, 16'h3C00, 32'h00000000, 32'h3F800000,  0);

        // 2.0 * 2.0 + 0.0 = 4.0   (FP16: 2.0=0x4000; FP32: 4.0=0x40800000)
        check_fp(16'h4000, 16'h4000, 32'h00000000, 32'h40800000,  1);

        // 1.0 * 1.0 + 1.0 = 2.0   (FP32 acc 1.0=0x3F800000; result 2.0=0x40000000)
        check_fp(16'h3C00, 16'h3C00, 32'h3F800000, 32'h40000000,  2);

        // -1.0 * 2.0 + 4.0 = 2.0  (FP16: -1.0=0xBC00; acc 4.0=0x40800000)
        check_fp(16'hBC00, 16'h4000, 32'h40800000, 32'h40000000,  3);

        // KNOWN BUG: zero FP16 input (0x0000) produces a non-zero result
        // instead of 0.0 — the FP path does not short-circuit on zero inputs.
        // 0.0 * 1.0 + 0.0 = 0.0
        check_fp(16'h0000, 16'h3C00, 32'h00000000, 32'h00000000,  4);

        // Non-zero acc cases (unaffected by acc=0 bug)
        // 4.0 * 0.5 + 2.0 = 4.0   (FP16: 4.0=0x4400, 0.5=0x3800; FP32 acc 2.0=0x40000000)
        check_fp(16'h4400, 16'h3800, 32'h40000000, 32'h40800000,  5);
        // -2.0 * 3.0 + 10.0 = 4.0  (FP16: -2.0=0xC000, 3.0=0x4200; FP32 acc 10.0=0x41200000)
        check_fp(16'hC000, 16'h4200, 32'h41200000, 32'h40800000,  6);
        // 0.5 * 0.5 + 3.0 = 3.25  (FP16: 0.5=0x3800; FP32 acc 3.0=0x40400000; result=0x40500000)
        check_fp(16'h3800, 16'h3800, 32'h40400000, 32'h40500000,  7);

        // ── Summary ───────────────────────────────────────────────────────────
        $display("========================================");
        $display("  PASS: %0d   FAIL: %0d   TOTAL: %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: *** %0d TEST(S) FAILED ***", fail_count);
        $display("========================================");

        $finish;
    end

endmodule
