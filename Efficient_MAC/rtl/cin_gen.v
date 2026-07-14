`timescale 1ns/1ps
// IN:  eop_fp  [1] — effective operation: 1=subtraction
// IN:  stk     [1] — alignment sticky bit from align_shifter
// IN:  comp    [1] — complement flag from align_shifter
// OUT: cin     [1] — carry-in to CPA: = eop_fp
// OUT: stk_add [1] — processed sticky for adder: comp ^ stk
module cin_gen(
    input  wire eop_fp, stk, comp,
    output wire cin, stk_add
);
    assign cin     = eop_fp;
    assign stk_add = comp ^ stk;
endmodule
