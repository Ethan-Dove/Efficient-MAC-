`timescale 1ns/1ps
// IN:  sum_vec  [31:0] — carry-save sum from csa_3_2
// IN:  carry_vec[31:0] — carry-save carry from csa_3_2
// IN:  cin      [1]    — carry-in from cin_gen (= eop_fp)
// OUT: cout     [1]    — carry out (end-around carry indicator)
// OUT: sum_low  [31:0] — resolved lower 32 bits of the 58-bit sum
module carry_propagate_adder(
    input  wire [31:0] sum_vec, carry_vec,
    input  wire        cin,
    output wire        cout,
    output wire [31:0] sum_low
);
    wire [32:0] res;
    assign res = sum_vec + carry_vec + cin;
    assign sum_low = res[31:0];
    assign cout    = res[32];
endmodule
