`timescale 1ns/1ps
// IN:  c_mix   [25:0] — upper 26 bits of c_mix_r2 [57:32], pre-computed for end-around carry
// OUT: inc_out [26:0] — c_mix + 1, selected by sum_high mux when cout=1
module incrementer(
    input  wire [25:0] c_mix,
    output wire [26:0] inc_out
);
    assign inc_out = {1'b0, c_mix} + 1'b1;
endmodule