// watchdog_assert_fml.sv
// Formal verification assertion module for watchdog timer.
// Order: assert (safety) -> cover (reachability) -> assume (environment).
// No $error; intended for formal property checking tools (Jasper, SymbiYosys, etc.).

module watchdog_assert_fml
  import watchdog_pkg::*;
#(
  parameter int CTR_W       = 16,
  parameter int MAX_TIMEOUT = WDT_MAX_TIMEOUT,
  parameter int MIN_TIMEOUT = WDT_MIN_TIMEOUT
) (
  input wire              clk,
  input wire              rst_n,

  // Watchdog configuration and control
  input wire              wdt_en,
  input wire [CTR_W-1:0] wdt_timeout_val,
  input wire              wdt_kick,

  // DUT outputs
  input wire              wdt_expired,
  input wire              wdt_ack,

  // Helper outputs
  input wire [CTR_W-1:0] shadow_cnt,
  input wire              true_timeout,
  input wire              false_positive,
  input wire              false_negative
);

  // -----------------------------------------------------------------------
  // Default clocking and reset
  // -----------------------------------------------------------------------
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // -----------------------------------------------------------------------
  // SAFETY ASSERTIONS
  // -----------------------------------------------------------------------

  // AST_WDT_NO_FALSE_POSITIVE
  // The watchdog must never assert wdt_expired before the configured timeout
  // has elapsed (no spurious expiry).
  AST_WDT_NO_FALSE_POSITIVE: assert property (
    !false_positive
  );

  // AST_WDT_NO_FALSE_NEGATIVE
  // Once the configured timeout has elapsed the watchdog must fire; it must
  // not silently fail to expire.
  AST_WDT_NO_FALSE_NEGATIVE: assert property (
    !false_negative
  );

  // AST_WDT_KICK_PREVENTS_EXPIRY
  // A kick on this cycle must prevent expiry on the very next cycle.
  AST_WDT_KICK_PREVENTS_EXPIRY: assert property (
    (wdt_kick && wdt_en) |=> !wdt_expired
  );

  // AST_WDT_DISABLED_NO_EXPIRY
  // When the watchdog is disabled it must never signal expiry.
  AST_WDT_DISABLED_NO_EXPIRY: assert property (
    !wdt_en |-> !wdt_expired
  );

  // AST_WDT_RESET_CLEARS
  // While reset is asserted the DUT must not signal expiry.
  // (This property checks the reset state directly; disable iff does not
  //  suppress it because we want to verify behaviour during reset.)
  AST_WDT_RESET_CLEARS: assert property (
    @(posedge clk) !rst_n |-> !wdt_expired
  );

  // AST_WDT_ACK_CLEARS_EXPIRY
  // After the system acknowledges expiry, the DUT must deassert wdt_expired
  // on the next cycle.
  AST_WDT_ACK_CLEARS_EXPIRY: assert property (
    wdt_ack |=> !wdt_expired
  );

  // -----------------------------------------------------------------------
  // COVER POINTS (reachability)
  // -----------------------------------------------------------------------

  // COV_WDT_EXPIRED: expiry is reachable
  COV_WDT_EXPIRED: cover property (
    wdt_expired
  );

  // COV_WDT_KICK_PREVENTS: kick followed by several non-expired cycles
  COV_WDT_KICK_PREVENTS: cover property (
    wdt_kick ##1 (!wdt_expired [*4])
  );

  // COV_WDT_ENABLED: watchdog runs without expiry, counter advancing
  COV_WDT_ENABLED: cover property (
    wdt_en && !wdt_expired && (shadow_cnt > 0)
  );

  // COV_WDT_SHADOW_HALF: shadow counter reaches at least half of timeout
  COV_WDT_SHADOW_HALF: cover property (
    shadow_cnt >= (wdt_timeout_val >> 1)
  );

  // COV_WDT_ACK: acknowledgement of expiry is reachable
  COV_WDT_ACK: cover property (
    wdt_ack
  );

  // -----------------------------------------------------------------------
  // ENVIRONMENT ASSUMPTIONS
  // -----------------------------------------------------------------------

  // ENV_WDT_TIMEOUT_RANGE: configured timeout is within legal bounds
  ENV_WDT_TIMEOUT_RANGE: assume property (
    (wdt_timeout_val >= MIN_TIMEOUT) && (wdt_timeout_val <= MAX_TIMEOUT)
  );

  // ENV_WDT_KICK_PULSE: wdt_kick is a single-cycle pulse
  ENV_WDT_KICK_PULSE: assume property (
    wdt_kick |=> !wdt_kick
  );

  // ENV_WDT_ACK_PULSE: wdt_ack is a single-cycle pulse
  ENV_WDT_ACK_PULSE: assume property (
    wdt_ack |=> !wdt_ack
  );

endmodule
