// ============================================================
// [AXI4 Write Channel] Formal assertions for AW/W/B handshake
// Inputs follow README defaults:
//   clk, rst_n, awvalid, awready, wvalid, wready
// Data widths per request:
//   awaddr[31:0], wdata[63:0], wstrb[7:0]
// ============================================================
module axi4_write_assert #(
  parameter integer MAX_AW2W = 16,
  parameter integer MAX_W2B  = 16,
  parameter integer MAX_OUT  = 8
) (
  input wire                  clk,
  input wire                  rst_n,
  input wire                  awvalid,
  input wire                  awready,
  input wire [31:0]           awaddr,
  input wire                  wvalid,
  input wire                  wready,
  input wire [63:0]           wdata,
  input wire [7:0]            wstrb,
  input wire                  bvalid,
  input wire                  bready,
  input wire                  pending_aw,
  input wire                  pending_b,
  input wire [$clog2(MAX_OUT+1)-1:0] outstanding_aw,
  input wire [$clog2(MAX_OUT+1)-1:0] outstanding_b,
  input wire [$clog2(MAX_AW2W+1)-1:0] cnt_aw2w,
  input wire [$clog2(MAX_W2B+1)-1:0]  cnt_w2b,
  input wire                  aw2w_timeout,
  input wire                  w2b_timeout,
  input wire                  aw_overflow,
  input wire                  aw_underflow,
  input wire                  b_overflow,
  input wire                  b_underflow
);

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid && wready;
  wire b_hs  = bvalid && bready;

  // 1. Safety -------------------------------------------------

  property prop_no_aw2w_timeout;
    @(posedge clk) disable iff (!rst_n)
    !aw2w_timeout;
  endproperty
  AST_NO_AW2W_TIMEOUT: assert property (prop_no_aw2w_timeout);

  property prop_no_w2b_timeout;
    @(posedge clk) disable iff (!rst_n)
    !w2b_timeout;
  endproperty
  AST_NO_W2B_TIMEOUT: assert property (prop_no_w2b_timeout);

  property prop_no_aw_overflow_underflow;
    @(posedge clk) disable iff (!rst_n)
    !(aw_overflow || aw_underflow);
  endproperty
  AST_NO_AW_COUNT_ERR: assert property (prop_no_aw_overflow_underflow);

  property prop_no_b_overflow_underflow;
    @(posedge clk) disable iff (!rst_n)
    !(b_overflow || b_underflow);
  endproperty
  AST_NO_B_COUNT_ERR: assert property (prop_no_b_overflow_underflow);

  property prop_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> awvalid;
  endproperty
  AST_AWVALID_STABLE: assert property (prop_awvalid_stable);

  property prop_awaddr_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> $stable(awaddr);
  endproperty
  AST_AWADDR_STABLE: assert property (prop_awaddr_stable);

  property prop_wvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> wvalid;
  endproperty
  AST_WVALID_STABLE: assert property (prop_wvalid_stable);

  property prop_wpayload_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> ($stable(wdata) && $stable(wstrb));
  endproperty
  AST_WPAYLOAD_STABLE: assert property (prop_wpayload_stable);

  property prop_bvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> bvalid;
  endproperty
  AST_BVALID_STABLE: assert property (prop_bvalid_stable);

  // 2. Reachability ------------------------------------------

  COV_AW_HS:           cover property (@(posedge clk) aw_hs);
  COV_W_HS:            cover property (@(posedge clk) w_hs);
  COV_B_HS:            cover property (@(posedge clk) b_hs);
  COV_PENDING_AW:      cover property (@(posedge clk) pending_aw);
  COV_PENDING_B:       cover property (@(posedge clk) pending_b);
  COV_BACKPRESSURE_AW: cover property (@(posedge clk) awvalid && !awready);
  COV_BACKPRESSURE_W:  cover property (@(posedge clk) wvalid && !wready);
  COV_BACKPRESSURE_B:  cover property (@(posedge clk) bvalid && !bready);
  COV_AW_THEN_W:       cover property (@(posedge clk) aw_hs ##[1:MAX_AW2W] w_hs);
  COV_W_THEN_B:        cover property (@(posedge clk) w_hs ##[1:MAX_W2B] b_hs);
  COV_AW_W_B_CHAIN:    cover property (@(posedge clk) aw_hs ##[1:MAX_AW2W] w_hs ##[1:MAX_W2B] b_hs);
  COV_AW_OUT_GT1:      cover property (@(posedge clk) outstanding_aw > 1);
  COV_B_OUT_GT1:       cover property (@(posedge clk) outstanding_b > 1);
  COV_AW_WAIT_BOUND:   cover property (@(posedge clk) pending_aw && (cnt_aw2w == MAX_AW2W - 1));
  COV_B_WAIT_BOUND:    cover property (@(posedge clk) pending_b && (cnt_w2b == MAX_W2B - 1));

  // 3. Environment Constraints -------------------------------

  property assume_aw_hold_until_ready;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> awvalid;
  endproperty
  ENV_AW_HOLD_UNTIL_READY: assume property (assume_aw_hold_until_ready);

  property assume_w_hold_until_ready;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> wvalid;
  endproperty
  ENV_W_HOLD_UNTIL_READY: assume property (assume_w_hold_until_ready);

  property assume_b_hold_until_ready;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> bvalid;
  endproperty
  ENV_B_HOLD_UNTIL_READY: assume property (assume_b_hold_until_ready);

  property assume_w_needs_pending_aw;
    @(posedge clk) disable iff (!rst_n)
    w_hs |-> pending_aw;
  endproperty
  ENV_W_NEEDS_PENDING_AW: assume property (assume_w_needs_pending_aw);

  property assume_b_needs_pending_w;
    @(posedge clk) disable iff (!rst_n)
    b_hs |-> pending_b;
  endproperty
  ENV_B_NEEDS_PENDING_W: assume property (assume_b_needs_pending_w);

  property assume_bready_eventually;
    @(posedge clk) disable iff (!rst_n)
    bvalid |-> ##[0:MAX_W2B] bready;
  endproperty
  ENV_BREADY_EVENTUALLY: assume property (assume_bready_eventually);

endmodule
