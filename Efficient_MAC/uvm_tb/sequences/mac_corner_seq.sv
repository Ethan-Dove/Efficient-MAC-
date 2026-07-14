// Corner-case sequence targeting pipeline edge cases and FP special values.
class mac_corner_seq extends mac_base_seq;
    `uvm_object_utils(mac_corner_seq)
    function new(string name = "mac_corner_seq");
        super.new(name);
    endfunction

    task body();
        mac_seq_item tx;

        // --- FLP corner cases ---
        // Zero product
        `uvm_do_with(tx, { float_mode==1; A==16'h0000; B==16'h0000; accumulator==0; })
        // One operand zero
        `uvm_do_with(tx, { float_mode==1; A==16'h3C00; B==16'h0000; accumulator==0; })
        // NaN/Inf exponent (all-ones exp field)
        `uvm_do_with(tx, { float_mode==1; A[14:10]==5'h1F; B==16'h3C00; accumulator==0; })
        // Near-max values
        `uvm_do_with(tx, { float_mode==1; A==16'h7BFF; B==16'h7BFF; accumulator==0; })
        // Subtraction: positive product, negative accumulator
        `uvm_do_with(tx, { float_mode==1; A==16'h4000; B==16'h3C00; accumulator==32'hBF800000; })
        // Subtraction: negative product, positive accumulator
        `uvm_do_with(tx, { float_mode==1; A==16'hC000; B==16'h3C00; accumulator==32'h3F800000; })
        // Both operands negative (positive product)
        `uvm_do_with(tx, { float_mode==1; A==16'hBC00; B==16'hBC00; accumulator==0; })
        // Max accumulator
        `uvm_do_with(tx, { float_mode==1; A==16'h3C00; B==16'h3C00; accumulator==32'h7F7FFFFF; })

        // --- FIX corner cases ---
        // Max positive x max positive
        `uvm_do_with(tx, { float_mode==0; A=={8'h7F,8'h7F}; B=={8'h7F,8'h7F}; accumulator==0; })
        // Max negative x max negative
        `uvm_do_with(tx, { float_mode==0; A=={8'h80,8'h80}; B=={8'h80,8'h80}; accumulator==0; })
        // Max positive x max negative
        `uvm_do_with(tx, { float_mode==0; A=={8'h7F,8'h7F}; B=={8'h80,8'h80}; accumulator==0; })
        // Nonzero accumulator, overflow-prone
        `uvm_do_with(tx, { float_mode==0; A=={8'h7F,8'h7F}; B=={8'h7F,8'h7F}; accumulator==32'h7FFFFFFF; })
        // Alternating sign bytes
        `uvm_do_with(tx, { float_mode==0; A=={8'h7F,8'h80}; B=={8'h80,8'h7F}; accumulator==0; })

        // 200 random FLP transactions constrained to normal exponent range only
        repeat (200) begin
            tx = mac_seq_item::type_id::create("corner_rand");
            start_item(tx);
            if (!tx.randomize() with {
                float_mode == 1'b1;
                A[14:10] inside {[1:28]};
                B[14:10] inside {[1:28]};
            })
                `uvm_fatal("RAND_FAIL", "corner FLP randomization failed")
            finish_item(tx);
        end

        // 200 random FIX transactions
        repeat (200) begin
            tx = mac_seq_item::type_id::create("fix_rand");
            start_item(tx);
            if (!tx.randomize() with { float_mode == 1'b0; })
                `uvm_fatal("RAND_FAIL", "corner FIX randomization failed")
            finish_item(tx);
        end
    endtask
endclass
