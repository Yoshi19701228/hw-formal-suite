// ============================================================
// AXI3 Assertion Module — Formal Verification
// Spec: AMBA AXI Protocol Specification (ARM IHI0022D, rev: AXI3)
//
// Usage (bind):
//   bind <dut_module> axi3_assert_fml #(.ADDR_W(32), .DATA_W(32)) u_fml (.*);
// ============================================================
module axi3_assert_fml
  import axi3_pkg::*;
#(
  parameter int ADDR_W          = 32,
  parameter int DATA_W          = 32,
  parameter int ID_W            = 4,
  parameter int MAX_WAIT        = AXI3_MAX_WAIT_CYCLES,
  parameter int MAX_OUTSTANDING = AXI3_MAX_OUTSTANDING
)(
  input logic              clk,
  input logic              rst_n,

  // AW
  input logic              awvalid,
  input logic              awready,
  input logic [ID_W-1:0]   awid,
  input logic [ADDR_W-1:0] awaddr,
  input logic [3:0]        awlen,    // 4-bit in AXI3
  input logic [2:0]        awsize,
  input logic [1:0]        awburst,
  input logic [1:0]        awlock,   // 2-bit in AXI3

  // W
  input logic              wvalid,
  input logic              wready,
  input logic [ID_W-1:0]   wid,      // AXI3-only
  input logic [DATA_W-1:0] wdata,
  input logic [DATA_W/8-1:0] wstrb,
  input logic              wlast,

  // B
  input logic              bvalid,
  input logic              bready,
  input logic [ID_W-1:0]   bid,
  input logic [1:0]        bresp,

  // AR
  input logic              arvalid,
  input logic              arready,
  input logic [ID_W-1:0]   arid,
  input logic [ADDR_W-1:0] araddr,
  input logic [3:0]        arlen,    // 4-bit in AXI3
  input logic [2:0]        arsize,
  input logic [1:0]        arburst,
  input logic [1:0]        arlock,   // 2-bit in AXI3

  // R
  input logic              rvalid,
  input logic              rready,
  input logic [ID_W-1:0]   rid,
  input logic [DATA_W-1:0] rdata,
  input logic [1:0]        rresp,
  input logic              rlast
);

  // ============================================================
  // [Helper Logic] — handshake timeout counters, write beat
  //   tracking, outstanding transaction counters
  //   (inlined from axi3_helper.v)
  // ============================================================
  reg [$clog2(MAX_WAIT+1)-1:0] cnt_aw, cnt_w, cnt_b, cnt_ar, cnt_r;
  reg               aw_timeout;
  reg               w_timeout;
  reg               b_timeout;
  reg               ar_timeout;
  reg               r_timeout;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_aw <= '0; aw_timeout <= 1'b0;
      cnt_w  <= '0; w_timeout  <= 1'b0;
      cnt_b  <= '0; b_timeout  <= 1'b0;
      cnt_ar <= '0; ar_timeout <= 1'b0;
      cnt_r  <= '0; r_timeout  <= 1'b0;
    end else begin
      // AW
      if (awvalid && !awready) cnt_aw <= cnt_aw + 1; else cnt_aw <= '0;
      aw_timeout <= (cnt_aw >= MAX_WAIT - 1) && awvalid && !awready;
      // W
      if (wvalid  && !wready)  cnt_w  <= cnt_w  + 1; else cnt_w  <= '0;
      w_timeout  <= (cnt_w  >= MAX_WAIT - 1) && wvalid  && !wready;
      // B
      if (bvalid  && !bready)  cnt_b  <= cnt_b  + 1; else cnt_b  <= '0;
      b_timeout  <= (cnt_b  >= MAX_WAIT - 1) && bvalid  && !bready;
      // AR
      if (arvalid && !arready) cnt_ar <= cnt_ar + 1; else cnt_ar <= '0;
      ar_timeout <= (cnt_ar >= MAX_WAIT - 1) && arvalid && !arready;
      // R
      if (rvalid  && !rready)  cnt_r  <= cnt_r  + 1; else cnt_r  <= '0;
      r_timeout  <= (cnt_r  >= MAX_WAIT - 1) && rvalid  && !rready;
    end
  end

  reg  [3:0]        snap_awlen;
  reg  [3:0]        cnt_w_beats;
  reg               wlast_mismatch;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      snap_awlen      <= 4'h0;
      cnt_w_beats     <= 4'h0;
      wlast_mismatch  <= 1'b0;
    end else begin
      if (awvalid && awready)
        snap_awlen <= awlen;

      if (wvalid && wready) begin
        if (wlast)
          cnt_w_beats <= 4'h0;
        else
          cnt_w_beats <= cnt_w_beats + 4'h1;

        // WLAST must fire exactly when beat count == AWLEN
        wlast_mismatch <= wlast && (cnt_w_beats != snap_awlen);
      end else begin
        wlast_mismatch <= 1'b0;
      end
    end
  end

  reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_aw_outstanding;
  reg               aw_overflow;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_aw_outstanding <= '0;
      aw_overflow        <= 1'b0;
    end else begin
      case ({awvalid && awready, bvalid && bready})
        2'b10: cnt_aw_outstanding <= cnt_aw_outstanding + 1;
        2'b01: cnt_aw_outstanding <= cnt_aw_outstanding - 1;
        default: ;
      endcase
      aw_overflow <= (cnt_aw_outstanding >= MAX_OUTSTANDING) && awvalid && awready;
    end
  end

  reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_ar_outstanding;
  reg               ar_overflow;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_ar_outstanding <= '0;
      ar_overflow        <= 1'b0;
    end else begin
      case ({arvalid && arready, rvalid && rready && rlast})
        2'b10: cnt_ar_outstanding <= cnt_ar_outstanding + 1;
        2'b01: cnt_ar_outstanding <= cnt_ar_outstanding - 1;
        default: ;
      endcase
      ar_overflow <= (cnt_ar_outstanding >= MAX_OUTSTANDING) && arvalid && arready;
    end
  end

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // Reset: all VALID signals must be deasserted
  property prop_valid_low_during_reset;
    @(posedge clk)
    !rst_n |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
  endproperty
  AST_AXI3_RESET_VALID: assert property (prop_valid_low_during_reset);

  // --- AW Channel ---
  property prop_aw_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=>
      ($stable(awvalid) && $stable(awid) && $stable(awaddr) &&
       $stable(awlen) && $stable(awsize) && $stable(awburst));
  endproperty
  AST_AXI3_AWVALID_STABLE: assert property (prop_aw_valid_stable);

  property prop_aw_size_valid;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> ((1 << awsize) <= DATA_W/8);
  endproperty
  AST_AXI3_AWSIZE_VALID: assert property (prop_aw_size_valid);

  property prop_aw_burst_valid;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> (awburst inside {axi3_burst_e'(0), axi3_burst_e'(1), axi3_burst_e'(2)});
  endproperty
  AST_AXI3_AWBURST_VALID: assert property (prop_aw_burst_valid);

  property prop_aw_wrap_len;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && awburst == axi3_burst_e'(2)) |->
      (awlen inside {4'h1, 4'h3, 4'h7, 4'hF});
  endproperty
  AST_AXI3_WRAP_LEN: assert property (prop_aw_wrap_len);

  // No timeout on AW channel (helper counter replaces ##[1:MAX_WAIT])
  property prop_aw_no_timeout;
    @(posedge clk) disable iff (!rst_n) !aw_timeout;
  endproperty
  AST_AXI3_AW_TIMEOUT: assert property (prop_aw_no_timeout);

  // No outstanding overflow
  property prop_aw_no_overflow;
    @(posedge clk) disable iff (!rst_n) !aw_overflow;
  endproperty
  AST_AXI3_NO_AW_OVERFLOW: assert property (prop_aw_no_overflow);

  // --- W Channel ---
  property prop_w_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=>
      ($stable(wvalid) && $stable(wid) && $stable(wdata) && $stable(wstrb));
  endproperty
  AST_AXI3_WVALID_STABLE: assert property (prop_w_valid_stable);

  property prop_w_no_timeout;
    @(posedge clk) disable iff (!rst_n) !w_timeout;
  endproperty
  AST_AXI3_W_TIMEOUT: assert property (prop_w_no_timeout);

  // WLAST must fire on the correct beat (helper tracks this)
  property prop_wlast_correct;
    @(posedge clk) disable iff (!rst_n) !wlast_mismatch;
  endproperty
  AST_AXI3_WLAST_CORRECT: assert property (prop_wlast_correct);

  // --- B Channel ---
  property prop_b_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> ($stable(bvalid) && $stable(bid) && $stable(bresp));
  endproperty
  AST_AXI3_BVALID_STABLE: assert property (prop_b_valid_stable);

  property prop_bresp_legal;
    @(posedge clk) disable iff (!rst_n)
    bvalid |-> (bresp inside {axi3_resp_e'(0), axi3_resp_e'(1),
                               axi3_resp_e'(2), axi3_resp_e'(3)});
  endproperty
  AST_AXI3_BRESP_LEGAL: assert property (prop_bresp_legal);

  property prop_b_no_timeout;
    @(posedge clk) disable iff (!rst_n) !b_timeout;
  endproperty
  AST_AXI3_B_TIMEOUT: assert property (prop_b_no_timeout);

  // --- AR Channel ---
  property prop_ar_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && !arready) |=>
      ($stable(arvalid) && $stable(arid) && $stable(araddr) &&
       $stable(arlen) && $stable(arsize) && $stable(arburst));
  endproperty
  AST_AXI3_ARVALID_STABLE: assert property (prop_ar_valid_stable);

  property prop_ar_size_valid;
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> ((1 << arsize) <= DATA_W/8);
  endproperty
  AST_AXI3_ARSIZE_VALID: assert property (prop_ar_size_valid);

  property prop_ar_burst_valid;
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> (arburst inside {axi3_burst_e'(0), axi3_burst_e'(1), axi3_burst_e'(2)});
  endproperty
  AST_AXI3_ARBURST_VALID: assert property (prop_ar_burst_valid);

  property prop_ar_wrap_len;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && arburst == axi3_burst_e'(2)) |->
      (arlen inside {4'h1, 4'h3, 4'h7, 4'hF});
  endproperty
  AST_AXI3_WRAP_RLEN: assert property (prop_ar_wrap_len);

  property prop_ar_no_timeout;
    @(posedge clk) disable iff (!rst_n) !ar_timeout;
  endproperty
  AST_AXI3_AR_TIMEOUT: assert property (prop_ar_no_timeout);

  property prop_ar_no_overflow;
    @(posedge clk) disable iff (!rst_n) !ar_overflow;
  endproperty
  AST_AXI3_NO_AR_OVERFLOW: assert property (prop_ar_no_overflow);

  // --- R Channel ---
  property prop_r_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (rvalid && !rready) |=>
      ($stable(rvalid) && $stable(rid) && $stable(rdata) &&
       $stable(rresp) && $stable(rlast));
  endproperty
  AST_AXI3_RVALID_STABLE: assert property (prop_r_valid_stable);

  property prop_rresp_legal;
    @(posedge clk) disable iff (!rst_n)
    rvalid |-> (rresp inside {axi3_resp_e'(0), axi3_resp_e'(1),
                               axi3_resp_e'(2), axi3_resp_e'(3)});
  endproperty
  AST_AXI3_RRESP_LEGAL: assert property (prop_rresp_legal);

  property prop_r_no_timeout;
    @(posedge clk) disable iff (!rst_n) !r_timeout;
  endproperty
  AST_AXI3_R_TIMEOUT: assert property (prop_r_no_timeout);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------
  COV_AXI3_AW_HANDSHAKE:     cover property (@(posedge clk) awvalid && awready);
  COV_AXI3_W_HANDSHAKE_LAST: cover property (@(posedge clk) wvalid  && wready && wlast);
  COV_AXI3_B_HANDSHAKE:      cover property (@(posedge clk) bvalid  && bready);
  COV_AXI3_AR_HANDSHAKE:     cover property (@(posedge clk) arvalid && arready);
  COV_AXI3_R_HANDSHAKE_LAST: cover property (@(posedge clk) rvalid  && rready && rlast);

  COV_AXI3_AW_WAIT:          cover property (@(posedge clk) awvalid && !awready);
  COV_AXI3_W_WAIT:           cover property (@(posedge clk) wvalid  && !wready);
  COV_AXI3_B_WAIT:           cover property (@(posedge clk) bvalid  && !bready);
  COV_AXI3_AR_WAIT:          cover property (@(posedge clk) arvalid && !arready);
  COV_AXI3_R_WAIT:           cover property (@(posedge clk) rvalid  && !rready);

  COV_AXI3_EXCLUSIVE_WRITE:  cover property (@(posedge clk) awvalid && awlock == 2'b01);
  COV_AXI3_EXCLUSIVE_READ:   cover property (@(posedge clk) arvalid && arlock == 2'b01);
  COV_AXI3_WRAP_BURST:       cover property (@(posedge clk) awvalid && awburst == 2'b10);
  COV_AXI3_MAX_LEN:          cover property (@(posedge clk) awvalid && awlen == 4'hF);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // All VALID signals must be deasserted at the end of reset
  property assume_valid_low_after_reset;
    @(posedge clk)
    $rose(rst_n) |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
  endproperty
  ENV_AXI3_VALID_LOW_AFTER_RESET: assume property (assume_valid_low_after_reset);

  // AWLEN is 4-bit; trivially bounded, but explicit for clarity
  property assume_aw_len_bounded;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> (awlen <= 4'hF);
  endproperty
  ENV_AXI3_AWLEN_BOUNDED: assume property (assume_aw_len_bounded);

  property assume_ar_len_bounded;
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> (arlen <= 4'hF);
  endproperty
  ENV_AXI3_ARLEN_BOUNDED: assume property (assume_ar_len_bounded);

endmodule
