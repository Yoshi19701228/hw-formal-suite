// ============================================================
// CDC Assertion Module — Formal Verification
// Verifies clock-domain crossing synchronizer correctness.
//
// Usage (bind):
//   bind <dut_module> cdc_assert_fml #(.SYNC_STAGES(2), .DATA_W(1)) u_fml (.*);
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
  input logic dst_synced
);

  // ============================================================
  // [Helper Logic] — uncertainty window, settled detection,
  //   sync timeout counter
  //   (inlined from cdc_helper.v)
  // ============================================================

  // Source-domain: detect transitions on src_data
  reg  src_data_prev;
  reg  src_changed_pulse; // single src_clk pulse on change

  always @(posedge src_clk or negedge rst_n) begin
    if (!rst_n) begin
      src_data_prev    <= 1'b0;
      src_changed_pulse <= 1'b0;
    end else begin
      src_data_prev     <= src_data;
      src_changed_pulse <= (src_data != src_data_prev);
    end
  end

  // Transfer change flag to dst_clk domain via 2-FF sync
  reg change_sync1, change_sync2;

  always @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      change_sync1 <= 1'b0;
      change_sync2 <= 1'b0;
    end else begin
      change_sync1 <= src_changed_pulse;
      change_sync2 <= change_sync1;
    end
  end

  wire change_detected_dst = change_sync2;

  // Uncertainty window counter (dst_clk domain)
  localparam int CNT_W = $clog2(CDC_MAX_SYNC_LATENCY + SYNC_STAGES + 2);

  reg [CNT_W-1:0] unc_cnt;
  reg             uncertain_window;

  always @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      unc_cnt          <= '0;
      uncertain_window <= 1'b0;
    end else begin
      if (change_detected_dst) begin
        unc_cnt          <= SYNC_STAGES[CNT_W-1:0];
        uncertain_window <= 1'b1;
      end else if (unc_cnt != '0) begin
        unc_cnt          <= unc_cnt - 1;
        uncertain_window <= (unc_cnt > 1);
      end else begin
        uncertain_window <= 1'b0;
      end
    end
  end

  // Settled detection: dst_synced stable for SYNC_STAGES cycles
  reg [CNT_W-1:0] stable_cnt;
  reg             dst_synced_prev;
  reg             settled;

  always @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      stable_cnt     <= '0;
      dst_synced_prev <= 1'b0;
      settled        <= 1'b0;
    end else begin
      dst_synced_prev <= dst_synced;
      if (dst_synced != dst_synced_prev) begin
        stable_cnt <= '0;
        settled    <= 1'b0;
      end else if (stable_cnt < SYNC_STAGES[CNT_W-1:0]) begin
        stable_cnt <= stable_cnt + 1;
        settled    <= 1'b0;
      end else begin
        settled <= 1'b1;
      end
    end
  end

  // Sync timeout: dst_synced must settle within
  // CDC_MAX_SYNC_LATENCY dst_clk cycles after change detected
  reg [CNT_W-1:0] timeout_cnt;
  reg             timeout_active;
  reg             sync_timeout;

  always @(posedge dst_clk or negedge rst_n) begin
    if (!rst_n) begin
      timeout_cnt    <= '0;
      timeout_active <= 1'b0;
      sync_timeout   <= 1'b0;
    end else begin
      if (change_detected_dst && !settled) begin
        timeout_cnt    <= '0;
        timeout_active <= 1'b1;
        sync_timeout   <= 1'b0;
      end else if (settled) begin
        timeout_active <= 1'b0;
        timeout_cnt    <= '0;
        sync_timeout   <= 1'b0;
      end else if (timeout_active) begin
        if (timeout_cnt >= CDC_MAX_SYNC_LATENCY - 1) begin
          sync_timeout <= 1'b1;
        end else begin
          timeout_cnt  <= timeout_cnt + 1;
          sync_timeout <= 1'b0;
        end
      end
    end
  end

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
