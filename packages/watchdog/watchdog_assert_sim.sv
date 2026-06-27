// watchdog_assert_sim.sv
// Simulation assertion module for watchdog timer.
// Mirrors watchdog_assert_fml.sv but adds $error/$info action blocks and
// includes AST_WDT_FIRE_ON_TIMEOUT which uses a variable-bound repetition
// operator supported by most simulation tools.
// NOT intended for formal tools (variable repetition bounds are unsupported
// by most formal engines).

module watchdog_assert_sim
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
  // SAFETY ASSERTIONS (with $error action blocks)
  // -----------------------------------------------------------------------

  // AST_WDT_NO_FALSE_POSITIVE
  // The watchdog must never assert wdt_expired before the configured timeout
  // has elapsed (no spurious expiry).
  AST_WDT_NO_FALSE_POSITIVE: assert property (
    !false_positive
  ) else $error("[WDT] FALSE POSITIVE: wdt_expired asserted at time %0t but shadow_cnt=%0d < timeout_val=%0d",
                $time, shadow_cnt, wdt_timeout_val);

  // AST_WDT_NO_FALSE_NEGATIVE
  // Once the configured timeout has elapsed the watchdog must fire; it must
  // not silently fail to expire.
  AST_WDT_NO_FALSE_NEGATIVE: assert property (
    !false_negative
  ) else $error("[WDT] FALSE NEGATIVE: wdt_expired not asserted at time %0t but shadow_cnt=%0d >= timeout_val=%0d",
                $time, shadow_cnt, wdt_timeout_val);

  // AST_WDT_KICK_PREVENTS_EXPIRY
  // A kick on this cycle must prevent expiry on the very next cycle.
  AST_WDT_KICK_PREVENTS_EXPIRY: assert property (
    (wdt_kick && wdt_en) |=> !wdt_expired
  ) else $error("[WDT] KICK_PREVENTS_EXPIRY violated at time %0t: wdt_expired asserted cycle after wdt_kick",
                $time);

  // AST_WDT_DISABLED_NO_EXPIRY
  // When the watchdog is disabled it must never signal expiry.
  AST_WDT_DISABLED_NO_EXPIRY: assert property (
    !wdt_en |-> !wdt_expired
  ) else $error("[WDT] DISABLED_NO_EXPIRY violated at time %0t: wdt_expired asserted while wdt_en=0",
                $time);

  // AST_WDT_RESET_CLEARS
  // While reset is asserted the DUT must not signal expiry.
  AST_WDT_RESET_CLEARS: assert property (
    @(posedge clk) !rst_n |-> !wdt_expired
  ) else $error("[WDT] RESET_CLEARS violated at time %0t: wdt_expired asserted while rst_n=0",
                $time);

  // AST_WDT_ACK_CLEARS_EXPIRY
  // After the system acknowledges expiry, the DUT must deassert wdt_expired
  // on the next cycle.
  AST_WDT_ACK_CLEARS_EXPIRY: assert property (
    wdt_ack |=> !wdt_expired
  ) else $error("[WDT] ACK_CLEARS_EXPIRY violated at time %0t: wdt_expired still asserted cycle after wdt_ack",
                $time);

  // AST_WDT_FIRE_ON_TIMEOUT
  // If the watchdog is continuously enabled and never kicked for
  // wdt_timeout_val cycles, it must fire on the following cycle.
  // Uses a variable repetition count; supported by simulation tools but
  // not by most formal engines.
  //
  // The property reads:
  //   "wdt_en held throughout for wdt_timeout_val cycles, with no kick,
  //    implies wdt_expired must be high on the next cycle."
  //
  // Note: wdt_timeout_val is sampled at the start of the antecedent.
  AST_WDT_FIRE_ON_TIMEOUT: assert property (
    (wdt_en && !wdt_kick) [*wdt_timeout_val] |-> ##1 wdt_expired
  ) else $error("[WDT] FIRE_ON_TIMEOUT violated at time %0t: wdt_expired not asserted after %0d cycles with no kick",
                $time, wdt_timeout_val);

  // -----------------------------------------------------------------------
  // COVER POINTS (reachability, with $info action blocks)
  // -----------------------------------------------------------------------

  // COV_WDT_EXPIRED: expiry is reachable
  COV_WDT_EXPIRED: cover property (
    wdt_expired
  ) $info("[WDT] COV_WDT_EXPIRED reached at time %0t", $time);

  // COV_WDT_KICK_PREVENTS: kick followed by several non-expired cycles
  COV_WDT_KICK_PREVENTS: cover property (
    wdt_kick ##1 (!wdt_expired [*4])
  ) $info("[WDT] COV_WDT_KICK_PREVENTS reached at time %0t", $time);

  // COV_WDT_ENABLED: watchdog runs without expiry, counter advancing
  COV_WDT_ENABLED: cover property (
    wdt_en && !wdt_expired && (shadow_cnt > 0)
  ) $info("[WDT] COV_WDT_ENABLED reached at time %0t, shadow_cnt=%0d", $time, shadow_cnt);

  // COV_WDT_SHADOW_HALF: shadow counter reaches at least half of timeout
  COV_WDT_SHADOW_HALF: cover property (
    shadow_cnt >= (wdt_timeout_val >> 1)
  ) $info("[WDT] COV_WDT_SHADOW_HALF reached at time %0t, shadow_cnt=%0d timeout_val=%0d",
          $time, shadow_cnt, wdt_timeout_val);

  // COV_WDT_ACK: acknowledgement of expiry is reachable
  COV_WDT_ACK: cover property (
    wdt_ack
  ) $info("[WDT] COV_WDT_ACK reached at time %0t", $time);

  // -----------------------------------------------------------------------
  // ENVIRONMENT ASSUMPTIONS
  // (Kept as assume in simulation; tools such as Questa treat these as
  //  checker-mode filter assumptions or they can be converted to if-guards.)
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
