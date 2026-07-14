// Functional coverage subscriber. Receives transactions from the monitor
// and samples the covergroup. Target: 100% bins before synthesis sign-off.
class mac_coverage extends uvm_subscriber #(mac_seq_item);
    `uvm_component_utils(mac_coverage)

    mac_seq_item tx;

    covergroup mac_cg;
        // Mode
        mode_cp: coverpoint tx.float_mode {
            bins fix_mode = {1'b0};
            bins flp_mode = {1'b1};
        }
        // FP exponent of A (only meaningful in FLP mode, but tracked globally)
        fp_exp_a: coverpoint tx.A[14:10] {
            bins zero    = {5'h00};
            bins normal  = {[5'h01 : 5'h1E]};
            bins inf_nan = {5'h1F};
        }
        // FP exponent of B
        fp_exp_b: coverpoint tx.B[14:10] {
            bins zero    = {5'h00};
            bins normal  = {[5'h01 : 5'h1E]};
            bins inf_nan = {5'h1F};
        }
        // Sign combination of operands (determines add vs. subtract path in FLP)
        sign_combo: coverpoint {tx.A[15], tx.B[15]} {
            bins pp = {2'b00};
            bins pn = {2'b01};
            bins np = {2'b10};
            bins nn = {2'b11};
        }
        // Zero accumulator
        acc_zero: coverpoint (tx.accumulator == 32'd0) {
            bins is_zero  = {1'b1};
            bins nonzero  = {1'b0};
        }
        // Cross: all modes x all sign combos
        mode_x_sign:  cross mode_cp, sign_combo;
        // Cross: all modes x FP exponent regions
        mode_x_exp_a: cross mode_cp, fp_exp_a;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mac_cg = new();
    endfunction

    function void write(mac_seq_item t);
        tx = t;
        mac_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COVERAGE",
            $sformatf("Functional coverage: %.2f%%", mac_cg.get_coverage()), UVM_LOW)
    endfunction
endclass
