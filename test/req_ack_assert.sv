// ============================================================
// [req → ack timeout] Formal Verification
// Verifies that req_valid gets an ack_valid within 16 cycles.
// Requires: req_ack_helper providing cnt_req_pending, timeout
//
// File 1: req_ack_helper.v  — Verilog helper (timeout counter)
// File 2: req_ack_assert.sv — This file (SVA)
// ============================================================

// 1. Safety — req_valid must receive ack_valid within MAX_LATENCY cycles
property prop_no_timeout;
  @(posedge clk) disable iff (!rst_n)
  !timeout;  // driven by req_ack_helper: asserts when cnt_req_pending >= 15
endproperty

AST_NO_TIMEOUT: assert property (prop_no_timeout);

// ack_valid must not appear without a pending req_valid
property prop_no_spurious_ack;
  @(posedge clk) disable iff (!rst_n)
  ack_valid |-> req_valid;
endproperty

AST_NO_SPURIOUS_ACK: assert property (prop_no_spurious_ack);

// 2. Reachability — cover key scenarios for bounded model checking witness
COV_REQ_SEEN:      cover property (@(posedge clk) $rose(req_valid));
COV_ACK_SEEN:      cover property (@(posedge clk) $rose(ack_valid));
COV_REQ_ACK_PAIR:  cover property (@(posedge clk) req_valid ##[1:16] ack_valid);
COV_FAST_ACK:      cover property (@(posedge clk) $rose(req_valid) ##1 ack_valid);
COV_LATE_ACK:      cover property (@(posedge clk) $rose(req_valid) ##15 ack_valid);
COV_MULTI_REQ:     cover property (@(posedge clk) $rose(req_valid) ##[2:$] $rose(req_valid));
COV_REQ_WAIT:      cover property (@(posedge clk) req_valid && !ack_valid);

// 3. Environment — constrain the environment for convergence
//    ack_valid must eventually respond within MAX_LATENCY cycles
property assume_ack_eventually;
  @(posedge clk) disable iff (!rst_n)
  req_valid |-> ##[1:16] ack_valid;
endproperty

ENV_ACK_EVENTUALLY: assume property (assume_ack_eventually);
