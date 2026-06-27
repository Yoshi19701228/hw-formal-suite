// ============================================================
// [Test] Arbiter SVA — Formal (non-determinism)
// Sample showing expansion of snippets: sva-fml-arbiter-helper + sva-fml-arbiter
// ============================================================

// --- Copilot Chat Test ---
// Copy and paste the following into Copilot Chat (Cmd+Shift+I) to try:
//
//   [Formal Verification]
//   Generate SVA and a Verilog helper to verify mutual exclusion,
//   no spurious grant, and starvation-freedom for a 4-port arbiter.
//   Signal names: req[3:0], gnt[3:0]
//   Maximum wait cycles: 16
//   Clock: clk, reset: rst_n (active-low)

// ============================================================
// Expected generated output (form after expanding snippet sva-fml-arbiter)
// ============================================================

// 1. Safety

property prop_gnt_mutex;
  @(posedge clk) disable iff (!rst_n) $onehot0(gnt);
endproperty
AST_GNT_MUTEX: assert property (prop_gnt_mutex);

property prop_no_spurious_gnt;
  @(posedge clk) disable iff (!rst_n) (gnt & ~req) == '0;
endproperty
AST_NO_SPURIOUS_GNT: assert property (prop_no_spurious_gnt);

property prop_no_starvation;
  @(posedge clk) disable iff (!rst_n) !starvation;
endproperty
AST_NO_STARVATION: assert property (prop_no_starvation);

property prop_gnt_implies_req;
  @(posedge clk) disable iff (!rst_n) gnt[chosen] |-> req[chosen];
endproperty
AST_GNT_IMPLIES_REQ: assert property (prop_gnt_implies_req);

// 2. Reachability

COV_CHOSEN_GNT:            cover property (@(posedge clk) gnt[chosen]);
COV_CHOSEN_REQ:            cover property (@(posedge clk) req[chosen]);
COV_CHOSEN_GNT_CONTENTION: cover property (@(posedge clk) gnt[chosen] && (req != (1 << chosen)));
COV_ALL_REQ:               cover property (@(posedge clk) &req);

// 3. Environment

property assume_chosen_valid;
  @(posedge clk) chosen < 4;
endproperty
ENV_CHOSEN_VALID: assume property (assume_chosen_valid);

property assume_chosen_requests;
  @(posedge clk) disable iff (!rst_n) ##1 req[chosen];
endproperty
ENV_CHOSEN_REQUESTS: assume property (assume_chosen_requests);
