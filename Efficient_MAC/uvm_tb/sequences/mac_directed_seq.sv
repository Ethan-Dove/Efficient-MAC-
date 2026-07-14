// Directed sequence: replicates all original tb_mac_top.v test vectors.
// Provides a baseline regression — these must pass before random tests run.
class mac_directed_seq extends mac_base_seq;
    `uvm_object_utils(mac_directed_seq)
    function new(string name = "mac_directed_seq");
        super.new(name);
    endfunction

    task body();
        mac_seq_item tx;

        // FIX: {Ah=10, Al=5} x {Bh=2, Bl=3} + 0 = 10*2 + 5*3 = 35
        `uvm_do_with(tx, { float_mode==0; A=={8'd10,8'd5}; B=={8'd2,8'd3}; accumulator==0; })

        // FIX: zero inputs
        `uvm_do_with(tx, { float_mode==0; A==0; B==0; accumulator==0; })

        // FIX: max positive x max positive (127*127 + 127*127 = 32258)
        `uvm_do_with(tx, { float_mode==0; A=={8'h7F,8'h7F}; B=={8'h7F,8'h7F}; accumulator==0; })

        // FIX: negative inputs (-2*-3 + -3*-2 = 12)
        `uvm_do_with(tx, { float_mode==0; A=={8'hFE,8'hFD}; B=={8'hFD,8'hFE}; accumulator==0; })

        // FIX: nonzero accumulator
        `uvm_do_with(tx, { float_mode==0; A=={8'd10,8'd5}; B=={8'd2,8'd3}; accumulator==32'd100; })

        // FLP: 1.0 * 1.0 + 1.0 = 2.0  (0x3C00 * 0x3C00 + 0x3F800000)
        `uvm_do_with(tx, { float_mode==1; A==16'h3C00; B==16'h3C00; accumulator==32'h3F800000; })

        // FLP: 2.0 * 3.0 + 4.0 = 10.0  (0x4000 * 0x4200 + 0x40800000)
        `uvm_do_with(tx, { float_mode==1; A==16'h4000; B==16'h4200; accumulator==32'h40800000; })

        // FLP: 0.5 * 0.5 + 0.0 = 0.25
        `uvm_do_with(tx, { float_mode==1; A==16'h3800; B==16'h3800; accumulator==0; })

        // FLP: -1.0 * 1.0 + 2.0 = 1.0  (subtraction path)
        `uvm_do_with(tx, { float_mode==1; A==16'hBC00; B==16'h3C00; accumulator==32'h40000000; })

        // FLP: zero accumulator
        `uvm_do_with(tx, { float_mode==1; A==16'h4000; B==16'h4000; accumulator==0; })
    endtask
endclass
