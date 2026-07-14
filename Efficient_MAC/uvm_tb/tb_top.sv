`timescale 1ns/1ps

// UVM top-level testbench module.
// Includes all UVM TB files in dependency order, instantiates the DUT,
// connects it to the interface, and launches the selected test via run_test().
//
// Select test at runtime:  ./simv +UVM_TESTNAME=mac_directed_test
//                          ./simv +UVM_TESTNAME=mac_random_test +ntb_random_seed_automatic
//                          ./simv +UVM_TESTNAME=mac_corner_test

import uvm_pkg::*;
`include "uvm_macros.svh"

// Interface
`include "mac_if.sv"

// Sequence item
`include "seq_items/mac_seq_item.sv"

// Sequences (in dependency order)
`include "sequences/mac_base_seq.sv"
`include "sequences/mac_directed_seq.sv"
`include "sequences/mac_random_seq.sv"
`include "sequences/mac_corner_seq.sv"

// Agent components
`include "agent/mac_driver.sv"
`include "agent/mac_monitor.sv"
`include "agent/mac_agent.sv"

// Environment
`include "env/mac_scoreboard.sv"
`include "env/mac_coverage.sv"
`include "env/mac_env.sv"

// Tests
`include "tests/mac_base_test.sv"
`include "tests/mac_directed_test.sv"
`include "tests/mac_random_test.sv"
`include "tests/mac_corner_test.sv"

module tb_top;
    import uvm_pkg::*;

    // Clock
    logic clk;
    initial  clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // Interface instance
    mac_if dut_if (.clk(clk));

    // DUT
    mac_top dut (
        .clk        (clk),
        .rst_n      (dut_if.rst_n),
        .float      (dut_if.float),
        .A          (dut_if.A),
        .B          (dut_if.B),
        .accumulator(dut_if.accumulator),
        .OUT_fx     (dut_if.OUT_fx),
        .OUT_fp     (dut_if.OUT_fp)
    );

    initial begin
        // Make the virtual interface available to all UVM components
        uvm_config_db #(virtual mac_if)::set(null, "uvm_test_top.*", "mac_vif", dut_if);
        run_test();   // test name selected via +UVM_TESTNAME on command line
    end
endmodule
