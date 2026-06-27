// ============================================================
// Reset Sequencer Assertion Module — Formal Verification
//
// Usage:
//   1. Instantiate reset_helper and connect outputs to this module.
//   2. Bind or instantiate alongside DUT.
//
//   reset_helper     #(.N_DOMAINS(4), .MIN_PULSE(4), .MAX_PROP(8)) u_hlp (
//     .clk, .por_n, .rst_out, .chosen_domain,
//     .cnt_pulse, .pulse_too_short, .sr_por, .prop_timeout);
//   reset_assert_fml #(.N_DOMAINS(4), .MIN_PULSE(4), .MAX_PROP(8)) u_fml (.*);
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
  input logic [N_DOMAINS-1:0]         rst_out,
  // From reset_helper
  input logic [$clog2(N_DOMAINS)-1:0] chosen_domain,
  input logic                         pulse_too_short,
  input logic                         prop_timeout
);

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
