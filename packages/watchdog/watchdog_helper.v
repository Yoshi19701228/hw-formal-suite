// watchdog_helper.v
// Formal/simulation verification helper for a watchdog timer.
// Maintains a shadow counter that mirrors what the DUT's internal counter
// should be doing, and derives three correctness flags:
//   true_timeout   - shadow counter has reached the configured timeout
//   false_positive - DUT fired before shadow counter reached timeout
//   false_negative - shadow counter reached timeout but DUT has not fired

module watchdog_helper #(
  parameter int CTR_W       = 16,
  parameter int MAX_TIMEOUT = 65536
) (
  input  wire              clk,
  input  wire              rst_n,

  // Watchdog configuration and control
  input  wire              wdt_en,                   // watchdog enable
  input  wire [CTR_W-1:0] wdt_timeout_val,           // configured timeout value
  input  wire              wdt_kick,                  // kick/refresh (active-high pulse)

  // DUT outputs
  input  wire              wdt_expired,               // DUT's expiry signal
  input  wire              wdt_ack,                   // system acknowledges expiry

  // Helper outputs
  output reg  [CTR_W-1:0] shadow_cnt,                // cycles since last kick
  output reg               true_timeout,              // shadow_cnt >= wdt_timeout_val
  output reg               false_positive,            // DUT fired too early
  output reg               false_negative             // DUT failed to fire in time
);

  // -----------------------------------------------------------------------
  // shadow_cnt
  // Increments every cycle while the watchdog is enabled.
  // Resets on kick, on disable, or on reset.
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shadow_cnt <= {CTR_W{1'b0}};
    end else if (!wdt_en || wdt_kick) begin
      shadow_cnt <= {CTR_W{1'b0}};
    end else begin
      // Saturate at MAX_TIMEOUT to avoid wrap-around
      if (shadow_cnt < wdt_timeout_val) begin
        shadow_cnt <= shadow_cnt + 1'b1;
      end
    end
  end

  // -----------------------------------------------------------------------
  // true_timeout: shadow counter has reached the configured timeout value.
  // Registered to align with DUT expiry (which is also registered).
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      true_timeout <= 1'b0;
    end else if (!wdt_en || wdt_kick) begin
      true_timeout <= 1'b0;
    end else begin
      true_timeout <= (shadow_cnt >= wdt_timeout_val);
    end
  end

  // -----------------------------------------------------------------------
  // false_positive: DUT asserted wdt_expired before the shadow counter
  // reached wdt_timeout_val.
  // Combinatorial; shadow_cnt < wdt_timeout_val means not yet timed out.
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      false_positive <= 1'b0;
    end else begin
      false_positive <= wdt_expired && (shadow_cnt < wdt_timeout_val) && wdt_en;
    end
  end

  // -----------------------------------------------------------------------
  // false_negative: one cycle after true_timeout was set, the DUT should
  // have asserted wdt_expired.  If it has not, that is a false negative.
  // Delayed by 1 cycle to give the DUT a clock edge to respond.
  // -----------------------------------------------------------------------
  reg true_timeout_d1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      true_timeout_d1 <= 1'b0;
      false_negative  <= 1'b0;
    end else begin
      true_timeout_d1 <= true_timeout;
      false_negative  <= true_timeout_d1 && !wdt_expired && wdt_en;
    end
  end

endmodule
