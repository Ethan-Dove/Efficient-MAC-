`timescale 1ns/1ps
// IN:  op1  [57:0] — {c_mix_r2[57:32], mul_result_r2}: upper accumulator + multiplier result
// IN:  op2  [57:0] — {26'd0, c_mix_r2[31:0]}: lower accumulator carry, upper bits zeroed
// OUT: count[5:0]  — predicted leading-zero count of the post-CPA sum
// OUT: valid[1]    — always 1
module lza_lzc(
    input  wire [57:0] op1, op2,
    output reg  [5:0]  count,
    output reg         valid
);
    // Leading Zero Anticipator (Zhang et al. §III-D).
    // Runs in parallel with the CPA in Stage 2.
    //
    // P/G/Z strings encode the bit-level carry structure of in1+in2:
    //   P[i] = in1[i] ^ in2[i]   (propagate)
    //   G[i] = in1[i] & in2[i]   (generate)
    //   Z[i] = ~(in1[i]|in2[i])  (zero)
    //
    // F string (one per sum-sign possibility):
    //   F_pos[i] = P[i] ^ Z[i+1]  — for sums whose MSB is 0 (no carry from top)
    //   F_neg[i] = P[i] ^ G[i+1]  — for sums whose MSB is 1 (carry from top)
    //
    // The highest set bit in F predicts the position of the leading 1 in the
    // sum; the prediction is guaranteed within ±1 bit (handled in
    // normalization_shifter with a 1-bit post-shift correction).
    //
    // valid=1 always: normalization_shifter applies the LZA count directly
    // (is_neg=0) or falls back to exact LZC (is_neg=1).


    wire [57:0] P, G, Z;
    wire [57:0] F_pos, F_neg, F;

    assign P = op1 ^ op2;
    assign G = op1 & op2;
    assign Z = ~(op1 | op2);

    assign F_pos[57] = P[57];
    assign F_neg[57] = P[57];

    genvar i;
    generate
        for (i = 0; i < 57; i = i + 1) begin : lza_gen
            assign F_pos[i] = P[i] ^ Z[i+1];
            assign F_neg[i] = P[i] ^ G[i+1];
        end
    endgenerate

    // Predict MSB of the sum to select the correct F string.
    wire sum_msb;
    assign sum_msb = op1[57] ^ op2[57];
    assign F = sum_msb ? F_neg : F_pos;

    // count = 60 - position_of_highest_set_bit_in_F  (= predicted LZC of sum).
    // Ascending loop: highest k that satisfies F[k]=1 wins (last assignment).
    integer k;
    always @(*) begin
        count = 6'd57;   // default: predict all-zero result
        valid = 1'b1;
        for (k = 0; k <= 57; k = k + 1)
            if (F[k])
                count = 57 - k;
    end
endmodule
