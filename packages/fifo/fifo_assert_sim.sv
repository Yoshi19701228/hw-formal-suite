// ============================================================
// FIFO Assertion Module — Simulation / UVM
// Checks FIFO protocol correctness in simulation.
// Bind or instantiate alongside DUT.
//
// Usage:
//   fifo_assert_sim #(.DEPTH(16), .DATA_W(32), .ALMOST_THRESH(2))
//     u_sim (
//       .clk, .rst_n,
//       .push, .pop, .wdata, .rdata,
//       .full, .empty, .almost_full, .almost_empty, .count
//     );
// ============================================================
module fifo_assert_sim
  import fifo_pkg::*;
#(
  parameter int DEPTH        = 16,
  parameter int DATA_W       = 32,
  parameter int ALMOST_THRESH = 2
)(
  input logic                   clk,
  input logic                   rst_n,

  input logic                   push,
  input logic                   pop,
  input logic [DATA_W-1:0]      wdata,
  input logic [DATA_W-1:0]      rdata,

  input logic                   full,
  input logic                   empty,
  input logic                   almost_full,
  input logic                   almost_empty,
  input logic [$clog2(DEPTH):0] count
);

  // ----------------------------------------------------------
  // 1. Safety assertions
  // ----------------------------------------------------------

  // Push to a full FIFO is a protocol violation
  property prop_no_overflow;
    @(posedge clk) disable iff (!rst_n)
    !(push && full);
  endproperty
  AST_FIFO_NO_OVERFLOW: assert property (prop_no_overflow)
    else $error("FIFO overflow: push asserted when full");

  // Pop from an empty FIFO is a protocol violation
  property prop_no_underflow;
    @(posedge clk) disable iff (!rst_n)
    !(pop && empty);
  endproperty
  AST_FIFO_NO_UNDERFLOW: assert property (prop_no_underflow)
    else $error("FIFO underflow: pop asserted when empty");

  // full must be asserted when count reaches DEPTH
  property prop_full_when_max;
    @(posedge clk) disable iff (!rst_n)
    (count == DEPTH[$clog2(DEPTH):0]) |-> full;
  endproperty
  AST_FIFO_FULL_WHEN_MAX: assert property (prop_full_when_max)
    else $error("FIFO: count==DEPTH but full not asserted");

  // empty must be asserted when count is zero
  property prop_empty_when_zero;
    @(posedge clk) disable iff (!rst_n)
    (count == '0) |-> empty;
  endproperty
  AST_FIFO_EMPTY_WHEN_ZERO: assert property (prop_empty_when_zero)
    else $error("FIFO: count==0 but empty not asserted");

  // almost_full must be asserted when count is within ALMOST_THRESH of full
  property prop_almost_full_correct;
    @(posedge clk) disable iff (!rst_n)
    (count >= (DEPTH - ALMOST_THRESH)[$clog2(DEPTH):0]) |-> almost_full;
  endproperty
  AST_FIFO_ALMOST_FULL_CORRECT: assert property (prop_almost_full_correct)
    else $error("FIFO: count near DEPTH but almost_full not asserted");

  // almost_empty must be asserted when count is at or below ALMOST_THRESH
  property prop_almost_empty_correct;
    @(posedge clk) disable iff (!rst_n)
    (count <= ALMOST_THRESH[$clog2(DEPTH):0]) |-> almost_empty;
  endproperty
  AST_FIFO_ALMOST_EMPTY_CORRECT: assert property (prop_almost_empty_correct)
    else $error("FIFO: count near 0 but almost_empty not asserted");

  // Push without pop must increment count by 1 on next cycle
  property prop_count_push;
    @(posedge clk) disable iff (!rst_n)
    (!full && push && !pop) |=> (count == $past(count) + 1);
  endproperty
  AST_FIFO_COUNT_PUSH: assert property (prop_count_push)
    else $error("FIFO: count did not increment after push");

  // Pop without push must decrement count by 1 on next cycle
  property prop_count_pop;
    @(posedge clk) disable iff (!rst_n)
    (!empty && pop && !push) |=> (count == $past(count) - 1);
  endproperty
  AST_FIFO_COUNT_POP: assert property (prop_count_pop)
    else $error("FIFO: count did not decrement after pop");

  // ----------------------------------------------------------
  // 2. Reachability covers
  // ----------------------------------------------------------

  COV_FIFO_PUSH_OK: cover property (
    @(posedge clk) disable iff (!rst_n)
    push && !full
  );

  COV_FIFO_POP_OK: cover property (
    @(posedge clk) disable iff (!rst_n)
    pop && !empty
  );

  COV_FIFO_FULL: cover property (
    @(posedge clk) disable iff (!rst_n)
    full
  );

  COV_FIFO_EMPTY: cover property (
    @(posedge clk) disable iff (!rst_n)
    empty
  );

  COV_FIFO_ALMOST_FULL: cover property (
    @(posedge clk) disable iff (!rst_n)
    almost_full
  );

  COV_FIFO_ALMOST_EMPTY: cover property (
    @(posedge clk) disable iff (!rst_n)
    almost_empty
  );

  COV_FIFO_SIMULTANEOUS_PUSH_POP: cover property (
    @(posedge clk) disable iff (!rst_n)
    push && pop && !full && !empty
  );

  // FIFO transitions from completely full to completely empty
  COV_FIFO_FULL_TO_EMPTY: cover property (
    @(posedge clk) disable iff (!rst_n)
    full ##[1:$] empty
  );

endmodule
