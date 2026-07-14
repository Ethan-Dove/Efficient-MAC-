// UVM transaction for mac_top.
// Stimulus fields are rand; response fields are filled by the monitor.
class mac_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mac_seq_item)

    // Stimulus
    rand logic [15:0] A, B;
    rand logic [31:0] accumulator;
    rand logic        float_mode;

    // Response (populated by monitor after pipeline latency)
    logic [31:0] out_fx;
    logic [31:0] out_fp;

    // ---- Constraints -------------------------------------------------------
    // In FLP mode, weight exponent distribution toward interesting regions:
    // 20% NaN/Inf (all-ones), 10% zero exp, 70% normal values.
    constraint c_fp_exp_a {
        float_mode -> A[14:10] dist {5'h1F := 20, 5'h0 := 10, [1:30] := 70};
    }
    constraint c_fp_exp_b {
        float_mode -> B[14:10] dist {5'h1F := 20, 5'h0 := 10, [1:30] := 70};
    }
    // Cover all four sign combinations equally in FLP mode.
    constraint c_sign_combos {
        float_mode -> (A[15] ^ B[15]) dist {1'b0 := 50, 1'b1 := 50};
    }
    // Hit zero accumulator 15% of the time.
    constraint c_acc_special {
        accumulator dist {32'd0 := 15, [1:'1] := 85};
    }

    function new(string name = "mac_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("mode=%s A=%04h B=%04h acc=%08h | fx=%08h fp=%08h",
            float_mode ? "FLP" : "FIX", A, B, accumulator, out_fx, out_fp);
    endfunction
endclass
