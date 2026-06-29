// ============================================================
// CDC Asynchronous Clock Environment — Formal Verification
//
// Purpose:
//   Provide assume properties that model two truly asynchronous
//   clock domains. By default formal tools treat all clocks as
//   synchronous; this module removes that assumption and models
//   worst-case metastability via $anyseq.
//
// Usage (bind to CDC DUT or formal_top):
//   bind cdc_dut cdc_async_assume #(
//     .SYNC_STAGES(2),
//     .CLK_A_MIN_HALF(2),
//     .CLK_B_MIN_HALF(3),
//     .MAX_META_WINDOW(2)
//   ) u_async_env (
//     .clk_a      (clk_src),
//     .clk_b      (clk_dst),
//     .rst_a_n    (rst_src_n),
//     .rst_b_n    (rst_dst_n),
//     .sig_a      (data_src),
//     .sig_b_syncd(data_dst_syncd)
//   );
//
// How it works:
//   1. Clock independence  — no phase/frequency relationship assumed
//   2. Clock validity      — each clock eventually toggles (liveness)
//   3. Metastability       — $anyseq models per-cycle non-determinism
//                            in the metastability window
//   4. Synchronizer output — signal is stable after SYNC_STAGES cycles
//                            in the destination domain
// ============================================================
module cdc_async_assume #(
  parameter int SYNC_STAGES    = 2,   // number of flip-flop sync stages
  parameter int CLK_A_MIN_HALF = 2,   // min half-period of clk_a (abstract units)
  parameter int CLK_B_MIN_HALF = 2,   // min half-period of clk_b (abstract units)
  parameter int MAX_META_WINDOW = 2,  // max cycles metastability can persist
  parameter int DATA_W          = 1   // width of the crossing signal
)(
  input logic              clk_a,       // source clock
  input logic              clk_b,       // destination clock
  input logic              rst_a_n,     // active-low reset, source domain
  input logic              rst_b_n,     // active-low reset, destination domain
  input logic [DATA_W-1:0] sig_a,       // signal in source (clk_a) domain
  input logic [DATA_W-1:0] sig_b_syncd  // signal after synchronizer, clk_b domain
);

  // ============================================================
  // [Helper] Metastability window tracker (source-side change)
  //
  // Tracks how many clk_b cycles have elapsed since sig_a last
  // changed. Used to define the metastability window during which
  // sig_b_syncd may take any value.
  // ============================================================
  reg [$clog2(MAX_META_WINDOW+SYNC_STAGES+1)-1:0] cnt_meta;
  reg                                              sig_a_prev;
  wire                                             sig_a_changed;

  // Detect a change in sig_a (single-bit; extend per bit for wider signals)
  assign sig_a_changed = (sig_a[0] !== sig_a_prev);

  always @(posedge clk_b or negedge rst_b_n) begin
    if (!rst_b_n) begin
      cnt_meta  <= '0;
      sig_a_prev <= sig_a[0];
    end else begin
      sig_a_prev <= sig_a[0];
      if (sig_a_changed)
        cnt_meta <= '0;
      else if (cnt_meta < MAX_META_WINDOW + SYNC_STAGES)
        cnt_meta <= cnt_meta + 1;
    end
  end

  wire in_meta_window  = (cnt_meta <= MAX_META_WINDOW);
  wire sync_settled    = (cnt_meta >= MAX_META_WINDOW + SYNC_STAGES);

  // ============================================================
  // [Helper] $anyseq metastability model
  //
  // During the metastability window, the synchronizer output can
  // be any value each cycle (modeled by $anyseq — changes per cycle).
  // After SYNC_STAGES additional cycles, the output must be stable.
  // ============================================================
  logic [DATA_W-1:0] meta_val;
  assign meta_val = $anyseq;   // non-deterministic per cycle — models metastability

  // ============================================================
  // 3. Environment Constraints (assume)
  // ============================================================

  // ------ Clock A: liveness (eventually toggles) ---------------

  // clk_a must not stay high longer than CLK_A_MIN_HALF cycles
  property assume_clk_a_max_high;
    @(posedge clk_a) $rose(clk_a) |->
      ##[1:CLK_A_MIN_HALF] $fell(clk_a);
  endproperty
  ENV_CLK_A_MAX_HIGH: assume property (assume_clk_a_max_high);

  // clk_a must not stay low longer than CLK_A_MIN_HALF cycles
  property assume_clk_a_max_low;
    @(negedge clk_a) $fell(clk_a) |->
      ##[1:CLK_A_MIN_HALF] $rose(clk_a);
  endproperty
  ENV_CLK_A_MAX_LOW: assume property (assume_clk_a_max_low);

  // ------ Clock B: liveness (eventually toggles) ---------------

  property assume_clk_b_max_high;
    @(posedge clk_b) $rose(clk_b) |->
      ##[1:CLK_B_MIN_HALF] $fell(clk_b);
  endproperty
  ENV_CLK_B_MAX_HIGH: assume property (assume_clk_b_max_high);

  property assume_clk_b_max_low;
    @(negedge clk_b) $fell(clk_b) |->
      ##[1:CLK_B_MIN_HALF] $rose(clk_b);
  endproperty
  ENV_CLK_B_MAX_LOW: assume property (assume_clk_b_max_low);

  // ------ No phase constraint between clk_a and clk_b ----------
  //
  // Intentionally NO assume about the phase/frequency relationship
  // between clk_a and clk_b. This is what makes them "asynchronous"
  // to the formal tool — it explores all possible phase combinations.

  // ------ Metastability window: output may be non-deterministic --

  property assume_meta_window_anyseq;
    @(posedge clk_b) disable iff (!rst_b_n)
    in_meta_window |-> sig_b_syncd == meta_val;
  endproperty
  ENV_META_WINDOW: assume property (assume_meta_window_anyseq);

  // ------ Post-synchronization stability -------------------------
  //
  // After SYNC_STAGES clk_b cycles past the metastability window,
  // the synchronized signal must reflect the stable source value.
  property assume_sync_settled;
    @(posedge clk_b) disable iff (!rst_b_n)
    sync_settled |-> sig_b_syncd == sig_a;
  endproperty
  ENV_SYNC_SETTLED: assume property (assume_sync_settled);

  // Synchronized signal must not glitch once settled
  property assume_sync_no_glitch;
    @(posedge clk_b) disable iff (!rst_b_n)
    (sync_settled && !sig_a_changed) |=> $stable(sig_b_syncd);
  endproperty
  ENV_SYNC_NO_GLITCH: assume property (assume_sync_no_glitch);

  // ------ Reset ordering -----------------------------------------
  //
  // Destination reset must deassert after (or together with) source reset
  // to avoid illegal combinations during power-on.
  property assume_reset_order;
    @(posedge clk_b) $rose(rst_b_n) |-> rst_a_n;
  endproperty
  ENV_RESET_ORDER: assume property (assume_reset_order);

  // ============================================================
  // 1. Safety — verify synchronizer did not lose a transition
  // ============================================================

  // After sync_settled, the output must NOT still hold the old value
  // if the source has changed more than SYNC_STAGES+MAX_META_WINDOW cycles ago
  property prop_no_missed_transition;
    @(posedge clk_b) disable iff (!rst_b_n)
    sync_settled |-> (sig_b_syncd == sig_a);
  endproperty
  AST_CDC_NO_MISSED_TRANSITION: assert property (prop_no_missed_transition);

  // ============================================================
  // 2. Reachability
  // ============================================================
  COV_CDC_META_ENTERED:   cover property (@(posedge clk_b) $rose(in_meta_window));
  COV_CDC_META_RESOLVED:  cover property (@(posedge clk_b) $rose(sync_settled));
  COV_CDC_TRANSITION_0_1: cover property (@(posedge clk_b) sync_settled && sig_b_syncd == 1'b1);
  COV_CDC_TRANSITION_1_0: cover property (@(posedge clk_b) sync_settled && sig_b_syncd == 1'b0);
  COV_CDC_SRC_CHANGES:    cover property (@(posedge clk_a) $changed(sig_a));

endmodule
