// clkdiv_abstract.v
// Abstract clock divider for formal verification.
//
// Most formal tools (JasperGold, Questa Formal, SymbiYosys) do not support
// truly multi-clock designs: a second clock derived inside the DUT cannot be
// used as a formal clock edge.  This abstraction avoids the problem by
// replacing the divided clock with a clock-enable (clk_en) pulse in the
// source clock domain.
//
// Usage pattern:
//   Original:   always @(posedge clk_divided) begin ... end
//   Abstract:   always @(posedge clk) begin if (clk_en) begin ... end end
//
// The division ratio is modeled as $anyconst so the formal tool proves
// correctness for any ratio in [DIV_MIN, DIV_MAX] simultaneously.
//
// Preserved properties:
//   - clk_en fires exactly once every 'period' source-clock cycles.
//   - period is fixed for the entire proof (stable after reset).
//   - clk_out toggles at half the clk_en rate (for waveform visibility;
//     not used as a formal clock edge).
//
// Soundness:
//   - If downstream logic uses clk+clk_en instead of clk_divided, this
//     model is an exact representation of the divided-clock enable behavior.
//   - The actual duty cycle / rise-fall times of clk_divided are abstracted
//     away; only the enable-pulse timing is preserved.
//
// Verilog-2001 compatible.

`default_nettype none

module clkdiv_abstract #(
    parameter DIV_MIN = 2,
    parameter DIV_MAX = 16
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [$clog2(DIV_MAX):0]  div_ratio,  // configured ratio (for reference; formal uses period)
    output reg                       clk_en,     // 1-cycle enable pulse in clk domain
    output wire                      clk_out     // toggling output (simulation visibility only)
);

    // -------------------------------------------------------------------------
    // Symbolic period.
    // The formal tool fixes 'period' for the entire proof run.
    // The assume-property ENV_CLKDIV_RATIO_RANGE (in the assertion wrapper)
    // restricts it to [DIV_MIN, DIV_MAX].
    // -------------------------------------------------------------------------
    (* anyconst *) reg [$clog2(DIV_MAX):0] period;

    // -------------------------------------------------------------------------
    // Cycle counter: counts 0 .. period-1 then resets.
    // -------------------------------------------------------------------------
    reg [$clog2(DIV_MAX):0] cnt;

    // Phase register: toggles each time the counter resets.
    // Used to generate clk_out for simulation waveform inspection.
    reg clk_phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= {($clog2(DIV_MAX)+1){1'b0}};
            clk_en    <= 1'b0;
            clk_phase <= 1'b0;
        end else begin
            if (cnt >= period - 1'b1) begin
                // Counter has reached the end of the division period.
                cnt       <= {($clog2(DIV_MAX)+1){1'b0}};
                clk_en    <= 1'b1;        // fire the enable pulse
                clk_phase <= ~clk_phase;  // toggle output clock phase
            end else begin
                cnt    <= cnt + 1'b1;
                clk_en <= 1'b0;
            end
        end
    end

    // clk_out: for waveform visibility only.
    // DO NOT use as a formal clock; it is a reg driven by sequential logic
    // and formal tools cannot bind it as a clock edge.
    assign clk_out = clk_phase;

    // -------------------------------------------------------------------------
    // Formal assertions and environment assumptions
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // ENV_CLKDIV_RATIO_RANGE: period is within the configured [DIV_MIN, DIV_MAX].
    // Instantiate as "assume" in the assertion wrapper.
    ENV_CLKDIV_RATIO_RANGE: assume property (
        @(posedge clk)
        (period >= DIV_MIN[$clog2(DIV_MAX):0]) &&
        (period <= DIV_MAX[$clog2(DIV_MAX):0])
    );

    // ENV_CLKDIV_RATIO_STABLE: the division ratio does not change after reset.
    // A real clock divider has its ratio programmed once; model that here.
    ENV_CLKDIV_RATIO_STABLE: assume property (
        @(posedge clk) disable iff (!rst_n)
        $stable(period)
    );

    // CLKDIV_ABS_EN_PULSE_WIDTH: clk_en is only ever a single-cycle pulse.
    CLKDIV_ABS_EN_PULSE_WIDTH: assert property (
        @(posedge clk) disable iff (!rst_n)
        clk_en |=> !clk_en
    );

    // CLKDIV_ABS_CNT_BOUNDED: counter never exceeds period-1.
    CLKDIV_ABS_CNT_BOUNDED: assert property (
        @(posedge clk) disable iff (!rst_n)
        cnt < period
    );

    // CLKDIV_ABS_EN_AFTER_PERIOD: clk_en fires exactly when cnt wraps.
    // (clk_en was set last cycle when cnt was at period-1)
    CLKDIV_ABS_EN_AFTER_PERIOD: assert property (
        @(posedge clk) disable iff (!rst_n)
        clk_en |-> (cnt == {($clog2(DIV_MAX)+1){1'b0}})
    );
`endif

endmodule

`default_nettype wire
