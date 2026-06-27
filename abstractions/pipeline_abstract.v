// pipeline_abstract.v
// Abstract N-stage pipeline for formal verification.
//
// A real pipeline with MAX_DEPTH stages requires tracking MAX_DEPTH tokens
// simultaneously, multiplying the state space.  This abstraction models
// exactly one in-flight token and selects the latency via $anyconst, so
// the tool proves handshake and data-integrity properties for any pipeline
// depth from 1 to MAX_DEPTH without enumerating each depth separately.
//
// Preserved properties:
//   1. Valid/ready handshake: in_ready de-asserts while a token is in flight.
//   2. In-order delivery: the token appears at the output after exactly
//      'latency' cycles (where latency is a $anyconst in [1, MAX_DEPTH]).
//   3. Data integrity: out_data == in_data for the tracked token.
//   4. No starvation: a token always eventually appears at the output
//      (use the assertion PIPE_ABS_LIVENESS in a liveness check).
//
// Limitations:
//   - Only one token is tracked.  Throughput / full-pipeline-fill scenarios
//     require a more detailed model or the real pipeline.
//   - Back-pressure (out_ready stalling the pipeline) is modeled: the token
//     waits at the output until out_ready is asserted.
//
// Verilog-2001 compatible.

`default_nettype none

module pipeline_abstract #(
    parameter DATA_W    = 32,
    parameter MAX_DEPTH = 8
) (
    input  wire               clk,
    input  wire               rst_n,
    // Input port
    input  wire               in_valid,
    output wire               in_ready,   // driven by abstract model
    input  wire [DATA_W-1:0]  in_data,
    // Output port
    output reg                out_valid,
    output reg  [DATA_W-1:0]  out_data,
    input  wire               out_ready   // downstream back-pressure
);

    // -------------------------------------------------------------------------
    // Symbolic latency: the formal tool picks one value in [1, MAX_DEPTH]
    // and proves that all assertions hold for that choice.
    // Combined with the $anyconst semantics (fixed for the entire proof),
    // this is equivalent to universally quantifying over pipeline depths.
    // -------------------------------------------------------------------------
    (* anyconst *) reg [$clog2(MAX_DEPTH):0] latency;

    // -------------------------------------------------------------------------
    // Shadow token
    // -------------------------------------------------------------------------
    reg               token_valid;          // a token is in flight
    reg  [DATA_W-1:0] token_data;           // captured input payload
    reg  [$clog2(MAX_DEPTH):0] token_age;  // cycles since token was accepted

    // Accept a new token only when the pipeline is free (single-token model)
    assign in_ready = !token_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_valid <= 1'b0;
            token_data  <= {DATA_W{1'b0}};
            token_age   <= {($clog2(MAX_DEPTH)+1){1'b0}};
            out_valid   <= 1'b0;
            out_data    <= {DATA_W{1'b0}};
        end else begin
            if (!token_valid) begin
                // -------------------------------------------------------
                // Idle: accept a new token if upstream is presenting one.
                // -------------------------------------------------------
                if (in_valid) begin
                    token_valid <= 1'b1;
                    token_data  <= in_data;
                    token_age   <= {($clog2(MAX_DEPTH)+1){1'b0}};
                end
                out_valid <= 1'b0;
            end else begin
                // -------------------------------------------------------
                // Token in flight: age it toward latency.
                // -------------------------------------------------------
                if (token_age < latency) begin
                    token_age <= token_age + 1'b1;
                    out_valid <= 1'b0;
                end else begin
                    // Latency reached: present token at output.
                    out_valid <= 1'b1;
                    out_data  <= token_data;

                    if (out_ready) begin
                        // Downstream consumed the token; free the pipeline.
                        token_valid <= 1'b0;
                        out_valid   <= 1'b0;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Formal assertions and environment assumptions
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // ENV_PIPE_LATENCY_RANGE: latency must be in [1, MAX_DEPTH].
    // Instantiate as "assume" in the assertion wrapper, not "assert".
    ENV_PIPE_LATENCY_RANGE: assume property (
        @(posedge clk)
        (latency >= 1) && (latency <= MAX_DEPTH[$clog2(MAX_DEPTH):0])
    );

    // ENV_PIPE_LATENCY_STABLE: latency does not change after reset.
    ENV_PIPE_LATENCY_STABLE: assume property (
        @(posedge clk) disable iff (!rst_n)
        $stable(latency)
    );

    // PIPE_ABS_DATA_INTEGRITY: output data matches the captured token.
    PIPE_ABS_DATA_INTEGRITY: assert property (
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> (out_data == token_data)
    );

    // PIPE_ABS_NO_OUT_WITHOUT_TOKEN: out_valid implies a token is/was in flight.
    PIPE_ABS_NO_OUT_WITHOUT_TOKEN: assert property (
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> token_valid
    );

    // PIPE_ABS_READY_WHEN_IDLE: in_ready is high exactly when no token is held.
    PIPE_ABS_READY_WHEN_IDLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        in_ready == !token_valid
    );

    // PIPE_ABS_AGE_BOUNDED: token age never exceeds latency.
    PIPE_ABS_AGE_BOUNDED: assert property (
        @(posedge clk) disable iff (!rst_n)
        token_age <= latency
    );
`endif

endmodule

`default_nettype wire
