//=================================================================
//  LSTM Cell with LFP MAC
//  - Inputs / states : Q6.11
//  - Weights         : E3M4
//  - Biases          : Q6.11
//  - Activations     : LUT-based (unchanged)
//=================================================================

module lstm_cell_q6_11 #(
    parameter WIDTH = 18,
    parameter FRAC  = 11
)(
    input  wire                     clk,
    input  wire                     rst,

    input  wire signed [WIDTH-1:0]  x_t,
    input  wire signed [WIDTH-1:0]  c_prev,
    input  wire signed [WIDTH-1:0]  h_prev,

    // -------- E3M4 weights --------
    input  wire [7:0]  W_fx, W_fh,
    input  wire [7:0]  W_ix, W_ih,
    input  wire [7:0]  W_gx, W_gh,
    input  wire [7:0]  W_ox, W_oh,

    // -------- Q6.11 biases --------
    input  wire signed [WIDTH-1:0]  b_f,
    input  wire signed [WIDTH-1:0]  b_i,
    input  wire signed [WIDTH-1:0]  b_g,
    input  wire signed [WIDTH-1:0]  b_o,

    output reg  signed [WIDTH-1:0]  c_t,
    output reg  signed [WIDTH-1:0]  h_t
);

    // =============================================================
    // 1) Gate pre-activations using LFP MAC
    // =============================================================

    wire signed [WIDTH-1:0] f_mac;
    wire signed [WIDTH-1:0] i_mac;
    wire signed [WIDTH-1:0] g_mac;
    wire signed [WIDTH-1:0] o_mac;

    lfp_mac_top_q6_11 u_mac_f (
        .in0_q   (x_t),
        .in1_q   (h_prev),
        .weight1 (W_fx),
        .weight2 (W_fh),
        .out_q   (f_mac)
    );

    lfp_mac_top_q6_11 u_mac_i (
        .in0_q   (x_t),
        .in1_q   (h_prev),
        .weight1 (W_ix),
        .weight2 (W_ih),
        .out_q   (i_mac)
    );

    lfp_mac_top_q6_11 u_mac_g (
        .in0_q   (x_t),
        .in1_q   (h_prev),
        .weight1 (W_gx),
        .weight2 (W_gh),
        .out_q   (g_mac)
    );

    lfp_mac_top_q6_11 u_mac_o (
        .in0_q   (x_t),
        .in1_q   (h_prev),
        .weight1 (W_ox),
        .weight2 (W_oh),
        .out_q   (o_mac)
    );

    // Add bias (Q6.11, unchanged)
    wire signed [WIDTH-1:0] f_pre = f_mac + b_f;
    wire signed [WIDTH-1:0] i_pre = i_mac + b_i;
    wire signed [WIDTH-1:0] g_pre = g_mac + b_g;
    wire signed [WIDTH-1:0] o_pre = o_mac + b_o;

    // =============================================================
    // 2) Activations (UNCHANGED)
    // =============================================================

    wire signed [WIDTH-1:0] f_gate;
    wire signed [WIDTH-1:0] i_gate;
    wire signed [WIDTH-1:0] g_gate;
    wire signed [WIDTH-1:0] o_gate;

    sigmoid_q6_11 u_sig_f (.x(f_pre), .y(f_gate));
    sigmoid_q6_11 u_sig_i (.x(i_pre), .y(i_gate));
    sigmoid_q6_11 u_sig_o (.x(o_pre), .y(o_gate));
    tanh_q6_11    u_tanh_g(.x(g_pre), .y(g_gate));

    // =============================================================
    // 3) Cell update: C_t = f*C_prev + i*g   (Q6.11)
    // =============================================================

    wire signed [2*WIDTH-1:0] fC_mul = f_gate * c_prev;
    wire signed [2*WIDTH-1:0] iG_mul = i_gate * g_gate;

    wire signed [WIDTH-1:0] c_new =
        (fC_mul >>> FRAC) + (iG_mul >>> FRAC);

    // =============================================================
    // 4) Hidden state: h_t = o * tanh(C_t)
    // =============================================================

    wire signed [WIDTH-1:0] c_tanh;
    tanh_q6_11 u_tanh_c (.x(c_new), .y(c_tanh));

    wire signed [2*WIDTH-1:0] oC_mul = o_gate * c_tanh;
    wire signed [WIDTH-1:0]   h_new  = oC_mul >>> FRAC;

    // =============================================================
    // 5) Registers
    // =============================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            c_t <= 18'b0;
            h_t <= 18'b0;
        end else begin
            c_t <= c_new;
            h_t <= h_new;
        end
    end

endmodule

/*module sigmoid_lut_wrapper (
    input  wire signed [17:0] x,   // Q6.11
    output wire signed [17:0] y
);
    // LUT range: [-6, +6] → 14-bit index
    wire [13:0] addr;

    assign addr =
        (x <= -18'sd12288) ? 14'd0 :
        (x >=  18'sd12288) ? 14'd16383 :
        (x + 18'sd12288) >>> 1;

    sigmoid_lut lut (
        .addr(addr),
        .y(y)
    );
endmodule
module tanh_lut_wrapper (
    input  wire signed [17:0] x,   // Q6.11
    output wire signed [17:0] y
);
    // LUT range: [-3, +3] → 13-bit index
    wire [12:0] addr;

    assign addr =
        (x <= -18'sd6144) ? 13'd0 :
        (x >=  18'sd6144) ? 13'd8191 :
        (x + 18'sd6144) >>> 1;

    tanh_lut lut (
        .addr(addr),
        .y(y)
    );
endmodule
//===========================================================
// Sigmoid LUT ROM
// addr : 14-bit unsigned
// y    : Q6.11 signed
//===========================================================
module sigmoid_lut (
    input  wire [13:0] addr,
    output reg  signed [17:0] y
);

    // 16384-entry ROM
    reg signed [17:0] rom [0:16383];

    initial begin
        $readmemh("sigmoid_lut.hex", rom);
    end

    always @(*) begin
        y = rom[addr];
    end

endmodule
//===========================================================
// Tanh LUT ROM
// addr : 13-bit unsigned
// y    : Q6.11 signed
//===========================================================
module tanh_lut (
    input  wire [12:0] addr,
    output reg  signed [17:0] y
);

    // 8192-entry ROM
    reg signed [17:0] rom [0:8191];

    initial begin
        $readmemh("tanh_lut.hex", rom);
    end

    always @(*) begin
        y = rom[addr];
    end

endmodule*/
module lfp_mac_top_q6_11 (
    input  signed [17:0] in0_q,   // Input 0 (Q6.11)
    input  signed [17:0] in1_q,   // Input 1 (Q6.11)
    input  [7:0] weight1,
    input  [7:0] weight2,
    output signed [17:0] out_q    // Output (Q6.11)
);

    // -------------------------------------------------
    // Wires
    // -------------------------------------------------

    // Q6.11 -> E3M4
    wire [7:0] in0_e3m4;
    wire [7:0] in1_e3m4;

    // LFP multiplier outputs (E4M4)
    wire [8:0] mul0_e4m4;
    wire [8:0] mul1_e4m4;

    // E4M4 -> Q6.11
    wire signed [17:0] mul0_q;
    wire signed [17:0] mul1_q;
    // -------------------------------------------------
    // Q6.11 → E3M4 converters
    // -------------------------------------------------
    Q6_11toE3M4_Converter u_q_to_e3m4_0 (
        .q  (in0_q),
        .fp (in0_e3m4)
    );

    Q6_11toE3M4_Converter u_q_to_e3m4_1 (
        .q  (in1_q),
        .fp (in1_e3m4)
    );

    // -------------------------------------------------
    // LFP E3M4 multipliers
    // -------------------------------------------------
    lfp_mult_e3m4_fig3 u_mul0 (
        .x1 (in0_e3m4),
        .x2 (weight1),
        .y  (mul0_e4m4)
    );

    lfp_mult_e3m4_fig3 u_mul1 (
        .x1 (in1_e3m4),
        .x2 (weight2),
        .y  (mul1_e4m4)
    );

    // -------------------------------------------------
    // E4M4 → Q6.11 converters
    // -------------------------------------------------
    E4M4_9b_to_Q6_11 u_e4m4_to_q_0 (
        .fp (mul0_e4m4),
        .q  (mul0_q)
    );

    E4M4_9b_to_Q6_11 u_e4m4_to_q_1 (
        .fp (mul1_e4m4),
        .q  (mul1_q)
    );

    // -------------------------------------------------
    // Adder (Q6.11)
    // -------------------------------------------------
    assign out_q = mul0_q + mul1_q;

endmodule
/*

module lfp_mac_top_q6_11 (
    input  signed [17:0] in0_q,    // Data Input 0 (Q6.11)
    input  signed [17:0] in1_q,    // Data Input 1 (Q6.11)
    input  [7:0]         w0_e3m4,  // Weight 0 (Direct E3M4) - NEW
    input  [7:0]         w1_e3m4,  // Weight 1 (Direct E3M4) - NEW
    output signed [17:0] out_q     // Output (Q6.11)
);

    // -------------------------------------------------
    // Wires
    // -------------------------------------------------

    // Data paths: Q6.11 -> E3M4
    wire [7:0] in0_e3m4;
    wire [7:0] in1_e3m4;

    // LFP multiplier outputs (E4M4)
    wire [8:0] mul0_e4m4;
    wire [8:0] mul1_e4m4;

    // Converted multiplier outputs (Q6.11)
    wire signed [17:0] mul0_q;
    wire signed [17:0] mul1_q;

    // -------------------------------------------------
    // Data Converters (Q6.11 → E3M4)
    // -------------------------------------------------
    // Weights are already E3M4, so no converters needed for them.
    
    Q6_11toE3M4_Converter u_q_to_e3m4_0 (
        .q  (in0_q),
        .fp (in0_e3m4)
    );

    Q6_11toE3M4_Converter u_q_to_e3m4_1 (
        .q  (in1_q),
        .fp (in1_e3m4)
    );

    // -------------------------------------------------
    // LFP Multipliers (E3M4 x E3M4 -> E4M4)
    // -------------------------------------------------
    lfp_mult_e3m4_fig3 u_mul0 (
        .x1 (in0_e3m4),
        .x2 (w0_e3m4),   // Directly connected to input port
        .y  (mul0_e4m4)
    );

    lfp_mult_e3m4_fig3 u_mul1 (
        .x1 (in1_e3m4),
        .x2 (w1_e3m4),   // Directly connected to input port
        .y  (mul1_e4m4)
    );

    // -------------------------------------------------
    // Result Converters (E4M4 → Q6.11)
    // -------------------------------------------------
    E4M4_9b_to_Q6_11 u_e4m4_to_q_0 (
        .fp (mul0_e4m4),
        .q  (mul0_q)
    );

    E4M4_9b_to_Q6_11 u_e4m4_to_q_1 (
        .fp (mul1_e4m4),
        .q  (mul1_q)
    );

    // -------------------------------------------------
    // Final Adder (Q6.11)
    // -------------------------------------------------
    assign out_q = mul0_q + mul1_q;

endmodule*/
module Q6_11toE3M4_Converter (
    input  wire signed [17:0] q,     // Q6.11
    output reg         [7:0]  fp      // {sign, exp[2:0], mant[3:0]}
);

    // --------------------------------------------------
    // Internal signals
    // --------------------------------------------------
    reg        sign;
    reg [17:0] abs_q;

    reg [2:0]  exp;
    reg [17:0] norm;
    reg [4:0]  mant;                  // extra bit for rounding

    // --------------------------------------------------
    // Cheap clamp detection (bias = 4)
    // Valid MSB range: 8 .. 14
    // --------------------------------------------------
    wire underflow = ~|abs_q[14:8];    // < 2^-3  → zero
    wire overflow  =  |abs_q[17:15];   // > max   → saturate

    // --------------------------------------------------
    // Combinational logic
    // --------------------------------------------------
    always @(*) begin
        // defaults
        fp    = 8'b0;
        sign  = q[17];
        abs_q = sign ? -q : q;

        // -------------------------------
        // Clamp logic
        // -------------------------------
        if (abs_q == 18'd0 || underflow) begin
            // zero / underflow
            fp = 8'b0;
        end
        else if (overflow) begin
            // saturation
            fp = {sign, 3'b111, 4'b1111};
        end
        else begin
            // -------------------------------
            // Exponent decode (direct)
            // bias = 4 → exp = MSB - 7
            // -------------------------------
            if      (abs_q[14]) exp = 3'd7;
            else if (abs_q[13]) exp = 3'd6;
            else if (abs_q[12]) exp = 3'd5;
            else if (abs_q[11]) exp = 3'd4;
            else if (abs_q[10]) exp = 3'd3;
            else if (abs_q[9])  exp = 3'd2;
            else                exp = 3'd1;   // abs_q[8]

            // -------------------------------
            // Mantissa normalization
            // MSB index = exp + 7
            // -------------------------------
            norm = abs_q << (17 - (exp + 7));

            // mantissa + rounding bit
            mant = norm[16:13];   // 1.MMMM + round

            /*// round-to-nearest
            if (norm[12])
                mant = mant + 1'b1;

            // mantissa overflow → renormalize
            if (mant == 5'b10000) begin
                mant = 4'b0000;  // 1.0000
                exp  = exp + 1'b1;
            end*/

            // re-check overflow after rounding
            if (exp > 3'd7)
                fp = {sign, 3'b111, 4'b1111};
            else
                fp = {sign, exp, mant[3:0]};
        end
    end

endmodule
module sigmoid_q6_11 (
    input  signed [17:0] x,
    output reg signed [17:0] y
);

    localparam signed [17:0] Q6 = 18'sd12288;  // 6.0
    localparam signed [17:0] Q1 = 18'sd2048;   // 1.0

    wire sign = x[17];
    wire signed [17:0] x_abs = sign ? -x : x;

    wire signed [17:0] sig_lut_out;

    sigmoid_lut lut (
        .addr(x_abs),
        .y(sig_lut_out)
    );

    always @(*) begin
        // ---- HARD SATURATION FIRST ----
        if (x <= -Q6)
            y = 18'sd0;
        else if (x >= Q6)
            y = Q1;
        // ---- LUT REGION ONLY ----
        else if (sign)
            y = Q1 - sig_lut_out;
        else
            y = sig_lut_out;
    end

endmodule


module sigmoid_lut (
    input  [17:0] addr,
    output reg signed [17:0] y
);

    reg signed [17:0] rom [0:383];
    wire [8:0] raw_index;
    wire [8:0] index;

    assign raw_index = addr >> 5;
    assign index = (raw_index > 9'd383) ? 9'd383 : raw_index;

    initial begin
        $readmemh("sigmoid_lut.mem", rom);
    end

    always @(*) begin
        y = rom[index];
    end

endmodule
module lfp_mult_e3m4_fig3 (
    input  wire [7:0] x1,   // E3M4
    input  wire [7:0] x2,   // E3M4
    output wire [8:0] y     // E4M4 (sign + 4-bit exp + 4-bit man)
);
    // -------------------------------
    // Field extraction
    // -------------------------------
    wire s1 = x1[7];
    wire s2 = x2[7];
    wire sy = s1 ^ s2;

  wire [6:0] p1 = x1[6:0];
  wire [6:0] p2 = x2[6:0];

    

    // -------------------------------
    // Log converters
    // -------------------------------
    wire v1, v2;
  lfp_log4 log1 (.x(x1[3:0]), .v(v1));
  lfp_log4 log2 (.x(x2[3:0]), .v(v2));

    // -------------------------------
    // Core adder (Point A in Fig. 3)
    // y_a[7:0] = x1[6:0] + x2[6:0] + v1 + v2
    // -------------------------------
    wire [7:0] y_a;
  assign y_a = p1 + p2 + v1 + v2 ;

    // -------------------------------
    // Antilog (right block in Fig. 3)
    // -------------------------------
    wire v_out;
  lfp_antilog4 antilog (.x(y_a[3:0]), .v(v_out));

  wire [3:0] m_out = y_a[3:0] - v_out;

    // -------------------------------
    // Zero handling (as per paper)
    // -------------------------------
    assign y = (x1[6:4] == 0 || x2[6:4] == 0) ? 9'b0 :
               {sy, y_a[7:4], m_out};

endmodule
// Code your design here
module lfp_antilog4 (
    input  wire [3:0] x,
    output wire       v
);
  wire vbar = ((~x[3] & ~x[2] & ~x[1]) | ( x[3] &  x[2] &  x[1] & x[0]));
  assign v = ~vbar;

// x − 1 if Eq.3.3 is FALSE
endmodule

module lfp_log4 (
    input  wire [3:0] x,
    output wire       v
);
    // Eq. (3.3)
   // Eq. (3.3)
  wire vbar = ((~x[3] & ~x[2] & ~x[1]) | ( x[3] &  x[2] &  x[1] & x[0]));
  assign v = ~vbar;

// x + 1 if Eq.3.3 is FALSE
endmodule
module tanh_q6_11 (
    input  signed [17:0] x,
    output reg signed [17:0] y
);

    localparam signed [17:0] Q025 = 18'sd512;    // 0.25
    localparam signed [17:0] Q3   = 18'sd6144;   // 3.0
    localparam signed [17:0] Q1   = 18'sd2048;   // 1.0

    wire sign = x[17];
    wire signed [17:0] x_abs = sign ? -x : x;

    // LUT output
    wire signed [17:0] tanh_lut_out;

    // LUT instance (defined later)
    tanh_lut lut (
        .addr(x_abs),
        .y(tanh_lut_out)
    );

    always @(*) begin
        if (sign) begin
            // tanh(-x) = -tanh(x)
            if (x_abs < Q025)
                y = -x_abs;
            else if (x_abs < Q3)
                y = -tanh_lut_out;
            else
                y = -Q1;
        end else begin
            if (x < Q025)
                y = x;
            else if (x < Q3)
                y = tanh_lut_out;
            else
                y = Q1;
        end
    end

endmodule
module tanh_lut (
    input  [17:0] addr,     // Q6.11 input
    output reg signed [17:0] y
);

    reg signed [17:0] rom [0:351];

    initial begin
        $readmemh("tanh_lut.mem", rom);
    end

    wire [8:0] index;
    assign index = (addr - 18'sd512) >> 4; // Δ = 1/128 → shift by 4

    always @(*) begin
        y = rom[index];
    end
endmodule
module E4M4_9b_to_Q6_11 (
    input  [8:0] fp,              // fp[8]=S, fp[7:4]=E, fp[3:0]=M
    output reg signed [17:0] q     // Q6.11
);

    reg sign;
    reg [3:0] exp;
    reg [4:0] mant;                // (1.M) * 2^4
    integer shift;
    reg signed [17:0] tmp = 17'd0;

    always @(*) begin
        // default
        q = 18'sd0;

        sign = fp[8];
        exp  = fp[7:4];

        // -----------------------------
        // Zero / underflow
        // -----------------------------
        if (exp == 0) begin
            q = 18'sd0;
        end
        else begin
            // -----------------------------
            // Compute shift = E - 1
            // -----------------------------
            shift = exp - 8 ;

            // -----------------------------
            // Underflow (shift < 0)
            // -----------------------------
// Scale
tmp [17:0] = {6'd0,1'b1, fp[3:0],7'd0};
if ((shift ) >= 0)
    tmp = tmp <<< (shift );
else
begin
    tmp = tmp >>> (-(shift ));
                // -----------------------------
                // Mantissa = (1.M) * 2^4
                // -----------------------------
                

                // -----------------------------
                // Scale
                // -----------------------------
                

                // -----------------------------
                // Apply sign
                // -----------------------------
end
                if (sign)
                    tmp = -tmp;

                // -----------------------------
                // Saturation
                // -----------------------------
                
                    q = tmp[17:0];
            end
        end
   
endmodule
