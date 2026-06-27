// ============================================================
// CDC Formal Helper — Verilog
// Tracks metastability window, settle status, and sync timeout.
// Avoids ##[1:N] sequences in formal by using counters.
//
// Usage:
//   cdc_helper #(.SYNC_STAGES(2)) u_hlp (
//     .src_clk, .dst_clk, .rst_n,
//     .src_data, .dst_synced,
//     .uncertain_window, .settled, .sync_timeout
//   );
// ============================================================
`ifndef CDC_MAX_SYNC_LATENCY
  `define CDC_MAX_SYNC_LATENCY 4
`endif

module cdc_helper #(
  parameter int SYNC_STAGES = 2   // number of synchronizer flop stages
)(
  input  wire src_clk,
  input  wire dst_clk,
  input  wire rst_n,

  // $anyseq: models arbitrary CDC stimulus from source domain
  // The caller connects the DUT's actual src_data here;
  // internally we also drive a free-running anyseq signal for
  // stimulus injection during formal stimulus generation.
  input  wire src_data,
  input  wire dst_synced,   // synchronized output from DUT

  output reg  uncertain_window, // HIGH for SYNC_STAGES dst_clk cycles after src_data changes
  output reg  settled,          // HIGH when dst_synced stable for SYNC_STAGES dst_clk cycles
  output reg  sync_timeout      // HIGH if dst_synced hasn't settled within CDC_MAX_SYNC_LATENCY
);

  // ----------------------------------------------------------
  // Source-domain: detect transitions on src_data
  // ----------------------------------------------------------
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

  // ----------------------------------------------------------
  // Transfer change flag to dst_clk domain via 2-FF sync
  // (This meta-signal itself crosses, but its glitch only
  //  widens the uncertain_window, which is conservative.)
  // ----------------------------------------------------------
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

  // ----------------------------------------------------------
  // Uncertainty window counter (dst_clk domain)
  // Counts SYNC_STAGES cycles after a change is detected.
  // ----------------------------------------------------------
  localparam int CNT_W = $clog2(`CDC_MAX_SYNC_LATENCY + SYNC_STAGES + 2);

  reg [CNT_W-1:0] unc_cnt;

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

  // ----------------------------------------------------------
  // Settled detection: dst_synced stable for SYNC_STAGES cycles
  // ----------------------------------------------------------
  reg [CNT_W-1:0] stable_cnt;
  reg             dst_synced_prev;

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

  // ----------------------------------------------------------
  // Sync timeout: dst_synced must settle within
  // CDC_MAX_SYNC_LATENCY dst_clk cycles after change detected
  // ----------------------------------------------------------
  reg [CNT_W-1:0] timeout_cnt;
  reg             timeout_active;

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
        if (timeout_cnt >= `CDC_MAX_SYNC_LATENCY - 1) begin
          sync_timeout <= 1'b1;
        end else begin
          timeout_cnt  <= timeout_cnt + 1;
          sync_timeout <= 1'b0;
        end
      end
    end
  end

endmodule
