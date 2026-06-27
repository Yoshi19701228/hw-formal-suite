// arith_abstract.v
// Abstract arithmetic unit (multiplier / divider / MAC) for formal verification.
//
// The technique used here is an Uninterpreted Function (UF): the result is
// modeled as $anyseq (any value the tool chooses) EXCEPT for algebraically
// determined corner cases.  This is sound because:
//
//   - Formal tools prove "for all possible values of $anyseq".
//   - Corner-case constraints (a*0=0, 1*b=b, etc.) pin the UF at known
//     points, preventing vacuous proofs that rely on an absurd result.
//   - Properties about latency, valid/ready, and structural invariants
//     (e.g., "result width == 2*DATA_W") still hold because those do not
//     depend on the arithmetic value.
//
// Supported operations (compile-time parameter OP):
//   "MUL" (default): 2*DATA_W-bit product.  Corner cases: 0*x, x*0, 1*x, x*1.
//   "DIV":           quotient in lower DATA_W bits; remainder not modeled.
//                    Corner cases: x/1 = x, 0/x = 0, x/x = 1 (x != 0).
//   "MAC":           like MUL but with an accumulator input (not yet fully
//                    wired; see stub at bottom).
//
// Latency is abstracted to 1 cycle regardless of the real pipeline depth.
// If latency must be preserved, compose with pipeline_abstract.v.
//
// Verilog-2001 compatible.  $anyseq is a Jasper/Questa Formal extension.

`default_nettype none

module arith_abstract #(
    parameter DATA_W = 32,
    parameter OP     = "MUL"   // "MUL", "DIV", or "MAC"
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                valid_in,
    input  wire [DATA_W-1:0]   a,
    input  wire [DATA_W-1:0]   b,
    output reg                 valid_out,
    output reg  [2*DATA_W-1:0] result     // MUL: product; DIV: {remainder, quotient}
);

    // -------------------------------------------------------------------------
    // Uninterpreted result wire.
    // The formal tool may assign any value; we constrain it only where
    // algebraic identities give us a known answer.
    // -------------------------------------------------------------------------
    wire [2*DATA_W-1:0] uf_result;
    assign uf_result = $anyseq;

    // Zero-extended versions for identity comparisons
    wire [2*DATA_W-1:0] b_ext = {{DATA_W{1'b0}}, b};
    wire [2*DATA_W-1:0] a_ext = {{DATA_W{1'b0}}, a};
    wire [2*DATA_W-1:0] one   = {{(2*DATA_W-1){1'b0}}, 1'b1};

    // -------------------------------------------------------------------------
    // Registered pipeline: captures inputs for the latency-1 model.
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0] a_r, b_r;
    reg              valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r       <= {DATA_W{1'b0}};
            b_r       <= {DATA_W{1'b0}};
            valid_r   <= 1'b0;
            valid_out <= 1'b0;
            result    <= {(2*DATA_W){1'b0}};
        end else begin
            // Stage 1: register inputs
            a_r     <= a;
            b_r     <= b;
            valid_r <= valid_in;

            // Stage 2: output
            valid_out <= valid_r;

            if (valid_r) begin
                if (OP == "MUL") begin
                    // ---------------------------------------------------
                    // Multiplication corner cases
                    // ---------------------------------------------------
                    if ((a_r == {DATA_W{1'b0}}) || (b_r == {DATA_W{1'b0}}))
                        result <= {(2*DATA_W){1'b0}};          // a*0 = 0*b = 0
                    else if (a_r == {{(DATA_W-1){1'b0}}, 1'b1})
                        result <= {{DATA_W{1'b0}}, b_r};       // 1*b = b
                    else if (b_r == {{(DATA_W-1){1'b0}}, 1'b1})
                        result <= {{DATA_W{1'b0}}, a_r};       // a*1 = a
                    else
                        result <= uf_result;                   // UF: unconstrained

                end else if (OP == "DIV") begin
                    // ---------------------------------------------------
                    // Division corner cases (unsigned)
                    // ---------------------------------------------------
                    if (a_r == {DATA_W{1'b0}})
                        result <= {(2*DATA_W){1'b0}};          // 0/b = 0
                    else if (b_r == {{(DATA_W-1){1'b0}}, 1'b1})
                        result <= {{DATA_W{1'b0}}, a_r};       // a/1 = a
                    else if (a_r == b_r)
                        result <= {{DATA_W{1'b0}},             // a/a = 1 (a != 0)
                                   {{(DATA_W-1){1'b0}}, 1'b1}};
                    else
                        result <= uf_result;                   // UF: unconstrained

                end else begin
                    // ---------------------------------------------------
                    // MAC / default: treat as UF with no corner cases.
                    // Extend this branch with accumulator logic as needed.
                    // ---------------------------------------------------
                    result <= uf_result;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Formal assertions
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // ARITH_ABS_VALID_LATENCY: valid_out fires exactly 2 cycles after valid_in.
    ARITH_ABS_VALID_LATENCY: assert property (
        @(posedge clk) disable iff (!rst_n)
        valid_in |=> valid_r ##1 valid_out
    );

    // ARITH_ABS_MUL_ZERO_A: when a=0, result is 0.
    generate
        if (OP == "MUL") begin : gen_mul_checks
            ARITH_ABS_MUL_ZERO_A: assert property (
                @(posedge clk) disable iff (!rst_n)
                (valid_r && (a_r == {DATA_W{1'b0}}))
                |=> (result == {(2*DATA_W){1'b0}})
            );

            ARITH_ABS_MUL_ZERO_B: assert property (
                @(posedge clk) disable iff (!rst_n)
                (valid_r && (b_r == {DATA_W{1'b0}}))
                |=> (result == {(2*DATA_W){1'b0}})
            );

            ARITH_ABS_MUL_ONE_A: assert property (
                @(posedge clk) disable iff (!rst_n)
                (valid_r && (a_r == {{(DATA_W-1){1'b0}}, 1'b1}))
                |=> (result == {{DATA_W{1'b0}}, $past(b_r)})
            );

            ARITH_ABS_MUL_ONE_B: assert property (
                @(posedge clk) disable iff (!rst_n)
                (valid_r && (b_r == {{(DATA_W-1){1'b0}}, 1'b1}))
                |=> (result == {{DATA_W{1'b0}}, $past(a_r)})
            );
        end
    endgenerate
`endif

endmodule

`default_nettype wire
