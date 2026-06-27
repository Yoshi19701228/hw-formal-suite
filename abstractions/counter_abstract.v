// counter_abstract.v
// Abstract wide counter for formal verification.
//
// The key insight: a 32-bit counter has 2^32 reachable states, causing
// state-space explosion in bounded model checking and making unbounded
// proofs intractable.  This abstraction starts the counter at $anyconst,
// which forces the formal tool to prove the property for ANY starting
// value rather than unrolling from 0.
//
// Soundness:
//   - Increment and clear behavior are modeled exactly.
//   - Because $anyconst covers every possible initial count, any invariant
//     proven here holds for the full counter lifecycle.
//   - Overflow detection is exact (count reaches all-ones while en=1).
//
// Limitations:
//   - This is a monotone up-counter.  For a down-counter or up/down
//     counter, extend the else-if chain and adjust overflow/underflow.
//   - The "initialized" flop adds one extra state but eliminates the need
//     for the tool to unroll from 0.
//
// Verilog-2001 compatible.

`default_nettype none

module counter_abstract #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,   // count enable (increment when 1)
    input  wire             clr,  // synchronous clear (takes priority over en)
    output reg  [WIDTH-1:0] count,
    output wire             overflow,   // high the cycle count wraps (up-counter)
    output wire             underflow   // always 0 for an up-counter
);

    // -------------------------------------------------------------------------
    // Symbolic initial value.
    // (* anyconst *) tells the tool this register holds a single arbitrary
    // but fixed value for the entire proof.  Equivalent to:
    //   wire [WIDTH-1:0] init_val = $anyconst;
    // -------------------------------------------------------------------------
    (* anyconst *) reg [WIDTH-1:0] init_val;

    // Tracks whether we have loaded the symbolic start state.
    reg initialized;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count       <= {WIDTH{1'b0}};
            initialized <= 1'b0;
        end else if (!initialized) begin
            // First active cycle: jump to the symbolic starting state.
            // This replaces the need to simulate all 2^WIDTH paths from 0.
            count       <= init_val;
            initialized <= 1'b1;
        end else begin
            if (clr)
                count <= {WIDTH{1'b0}};   // synchronous clear
            else if (en)
                count <= count + 1'b1;    // increment
        end
    end

    // -------------------------------------------------------------------------
    // Overflow: asserted the cycle BEFORE the wrap (i.e., while count is
    // all-ones and en would cause it to roll over to 0).
    // -------------------------------------------------------------------------
    assign overflow  = (count == {WIDTH{1'b1}}) && en && !clr;

    // Up-counter only — underflow is structurally impossible.
    assign underflow = 1'b0;

    // -------------------------------------------------------------------------
    // Formal assertions
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // CNTR_ABS_NO_WRAP_WHEN_CLR: clear prevents wrap.
    CNTR_ABS_NO_WRAP_WHEN_CLR: assert property (
        @(posedge clk) disable iff (!rst_n)
        (clr) |=> (count == {WIDTH{1'b0}})
    );

    // CNTR_ABS_INC: when running normally, count increments by 1.
    CNTR_ABS_INC: assert property (
        @(posedge clk) disable iff (!rst_n)
        (initialized && !clr && en && (count != {WIDTH{1'b1}}))
        |=> (count == ($past(count) + 1'b1))
    );

    // CNTR_ABS_STABLE: count does not change when neither en nor clr.
    CNTR_ABS_STABLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (initialized && !clr && !en)
        |=> (count == $past(count))
    );

    // CNTR_ABS_OVF_CONDITION: overflow is asserted exactly when count is max.
    CNTR_ABS_OVF_CONDITION: assert property (
        @(posedge clk) disable iff (!rst_n)
        overflow == ((count == {WIDTH{1'b1}}) && en && !clr)
    );
`endif

endmodule

`default_nettype wire
