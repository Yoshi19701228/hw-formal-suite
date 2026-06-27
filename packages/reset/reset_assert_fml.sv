// ============================================================
// Reset Sequencer Assertion Module — Formal Verification
//
// Usage (bind):
//   bind <dut_module> reset_assert_fml #(.N_DOMAINS(4), .MIN_PULSE(4), .MAX_PROP(8)) u_fml (.*);
// ============================================================
module reset_assert_fml
  import reset_pkg::*;
#(
  parameter int N_DOMAINS = 4,
  parameter int MIN_PULSE = RESET_MIN_PULSE_CYCLES,
  parameter int MAX_PROP  = RESET_MAX_PROP_CYCLES
)(
  input logic                         clk,
  input logic                         por_n,
  input logic [N_DOMAINS-1:0]         rst_out
);

  // ============================================================
  // [Helper Logic] — chosen_domain selection, pulse counter,
  //   shift register, and propagation timeout
  //   (inlined from reset_helper.v)
  // ============================================================

  // Non-deterministic domain selection — held constant by formal engine
  (* anyconst *) reg [$clog2(N_DOMAINS)-1:0] chosen_domain_r;
  wire [$clog2(N_DOMAINS)-1:0] chosen_domain = chosen_domain_r;

  // Pulse-width counter for the chosen domain
  // Increments while rst_out[chosen_domain] is asserted (high)
  reg  [$clog2(MIN_PULSE+1)-1:0] cnt_pulse;
  reg                             pulse_too_short;

  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      cnt_pulse     <= {($clog2(MIN_PULSE+1)){1'b0}};
      pulse_too_short <= 1'b0;
    end else begin
      if (rst_out[chosen_domain_r]) begin
        if (cnt_pulse < MIN_PULSE)
          cnt_pulse <= cnt_pulse + 1;
      end else begin
        // Detect falling edge of chosen domain reset
        pulse_too_short <= (cnt_pulse < MIN_PULSE) && (cnt_pulse != 0);
        cnt_pulse       <= {($clog2(MIN_PULSE+1)){1'b0}};
      end
    end
  end

  // Shift register: tracks how long ago por_n deasserted
  // sr_por[0] = !por_n one cycle ago, sr_por[MAX_PROP-1] = MAX_PROP cycles ago
  reg  [MAX_PROP-1:0] sr_por;

  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      sr_por <= {MAX_PROP{1'b0}};
    end else begin
      sr_por <= {sr_por[MAX_PROP-2:0], !por_n};
    end
  end

  // prop_timeout: por_n has been high (deasserted) for at least MAX_PROP cycles
  // but chosen_domain reset is still asserted — DUT is too slow to release it
  reg  prop_timeout;

  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      prop_timeout <= 1'b0;
    end else begin
      prop_timeout <= sr_por[MAX_PROP-1] && rst_out[chosen_domain_r];
    end
  end

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // While POR is active (por_n low), all domain resets must be asserted
  property prop_por_asserts_all;
    @(posedge clk)
    !por_n |-> &rst_out;
  endproperty
  AST_RESET_POR_ASSERTS_ALL: assert property (prop_por_asserts_all);

  // No domain reset may be released before MIN_PULSE cycles of assertion
  property prop_min_pulse;
    @(posedge clk)
    !pulse_too_short;
  endproperty
  AST_RESET_MIN_PULSE: assert property (prop_min_pulse);

  // All domain resets must deassert within MAX_PROP cycles of por_n deassertion
  property prop_prop_timeout;
    @(posedge clk)
    !prop_timeout;
  endproperty
  AST_RESET_PROP_TIMEOUT: assert property (prop_prop_timeout);

  // Once reset rises it must stay high for at least one more cycle (no single-cycle glitch)
  property prop_no_glitch;
    @(posedge clk) disable iff (!por_n)
    $rose(rst_out[chosen_domain]) |=> rst_out[chosen_domain];
  endproperty
  AST_RESET_NO_GLITCH: assert property (prop_no_glitch);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------

  // Chosen domain enters reset
  COV_RESET_CHOSEN_ASSERTED:
    cover property (@(posedge clk) rst_out[chosen_domain]);

  // Chosen domain exits reset (falling edge)
  COV_RESET_CHOSEN_DEASSERTED:
    cover property (@(posedge clk) !rst_out[chosen_domain] && $past(rst_out[chosen_domain]));

  // All domains in reset simultaneously
  COV_RESET_ALL_ASSERTED:
    cover property (@(posedge clk) &rst_out);

  // All domains out of reset simultaneously
  COV_RESET_ALL_DEASSERTED:
    cover property (@(posedge clk) !(|rst_out));

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // chosen_domain is a valid domain index
  property assume_chosen_valid;
    @(posedge clk)
    chosen_domain < N_DOMAINS;
  endproperty
  ENV_RESET_CHOSEN_VALID: assume property (assume_chosen_valid);

  // POR must be held low for at least MIN_PULSE cycles when asserted
  property assume_por_min_width;
    @(posedge clk)
    $fell(por_n) |-> !por_n [*MIN_PULSE];
  endproperty
  ENV_RESET_POR_MIN_WIDTH: assume property (assume_por_min_width);

endmodule
