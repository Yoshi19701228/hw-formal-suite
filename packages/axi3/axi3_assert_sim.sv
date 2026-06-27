// ============================================================
// AXI3 Assertion Module — Simulator
// Spec: AMBA AXI Protocol Specification (ARM IHI0022D, rev: AXI3)
//
// Key AXI3 differences from AXI4:
//   - WID signal exists on W channel; must match AWID per beat
//   - AWLEN/ARLEN are 4-bit (max 16 beats)
//   - AWLOCK/ARLOCK are 2-bit
//   - No AWREGION / ARREGION
//
// Usage (bind to master or slave DUT):
//   bind <dut_module> axi3_assert_sim #(
//     .ADDR_W(32), .DATA_W(32), .ID_W(4)
//   ) u_axi3_chk (.*);
// ============================================================
module axi3_assert_sim
  import axi3_pkg::*;
#(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int ID_W     = 4,
  parameter int MAX_WAIT = AXI3_MAX_WAIT_CYCLES
)(
  input logic              clk,
  input logic              rst_n,

  // Write Address Channel (AW)
  input logic              awvalid,
  input logic              awready,
  input logic [ID_W-1:0]   awid,
  input logic [ADDR_W-1:0] awaddr,
  input logic [3:0]        awlen,    // 4-bit in AXI3
  input logic [2:0]        awsize,
  input logic [1:0]        awburst,
  input logic [1:0]        awlock,   // 2-bit in AXI3

  // Write Data Channel (W)
  input logic              wvalid,
  input logic              wready,
  input logic [ID_W-1:0]   wid,      // AXI3-only: must match AWID
  input logic [DATA_W-1:0] wdata,
  input logic [DATA_W/8-1:0] wstrb,
  input logic              wlast,

  // Write Response Channel (B)
  input logic              bvalid,
  input logic              bready,
  input logic [ID_W-1:0]   bid,
  input logic [1:0]        bresp,

  // Read Address Channel (AR)
  input logic              arvalid,
  input logic              arready,
  input logic [ID_W-1:0]   arid,
  input logic [ADDR_W-1:0] araddr,
  input logic [3:0]        arlen,    // 4-bit in AXI3
  input logic [2:0]        arsize,
  input logic [1:0]        arburst,
  input logic [1:0]        arlock,   // 2-bit in AXI3

  // Read Data Channel (R)
  input logic              rvalid,
  input logic              rready,
  input logic [ID_W-1:0]   rid,
  input logic [DATA_W-1:0] rdata,
  input logic [1:0]        rresp,
  input logic              rlast
);

  // ----------------------------------------------------------
  // AW Channel — Write Address
  // ----------------------------------------------------------

  // AWVALID must not deassert until AWREADY; control signals stable throughout
  property prop_aw_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=>
      ($stable(awvalid) && $stable(awid) && $stable(awaddr) &&
       $stable(awlen) && $stable(awsize) && $stable(awburst));
  endproperty
  AST_AXI3_AWVALID_STABLE: assert property (prop_aw_valid_stable)
    else $error("[AXI3 FAIL] AW: AWVALID/signals changed before AWREADY at %t", $time);

  // AWLEN is always <= 4'hF (tautological for 4-bit wire; explicit for parameter safety)
  property prop_aw_len_valid;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> (awlen <= 4'hF);
  endproperty
  AST_AXI3_AWLEN_VALID: assert property (prop_aw_len_valid)
    else $error("[AXI3 FAIL] AW: AWLEN out of range at %t", $time);

  // AWSIZE must not exceed data bus width
  property prop_aw_size_valid;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> ((1 << awsize) <= DATA_W/8);
  endproperty
  AST_AXI3_AWSIZE_VALID: assert property (prop_aw_size_valid)
    else $error("[AXI3 FAIL] AW: AWSIZE exceeds data bus width at %t", $time);

  // AWBURST must not be reserved value (2'b11)
  property prop_aw_burst_valid;
    @(posedge clk) disable iff (!rst_n)
    awvalid |-> (awburst inside {axi3_burst_e'(0), axi3_burst_e'(1), axi3_burst_e'(2)});
  endproperty
  AST_AXI3_AWBURST_VALID: assert property (prop_aw_burst_valid)
    else $error("[AXI3 FAIL] AW: AWBURST is reserved value at %t", $time);

  // WRAP burst length must be 2, 4, 8, or 16 beats (AWLEN = 1, 3, 7, 15)
  property prop_aw_wrap_len;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && awburst == axi3_burst_e'(2)) |->
      (awlen inside {4'h1, 4'h3, 4'h7, 4'hF});
  endproperty
  AST_AXI3_WRAP_LEN: assert property (prop_aw_wrap_len)
    else $error("[AXI3 FAIL] AW: WRAP burst has invalid AWLEN at %t", $time);

  // ----------------------------------------------------------
  // W Channel — Write Data
  // ----------------------------------------------------------

  // WVALID must not deassert until WREADY; WID and data signals stable throughout
  property prop_w_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=>
      ($stable(wvalid) && $stable(wid) && $stable(wdata) && $stable(wstrb));
  endproperty
  AST_AXI3_WVALID_STABLE: assert property (prop_w_valid_stable)
    else $error("[AXI3 FAIL] W: WVALID/signals changed before WREADY at %t", $time);

  // WID must also be stable independently (belt-and-suspenders for linters)
  property prop_wid_stable;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && !wready) |=> $stable(wid);
  endproperty
  AST_AXI3_WID_STABLE: assert property (prop_wid_stable)
    else $error("[AXI3 FAIL] W: WID changed before WREADY at %t", $time);

  // ----------------------------------------------------------
  // B Channel — Write Response
  // ----------------------------------------------------------

  // BVALID must not deassert until BREADY; BID and BRESP stable throughout
  property prop_b_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (bvalid && !bready) |=> ($stable(bvalid) && $stable(bid) && $stable(bresp));
  endproperty
  AST_AXI3_BVALID_STABLE: assert property (prop_b_valid_stable)
    else $error("[AXI3 FAIL] B: BVALID/signals changed before BREADY at %t", $time);

  // BRESP must be a legal value
  property prop_bresp_legal;
    @(posedge clk) disable iff (!rst_n)
    bvalid |-> (bresp inside {axi3_resp_e'(0), axi3_resp_e'(1),
                               axi3_resp_e'(2), axi3_resp_e'(3)});
  endproperty
  AST_AXI3_BRESP_LEGAL: assert property (prop_bresp_legal)
    else $error("[AXI3 FAIL] B: illegal BRESP value %0b at %t", bresp, $time);

  // ----------------------------------------------------------
  // AR Channel — Read Address
  // ----------------------------------------------------------

  // ARVALID must not deassert until ARREADY; control signals stable throughout
  property prop_ar_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && !arready) |=>
      ($stable(arvalid) && $stable(arid) && $stable(araddr) &&
       $stable(arlen) && $stable(arsize) && $stable(arburst));
  endproperty
  AST_AXI3_ARVALID_STABLE: assert property (prop_ar_valid_stable)
    else $error("[AXI3 FAIL] AR: ARVALID/signals changed before ARREADY at %t", $time);

  // ARSIZE must not exceed data bus width
  property prop_ar_size_valid;
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> ((1 << arsize) <= DATA_W/8);
  endproperty
  AST_AXI3_ARSIZE_VALID: assert property (prop_ar_size_valid)
    else $error("[AXI3 FAIL] AR: ARSIZE exceeds data bus width at %t", $time);

  // ARBURST must not be reserved value (2'b11)
  property prop_ar_burst_valid;
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> (arburst inside {axi3_burst_e'(0), axi3_burst_e'(1), axi3_burst_e'(2)});
  endproperty
  AST_AXI3_ARBURST_VALID: assert property (prop_ar_burst_valid)
    else $error("[AXI3 FAIL] AR: ARBURST is reserved value at %t", $time);

  // WRAP burst length must be 2, 4, 8, or 16 beats (ARLEN = 1, 3, 7, 15)
  property prop_ar_wrap_len;
    @(posedge clk) disable iff (!rst_n)
    (arvalid && arburst == axi3_burst_e'(2)) |->
      (arlen inside {4'h1, 4'h3, 4'h7, 4'hF});
  endproperty
  AST_AXI3_WRAP_RLEN: assert property (prop_ar_wrap_len)
    else $error("[AXI3 FAIL] AR: WRAP burst has invalid ARLEN at %t", $time);

  // ----------------------------------------------------------
  // R Channel — Read Data
  // ----------------------------------------------------------

  // RVALID must not deassert until RREADY; read data signals stable throughout
  property prop_r_valid_stable;
    @(posedge clk) disable iff (!rst_n)
    (rvalid && !rready) |=>
      ($stable(rvalid) && $stable(rid) && $stable(rdata) &&
       $stable(rresp) && $stable(rlast));
  endproperty
  AST_AXI3_RVALID_STABLE: assert property (prop_r_valid_stable)
    else $error("[AXI3 FAIL] R: RVALID/signals changed before RREADY at %t", $time);

  // RRESP must be a legal value
  property prop_rresp_legal;
    @(posedge clk) disable iff (!rst_n)
    rvalid |-> (rresp inside {axi3_resp_e'(0), axi3_resp_e'(1),
                               axi3_resp_e'(2), axi3_resp_e'(3)});
  endproperty
  AST_AXI3_RRESP_LEGAL: assert property (prop_rresp_legal)
    else $error("[AXI3 FAIL] R: illegal RRESP value %0b at %t", rresp, $time);

  // ----------------------------------------------------------
  // Reset — all VALID signals must be deasserted during reset
  // ----------------------------------------------------------
  property prop_valid_low_during_reset;
    @(posedge clk)
    !rst_n |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
  endproperty
  AST_AXI3_RESET_VALID: assert property (prop_valid_low_during_reset)
    else $error("[AXI3 FAIL] VALID asserted during reset at %t", $time);

  // ----------------------------------------------------------
  // Cover — reachability
  // ----------------------------------------------------------

  // Basic handshake coverage
  COV_AXI3_AW_HANDSHAKE:       cover property (@(posedge clk) awvalid && awready);
  COV_AXI3_W_HANDSHAKE_LAST:   cover property (@(posedge clk) wvalid  && wready && wlast);
  COV_AXI3_B_HANDSHAKE:        cover property (@(posedge clk) bvalid  && bready);
  COV_AXI3_AR_HANDSHAKE:       cover property (@(posedge clk) arvalid && arready);
  COV_AXI3_R_HANDSHAKE_LAST:   cover property (@(posedge clk) rvalid  && rready && rlast);

  // Back-pressure (VALID asserted but READY low)
  COV_AXI3_AW_WAIT:            cover property (@(posedge clk) awvalid && !awready);
  COV_AXI3_W_WAIT:             cover property (@(posedge clk) wvalid  && !wready);
  COV_AXI3_B_WAIT:             cover property (@(posedge clk) bvalid  && !bready);
  COV_AXI3_AR_WAIT:            cover property (@(posedge clk) arvalid && !arready);
  COV_AXI3_R_WAIT:             cover property (@(posedge clk) rvalid  && !rready);

  // AXI3-specific: exclusive access (LOCK = 2'b01)
  COV_AXI3_EXCLUSIVE_WRITE:    cover property (@(posedge clk) awvalid && awlock == 2'b01);
  COV_AXI3_EXCLUSIVE_READ:     cover property (@(posedge clk) arvalid && arlock == 2'b01);

  // WRAP burst exercise
  COV_AXI3_WRAP_BURST:         cover property (@(posedge clk) awvalid && awburst == 2'b10);

  // Maximum-length burst (16 beats, AWLEN = 4'hF)
  COV_AXI3_MAX_LEN:            cover property (@(posedge clk) awvalid && awlen == 4'hF);

endmodule
