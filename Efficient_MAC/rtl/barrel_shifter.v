module barrel_shifter_58 (
    input  [57:0] data_in,
    input  [5:0]  shift_ctrl,
    output [57:0] data_out
);

    wire [57:0] s1, s2, s3, s4, s5;

    // Stage 1: Shift right by 1 bit if shift_ctrl[0] is 1
    assign s1 = shift_ctrl[0] ? {1'b0, data_in[57:1]} : data_in;

    // Stage 2: Shift right by 2 bits if shift_ctrl[1] is 1
    assign s2 = shift_ctrl[1] ? {2'b0, s1[57:2]} : s1;

    // Stage 3: Shift right by 4 bits if shift_ctrl[2] is 1
    assign s3 = shift_ctrl[2] ? {4'b0, s2[57:4]} : s2;

    // Stage 4: Shift right by 8 bits if shift_ctrl[3] is 1
    assign s4 = shift_ctrl[3] ? {8'b0, s3[57:8]} : s3;

    // Stage 5: Shift right by 16 bits if shift_ctrl[4] is 1
    assign s5 = shift_ctrl[4] ? {16'b0, s4[57:16]} : s4;

    // Stage 6: Shift right by 32 bits if shift_ctrl[5] is 1
    assign data_out = shift_ctrl[5] ? {32'b0, s5[57:32]} : s5;

endmodule
