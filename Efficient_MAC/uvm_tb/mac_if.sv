`timescale 1ns/1ps
// SystemVerilog interface for mac_top. Used by driver (drives stimulus) and
// monitor (observes inputs and outputs).
interface mac_if (input logic clk);
    logic        rst_n;
    logic        float;
    logic [15:0] A, B;
    logic [31:0] accumulator;
    logic [31:0] OUT_fx;
    logic [31:0] OUT_fp;
endinterface
