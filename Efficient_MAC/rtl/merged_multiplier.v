
// ---------------------------------------------------------
// 4-bit Carry Look-Ahead Adder Block
// ---------------------------------------------------------
module cla_4bit(
    input [3:0] a, b,
    input cin,
    output [3:0] sum,
    output pg, // Block Propagate
    output gg  // Block Generate
);
    wire [3:0] p, g;
    wire [3:1] c;

    // Calculate individual propagate and generate
    assign p = a ^ b;
    assign g = a & b;

    // Calculate carries using look-ahead logic
    assign c[1] = g[0] | (p[0] & cin);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin);

    // Calculate sum
    assign sum[0] = p[0] ^ cin;
    assign sum[1] = p[1] ^ c[1];
    assign sum[2] = p[2] ^ c[2];
    assign sum[3] = p[3] ^ c[3];

    // Calculate block propagate and generate for the next hierarchical level
    assign pg = p[0] & p[1] & p[2] & p[3];
    assign gg = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);

endmodule

// ---------------------------------------------------------
// 16-bit Carry Look-Ahead Adder 
// ---------------------------------------------------------
module cla_16bit(
    input [15:0] A, B,
    input Cin,
    output [15:0] Sum,
    output Cout
);
    wire [3:0] P, G; // Block propagates and generates
    wire [4:0] C;    // Carries between the 4-bit blocks

    assign C[0] = Cin;

    // Look-Ahead Carry Unit (LCU) logic for the four 4-bit blocks
    assign C[1] = G[0] | (P[0] & C[0]);
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & C[0]);
    assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) | (P[2] & P[1] & P[0] & C[0]);
    assign C[4] = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]) | (P[3] & P[2] & P[1] & P[0] & C[0]);

    assign Cout = C[4];

    // Instantiate four 4-bit CLA blocks
    cla_4bit cla0 (
        .a(A[3:0]), .b(B[3:0]), .cin(C[0]), 
        .sum(Sum[3:0]), .pg(P[0]), .gg(G[0])
    );
    
    cla_4bit cla1 (
        .a(A[7:4]), .b(B[7:4]), .cin(C[1]), 
        .sum(Sum[7:4]), .pg(P[1]), .gg(G[1])
    );
    
    cla_4bit cla2 (
        .a(A[11:8]), .b(B[11:8]), .cin(C[2]), 
        .sum(Sum[11:8]), .pg(P[2]), .gg(G[2])
    );
    
    cla_4bit cla3 (
        .a(A[15:12]), .b(B[15:12]), .cin(C[3]), 
        .sum(Sum[15:12]), .pg(P[3]), .gg(G[3])
    );

endmodule

// ============================================================================
// 16-bit 4:2 Carry Save Adder
// ============================================================================
module csa_4to2_16bit (
    input  wire [15:0] in1,
    input  wire [15:0] in2,
    input  wire [15:0] in3,
    input  wire [15:0] in4,
    output wire [15:0] sum,
    output wire [15:0] carry
);
    wire [15:0] sum1   = in1 ^ in2 ^ in3;
    wire [15:0] carry1 = (in1 & in2) | (in2 & in3) | (in1 & in3);

    wire [15:0] carry1_shifted = carry1 << 1;

    wire [15:0] sum2   = sum1 ^ carry1_shifted ^ in4;
    wire [15:0] carry2 = (sum1 & carry1_shifted) | (carry1_shifted & in4) | (sum1 & in4);

    assign sum   = sum2;
    assign carry = carry2 << 1;
endmodule

// ============================================================================
// Special 16-bit 4:2 Carry Save Adder (Adds +2)
// ============================================================================
module csa_4to2_16bit_add2 (
  	input  wire float,
    input  wire [15:0] in1,
    input  wire [15:0] in2,
    input  wire [15:0] in3,
    input  wire [15:0] in4,
    output wire [15:0] sum,
    output wire [15:0] carry
);
    wire inject = float;
    wire [15:0] sum1   = in1 ^ in2 ^ in3;
    wire [15:0] carry1 = (in1 & in2) | (in2 & in3) | (in1 & in3);

    // Inject 1 into the LSB of the intermediate shifted carry (Adds +1)
  wire [15:0] carry1_shifted = {carry1[14:0], inject};

    wire [15:0] sum2   = sum1 ^ carry1_shifted ^ in4;
    wire [15:0] carry2 = (sum1 & carry1_shifted) | (carry1_shifted & in4) | (sum1 & in4);

    assign sum   = sum2;
    // Inject 1 into the LSB of the output shifted carry (Adds another +1, total +2)
  assign carry = {carry2[14:0], inject};
endmodule

// ============================================================================
// 32-bit 4:2 Carry Save Adder (For final assembly)
// ============================================================================
module csa_4to2_22bit (
  input  wire [21:0] in1,
  input  wire [21:0] in2,
  input  wire [21:0] in3,
  input  wire [21:0] in4,
  output wire [21:0] sum,
  output wire [21:0] carry
);
  wire [21:0] sum1   = in1 ^ in2 ^ in3;
  wire [21:0] carry1 = (in1 & in2) | (in2 & in3) | (in1 & in3);

  wire [21:0] carry1_shifted = carry1 << 1;

  wire [21:0] sum2   = sum1 ^ carry1_shifted ^ in4;
  wire [21:0] carry2 = (sum1 & carry1_shifted) | (carry1_shifted & in4) | (sum1 & in4);

    assign sum   = sum2;
    assign carry = carry2 << 1;
endmodule

// ============================================================================
// 8-bit Dual-Mode Booth Multiplier
// float = 1 -> Unsigned
// float = 0 -> Signed
// ============================================================================
module booth_multiplier_8x8_dual (
    input  wire [7:0] A,
    input  wire [7:0] B,
    input  wire       float,
    output wire [15:0] sum,
    output wire [15:0] carry
);
    wire [7:0] A_ext_bits = float ? 8'd0  : {8{A[7]}};
    wire [1:0] B_ext_bits = float ? 2'b00 : {2{B[7]}};

    wire [15:0] A_ext = {A_ext_bits, A};
    wire [10:0] B_pad = {B_ext_bits, B, 1'b0};

    wire [15:0] A_ext_x2     = A_ext << 1;
    wire [15:0] neg_A_ext    = ~A_ext + 16'd1;
    wire [15:0] neg_A_ext_x2 = ~(A_ext << 1) + 16'd1;

    reg [15:0] pp0, pp1, pp2, pp3, pp4;

    always @(*) begin
        case (B_pad[2:0])
            3'b001, 3'b010: pp0 = A_ext;
            3'b011:         pp0 = A_ext_x2;
            3'b100:         pp0 = neg_A_ext_x2;
            3'b101, 3'b110: pp0 = neg_A_ext;
            default:        pp0 = 16'd0;
        endcase
        case (B_pad[4:2])
            3'b001, 3'b010: pp1 = A_ext << 2;
            3'b011:         pp1 = A_ext_x2 << 2;
            3'b100:         pp1 = neg_A_ext_x2 << 2;
            3'b101, 3'b110: pp1 = neg_A_ext << 2;
            default:        pp1 = 16'd0;
        endcase
        case (B_pad[6:4])
            3'b001, 3'b010: pp2 = A_ext << 4;
            3'b011:         pp2 = A_ext_x2 << 4;
            3'b100:         pp2 = neg_A_ext_x2 << 4;
            3'b101, 3'b110: pp2 = neg_A_ext << 4;
            default:        pp2 = 16'd0;
        endcase
        case (B_pad[8:6])
            3'b001, 3'b010: pp3 = A_ext << 6;
            3'b011:         pp3 = A_ext_x2 << 6;
            3'b100:         pp3 = neg_A_ext_x2 << 6;
            3'b101, 3'b110: pp3 = neg_A_ext << 6;
            default:        pp3 = 16'd0;
        endcase
        case (B_pad[10:8])
            3'b001, 3'b010: pp4 = A_ext << 8;
            3'b011:         pp4 = A_ext_x2 << 8;
            3'b100:         pp4 = neg_A_ext_x2 << 8;
            3'b101, 3'b110: pp4 = neg_A_ext << 8;
            default:        pp4 = 16'd0;
        endcase
    end

    wire [15:0] csa1_sum   = pp0 ^ pp1 ^ pp2;
    wire [15:0] csa1_carry = (pp0 & pp1) | (pp1 & pp2) | (pp0 & pp2);

    wire [15:0] csa1_carry_shifted = csa1_carry << 1;
    wire [15:0] csa2_sum   = csa1_sum ^ csa1_carry_shifted ^ pp3;
    wire [15:0] csa2_carry = (csa1_sum & csa1_carry_shifted) | (csa1_carry_shifted & pp3) | (csa1_sum & pp3);

    wire [15:0] csa2_carry_shifted = csa2_carry << 1;
    wire [15:0] csa3_sum   = csa2_sum ^ csa2_carry_shifted ^ pp4;
    wire [15:0] csa3_carry = (csa2_sum & csa2_carry_shifted) | (csa2_carry_shifted & pp4) | (csa2_sum & pp4);

    assign sum   = csa3_sum;
    assign carry = csa3_carry << 1;
endmodule

// ============================================================================
// Modified Flawed 11-bit Karatsuba Multiplier (Sum Method)
// ============================================================================
module merged_multiplier (
    input  wire [10:0] X,
    input  wire [10:0] Y,
    input  wire        float,  // Controls multiplexer and mult_mid/mult_Z2 mode
    input  wire [7:0]  ext_A,  // External input A
    input  wire [7:0]  ext_B,  // External input B
    output wire [31:0] result
    //output wire [31:0] result_sum,
    //output wire [31:0] result_carry// Expanded to 32 bits for sign extension
);
    // 1. Decompose inputs
    wire [2:0] X1 = X[10:8];
    wire [7:0] X0 = X[7:0];
    
    wire [2:0] Y1 = Y[10:8];
    wire [7:0] Y0 = Y[7:0];

    // 2. Calculate Z0 (Upper product) in Carry-Save Format
    wire [5:0] pp0_z0 = {3'b000, X1 & {3{Y1[0]}}};
    wire [5:0] pp1_z0 = {2'b00, (X1 & {3{Y1[1]}}), 1'b0};
    wire [5:0] pp2_z0 = {1'b0,  (X1 & {3{Y1[2]}}), 2'b00};

    wire [5:0] Z0_sum_raw   = pp0_z0 ^ pp1_z0 ^ pp2_z0;
    wire [5:0] Z0_carry_raw = (pp0_z0 & pp1_z0) | (pp1_z0 & pp2_z0) | (pp0_z0 & pp2_z0);
    
    wire [5:0] Z0_sum   = Z0_sum_raw;
    wire [5:0] Z0_carry = Z0_carry_raw << 1;

    // 3. Calculate Z2 (Lower product)
    wire [15:0] Z2_sum, Z2_carry;
    booth_multiplier_8x8_dual mult_Z2 (
        .A(X0),
        .B(Y0),
        .float(float),
        .sum(Z2_sum),
        .carry(Z2_carry)
    );

    // 4. Calculate middle sums (X0 + X1) and (Y0 + Y1)
    // Note: This sum can technically be 9 bits. Truncating to 8 bits for the 8x8 multiplier
    // acts as the new intentional flaw in this architecture.
    wire [8:0] sum_X = X0 + {5'b00000, X1};
    wire [8:0] sum_Y = Y0 + {5'b00000, Y1};

    // 5. Multiplex inputs for the middle multiplier based on 'float'
    wire [7:0] mid_in_A = float ? sum_X[7:0] : ext_A;
    wire [7:0] mid_in_B = float ? sum_Y[7:0] : ext_B;

    // 6. Middle Multiplier: Calculates (X0+X1)*(Y0+Y1)
    wire [15:0] mid_sum, mid_carry;
    booth_multiplier_8x8_dual mult_mid (
        .A(mid_in_A),
        .B(mid_in_B),
        .float(float),
        .sum(mid_sum),
        .carry(mid_carry)
    );

    // 7. CSA Tree for Z1 Calculation
    // Mask Z0 to 0 when float == 0 to isolate the two 8-bit multiplications
    wire [5:0] Z0_sum_mux   = float ? Z0_sum : 6'd0;
    wire [5:0] Z0_carry_mux = float ? Z0_carry : 6'd0;

    // First 4:2 CSA: Adds Z0 (or 0), Z2_sum, Z2_carry
    // Output represents (Z0 + Z2)
    wire [15:0] csa1_sum, csa1_carry;
    csa_4to2_16bit csa_inst1 (
        .in1({10'd0, Z0_sum_mux}),
        .in2(Z2_sum),
        .in3(Z2_carry),
        .in4({10'd0, Z0_carry_mux}),
        .sum(csa1_sum),
        .carry(csa1_carry)
    );

    // To subtract (Z0 + Z2) from the middle product, we use two's complement: -A = ~A + 1
    // We invert the sum and carry vectors from the first CSA. 
    // (We will add the +2 later in the final addition stage)
    // If float=0 (isolated mode), we don't invert because we just want to add them.
    wire [15:0] csa1_sum_sub   = float ? ~csa1_sum   : csa1_sum;
    wire [15:0] csa1_carry_sub = float ? ~csa1_carry : csa1_carry;

    // Second 4:2 CSA: Adds mid_sum, mid_carry, and the inverted (Z0 + Z2)
    wire [15:0] Z1_sum, Z1_carry;
    csa_4to2_16bit_add2 csa_inst2 (
        .float(float),
        .in1(csa1_sum_sub),
        .in2(csa1_carry_sub),
        .in3(mid_sum),
        .in4(mid_carry),
        .sum(Z1_sum),
        .carry(Z1_carry)
    );

    // 8. Final Normal Addition
  wire [15:0] Z1_shifted_sum = float?  Z1_sum <<8 : Z1_sum;
  wire [15:0] Z1_shifted_carry = float? Z1_carry <<8 : Z1_carry;
  
 
  //test <- you lose info by doing shift. 
  //wire [15:0] Z1 = Z1_sum + Z1_carry; //Z1_shifted_sum + Z1_shifted_carry; //Z1_sum + Z1_carry;
  wire carry_out, carry_out_ext;
  wire [15:0] Z1;
  cla_16bit adder_16bit(Z1_sum, Z1_carry, 1'b0, Z1, carry_out);
  wire sum_carry_both_msb_one = Z1_sum[15] & Z1_carry[15];
  wire [15:0] sign_ext_carry = sum_carry_both_msb_one ? 16'b0 : {16{Z1_carry[15]}}; 
    
    wire [31:0] iso_sum   = {{16{Z1_sum[15]}}, Z1_sum};
    wire [31:0] iso_carry = {sign_ext_carry, Z1_carry};
    wire [31:0] ext_iso_sum = iso_sum + iso_carry;
  //cla_32bit adder_32bit(iso_sum, iso_carry, 1'b0, ext_iso_sum, carry_out_ext);
  
  //wire [31:0] result_isolated = iso_sum + iso_carry; 
  //end test
  
  
  	wire [15:0] Z2 = Z2_sum + Z2_carry;    
    wire [5:0]  Z0_resolved = Z0_sum + Z0_carry;

    // 9. Final Assembly & Multiplexing
    // Karatsuba result (float = 1)
    //wire [31:0] result_karatsuba = {10'd0, Z0_resolved, Z2} + {16'd0, Z1}; shifting left 8 bits and then zero extending loses data. 
    wire [31:0] result_karatsuba = {10'd0, Z0_resolved, Z2} + {8'd0, Z1,8'd0};
    // Isolated 8-bit sum result (float = 0), sign-extended to 32 bits
    wire [31:0] result_isolated = {{16{Z1[15]}}, Z1};

    assign result = float ? result_karatsuba : result_isolated; //<-working
    //assign result = float ? result_karatsuba : ext_iso_sum;
  	
endmodule
