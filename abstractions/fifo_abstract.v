// fifo_abstract.v
// Abstract FIFO model for formal verification.
//
// Tracks occupancy count, full, empty, almost_full, and almost_empty
// signals with full precision.  The actual data payload is abstracted
// away: rdata is $anyseq when the FIFO is non-empty, giving the formal
// tool freedom to choose any value (over-approximation).
//
// Soundness:
//   - All flow-control signals (full, empty, count) are exact.
//   - Data ordering is NOT modeled; use this abstraction only when you
//     need to verify handshake logic, not payload correctness.
//   - rdata stability: the output does not change unless a pop occurs,
//     which is enforced by the assertion FIFO_ABS_RDATA_STABLE.
//
// Overflow / underflow protection:
//   The abstract model asserts that the environment never pushes into a
//   full FIFO or pops from an empty one.  Wire these as assumptions in
//   the assertion wrapper if the DUT has its own back-pressure logic.
//
// Verilog-2001 compatible.  $anyseq is a Jasper/Questa Formal
// extension.

`default_nettype none

module fifo_abstract #(
    parameter DEPTH  = 16,
    parameter DATA_W = 32
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               push,
    input  wire               pop,
    input  wire [DATA_W-1:0]  wdata,       // write data (payload abstracted away)
    output reg  [DATA_W-1:0]  rdata,
    output wire [$clog2(DEPTH):0] count,   // current occupancy (0..DEPTH)
    output wire               full,
    output wire               empty,
    output wire               almost_full, // count >= DEPTH-1
    output wire               almost_empty // count <= 1
);

    // -------------------------------------------------------------------------
    // Internal count register
    // -------------------------------------------------------------------------
    reg [$clog2(DEPTH):0] count_r;

    // Gate pushes/pops against full/empty to avoid illegal transitions
    wire push_ok = push && !full;
    wire pop_ok  = pop  && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count_r <= {($clog2(DEPTH)+1){1'b0}};
        else if ( push_ok && !pop_ok)
            count_r <= count_r + 1'b1;
        else if (!push_ok &&  pop_ok)
            count_r <= count_r - 1'b1;
        // simultaneous push+pop: count unchanged
    end

    // -------------------------------------------------------------------------
    // Combinational status flags
    // -------------------------------------------------------------------------
    assign count        = count_r;
    assign full         = (count_r == DEPTH[($clog2(DEPTH)):0]);
    assign empty        = (count_r == {($clog2(DEPTH)+1){1'b0}});
    assign almost_full  = (count_r >= (DEPTH - 1));
    assign almost_empty = (count_r <= 1);

    // -------------------------------------------------------------------------
    // Abstract read data
    // Data content is unconstrained ($anyseq) when FIFO is non-empty.
    // When empty, output 0 (the real FIFO would have undefined / stale data,
    // but 0 is a safe concrete value for the abstract model).
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= {DATA_W{1'b0}};
        end else begin
            if (pop_ok)
                rdata <= (count_r > 1) ? $anyseq : {DATA_W{1'b0}};
            // When !pop_ok: rdata holds its value (stability guarantee)
        end
    end

    // -------------------------------------------------------------------------
    // Formal assertions
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // FIFO_ABS_NO_OVF: environment must not push into a full FIFO.
    FIFO_ABS_NO_OVF: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(push && full)
    );

    // FIFO_ABS_NO_UDF: environment must not pop from an empty FIFO.
    FIFO_ABS_NO_UDF: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(pop && empty)
    );

    // FIFO_ABS_COUNT_MAX: occupancy never exceeds DEPTH.
    FIFO_ABS_COUNT_MAX: assert property (
        @(posedge clk) disable iff (!rst_n)
        count_r <= DEPTH[($clog2(DEPTH)):0]
    );

    // FIFO_ABS_RDATA_STABLE: rdata does not change unless a pop occurs.
    FIFO_ABS_RDATA_STABLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!pop_ok) |=> ($stable(rdata))
    );

    // FIFO_ABS_FULL_EMPTY_MUTEX: full and empty are mutually exclusive
    // (only possible when DEPTH == 0, which is illegal).
    FIFO_ABS_FULL_EMPTY_MUTEX: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(full && empty)
    );
`endif

endmodule

`default_nettype wire
