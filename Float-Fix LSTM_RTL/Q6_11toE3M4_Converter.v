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
