// Scoreboard with software reference model. Receives completed transactions
// from the monitor and checks DUT output against the expected result.
//
// FIX reference: OUT_fx = Ah*Bh + Al*Bl + accumulator (signed 32-bit).
// FLP reference: hp16(A) * hp16(B) + sp32(accumulator), 2-ULP tolerance.
class mac_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mac_scoreboard)

    uvm_analysis_imp #(mac_seq_item, mac_scoreboard) analysis_export;

    int pass_count, fail_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    function void write(mac_seq_item tx);
        if (!tx.float_mode) check_fix(tx);
        else                check_flp(tx);
    endfunction

    // ----- FIX reference model -----
    function void check_fix(mac_seq_item tx);
        logic [7:0]         Ah, Al, Bh, Bl;
        logic signed [31:0] p1, p2, expected;
        {Ah, Al} = tx.A;
        {Bh, Bl} = tx.B;
        // Explicit 32-bit sign extension before multiply (portable, no VCS casts)
        p1 = $signed({{24{Ah[7]}}, Ah}) * $signed({{24{Bh[7]}}, Bh});
        p2 = $signed({{24{Al[7]}}, Al}) * $signed({{24{Bl[7]}}, Bl});
        expected = p1 + p2 + $signed(tx.accumulator);
        if (tx.out_fx !== expected) begin
            `uvm_error("SB_FIX", $sformatf(
                "MISMATCH A=%04h B=%04h acc=%08h | got=%08h exp=%08h",
                tx.A, tx.B, tx.accumulator, tx.out_fx, expected))
            fail_count++;
        end else begin
            pass_count++;
            `uvm_info("SB_FIX", $sformatf("PASS %s", tx.convert2string()), UVM_HIGH)
        end
    endfunction

    // ----- FLP reference model -----
    function void check_flp(mac_seq_item tx);
        shortreal a_real, b_real, acc_real, result_ref;
        logic [31:0] ref_bits;
        a_real     = hp16_to_shortreal(tx.A);
        b_real     = hp16_to_shortreal(tx.B);
        acc_real   = $bitstoshortreal(tx.accumulator);
        result_ref = a_real * b_real + acc_real;
        ref_bits   = $shortrealtobits(result_ref);
        if (!within_ulp(tx.out_fp, ref_bits, 2)) begin
            `uvm_error("SB_FLP", $sformatf(
                "MISMATCH A=%04h B=%04h acc=%08h | got=%08h exp~%08h",
                tx.A, tx.B, tx.accumulator, tx.out_fp, ref_bits))
            fail_count++;
        end else begin
            pass_count++;
            `uvm_info("SB_FLP", $sformatf("PASS %s", tx.convert2string()), UVM_HIGH)
        end
    endfunction

    // Convert 16-bit half-precision to SystemVerilog shortreal (SP32).
    function shortreal hp16_to_shortreal(logic [15:0] hp);
        logic [31:0] sp_bits;
        logic [4:0]  exp_hp;
        exp_hp = hp[14:10];
        if (exp_hp == 5'd0 && hp[9:0] == 10'd0)
            sp_bits = {hp[15], 31'd0};                         // zero
        else if (exp_hp == 5'h1F)
            sp_bits = {hp[15], 8'hFF, 23'd0};                 // NaN / Inf
        else
            sp_bits = {hp[15], (8'(exp_hp) + 8'd112), hp[9:0], 13'd0}; // normal
        return $bitstoshortreal(sp_bits);
    endfunction

    // True if two FP32 bit patterns differ by at most n ULP.
    function bit within_ulp(logic [31:0] a, logic [31:0] b, int n);
        int diff;
        if (a == b) return 1;
        if (a[30:0] == 0 && b[30:0] == 0) return 1; // +0 vs -0
        diff = int'(a) - int'(b);
        if (diff < 0) diff = -diff;
        return (diff <= n);
    endfunction

    function void report_phase(uvm_phase phase);
        string res;
        res = (fail_count == 0) ? "PASS" : "FAIL";
        `uvm_info("SCOREBOARD", $sformatf("[%s] pass=%0d fail=%0d total=%0d",
            res, pass_count, fail_count, pass_count + fail_count), UVM_LOW)
        if (fail_count > 0)
            `uvm_error("SCOREBOARD", "One or more scoreboard checks failed")
    endfunction
endclass
