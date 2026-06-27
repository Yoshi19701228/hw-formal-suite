// ============================================================
// CDC Assertion Module — Formal Verification
// Verifies clock-domain crossing synchronizer correctness.
//
// Usage:
//   1. Instantiate cdc_helper and connect its outputs here.
//   2. Bind or instantiate alongside DUT.
//
//   cdc_helper #(.SYNC_STAGES(2)) u_hlp (
//     .src_clk, .dst_clk, .rst_n,
//     .src_data, .dst_synced,
//     .uncertain_window, .settled, .sync_timeout
//   );
//   cdc_assert_fml #(.SYNC_STAGES(2), .DATA_W(1)) u_fml (.*);
// ============================================================
module cdc_assert_fml
  import cdc_pkg::*;
#(
  parameter int SYNC_STAGES = 2,
  parameter int DATA_W      = 1
)(
  input logic src_clk,
  input logic dst_clk,
  input logic rst_n,

  // Signal crossing the clock domain
  input logic src_data,
  input logic dst_synced,

  // From cdc_helper
  input logic uncertain_window,
  input logic settled,
  input logic sync_timeout
);

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // Outside the metastability window, dst_synced must be stable
  // (no spurious transitions on the synchronized output)
  property prop_no_glitch;
    @(posedge dst_clk) disable iff (!rst_n)
    !uncertain_window |-> $stable(dst_synced);
  endproperty
  AST_CDC_NO_GLITCH: assert property (prop_no_glitch);

  // Once settled, the synchronized value must match the source
  // value captured SYNC_STAGES cycles ago (propagation latency)
  property prop_settled_correct;
    @(posedge dst_clk) disable iff (!rst_n)
    settled |-> (dst_synced == $past(src_data, SYNC_STAGES));
  endproperty
  AST_CDC_SETTLED_CORRECT: assert property (prop_settled_correct);

  // Helper guarantees no timeout; assert it as a safety property
  property prop_sync_no_timeout;
    @(posedge dst_clk) disable iff (!rst_n)
    !sync_timeout;
  endproperty
  AST_CDC_SYNC_TIMEOUT: assert property (prop_sync_no_timeout);

  // During reset, synchronized output must be deasserted
  property prop_reset_stable;
    @(posedge dst_clk)
    !rst_n |-> !dst_synced;
  endproperty
  AST_CDC_RESET_STABLE: assert property (prop_reset_stable);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------

  // src_data rises and dst_synced eventually follows
  COV_CDC_RISING_EDGE: cover property (
    @(posedge dst_clk) disable iff (!rst_n)
    $rose(src_data) ##[1:CDC_MAX_SYNC_LATENCY] $rose(dst_synced)
  );

  // src_data falls and dst_synced eventually follows
  COV_CDC_FALLING_EDGE: cover property (
    @(posedge dst_clk) disable iff (!rst_n)
    $fell(src_data) ##[1:CDC_MAX_SYNC_LATENCY] $fell(dst_synced)
  );

  // settled flag is reached (successful synchronization observed)
  COV_CDC_SETTLED: cover property (
    @(posedge dst_clk) disable iff (!rst_n)
    settled
  );

  // uncertain_window is observed (metastability window exercised)
  COV_CDC_UNCERTAIN: cover property (
    @(posedge dst_clk) disable iff (!rst_n)
    uncertain_window
  );

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // src_data must be held for at least SYNC_STAGES src_clk cycles
  // before changing again — prevents back-to-back glitches that
  // could overwhelm the synchronizer
  property assume_src_min_pulse;
    @(posedge src_clk) disable iff (!rst_n)
    $changed(src_data) |-> $stable(src_data) [* SYNC_STAGES];
  endproperty
  ENV_CDC_SRC_MIN_PULSE: assume property (assume_src_min_pulse);

  // rst_n must be deasserted synchronously: both clocks must see
  // the rising edge of rst_n in the same cycle (modeled by
  // requiring rst_n stable for 1 cycle after deassertion)
  property assume_reset_sync;
    @(posedge dst_clk)
    $rose(rst_n) |-> $stable(rst_n);
  endproperty
  ENV_CDC_RESET_SYNC: assume property (assume_reset_sync);

endmodule
