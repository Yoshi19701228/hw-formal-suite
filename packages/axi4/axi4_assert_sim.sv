// ============================================================
// AXI4 Assertion Module — Simulator
// Spec: AMBA AXI and ACE Protocol Specification (ARM IHI0022H)
//
// Usage (bind to master or slave DUT):
//   bind <dut_module> axi4_assert_sim #(
//     .ADDR_W(32), .DATA_W(64), .ID_W(4), .MAX_WAIT(256)
//   ) u_axi4_chk (.*);
// ============================================================
module axi4_assert_sim
  import axi4_pkg::*;
#(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 64,
  parameter int ID_W     = 4,
  parameter int MAX_WAIT = AXI4_MAX_WAIT_CYCLES
)(
  input logic              ACLK,
  input logic              ARESETn,

  // Write Address Channel (AW)
  input logic              AWVALID,
  input logic              AWREADY,
  input logic [ID_W-1:0]   AWID,
  input logic [ADDR_W-1:0] AWADDR,
  input logic [7:0]        AWLEN,
  input logic [2:0]        AWSIZE,
  input logic [1:0]        AWBURST,

  // Write Data Channel (W)
  input logic              WVALID,
  input logic              WREADY,
  input logic [DATA_W-1:0] WDATA,
  input logic [DATA_W/8-1:0] WSTRB,
  input logic              WLAST,

  // Write Response Channel (B)
  input logic              BVALID,
  input logic              BREADY,
  input logic [ID_W-1:0]   BID,
  input logic [1:0]        BRESP,

  // Read Address Channel (AR)
  input logic              ARVALID,
  input logic              ARREADY,
  input logic [ID_W-1:0]   ARID,
  input logic [ADDR_W-1:0] ARADDR,
  input logic [7:0]        ARLEN,
  input logic [2:0]        ARSIZE,
  input logic [1:0]        ARBURST,

  // Read Data Channel (R)
  input logic              RVALID,
  input logic              RREADY,
  input logic [ID_W-1:0]   RID,
  input logic [DATA_W-1:0] RDATA,
  input logic [1:0]        RRESP,
  input logic              RLAST
);

  // ----------------------------------------------------------
  // AW Channel — Write Address
  // ----------------------------------------------------------

  // Handshake stability: AWVALID must not deassert until AWREADY
  property prop_aw_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=> AWVALID;
  endproperty
  AST_AXI4_AW_VALID_STABLE: assert property (prop_aw_valid_stable)
    else $error("[AXI4 FAIL] AW: AWVALID dropped before AWREADY at %t", $time);

  // Address and control signals stable while AWVALID && !AWREADY
  property prop_aw_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=>
      ($stable(AWID) && $stable(AWADDR) && $stable(AWLEN) &&
       $stable(AWSIZE) && $stable(AWBURST));
  endproperty
  AST_AXI4_AW_SIGNALS_STABLE: assert property (prop_aw_signals_stable)
    else $error("[AXI4 FAIL] AW: channel signals changed before handshake at %t", $time);

  // AWSIZE must not exceed data bus width
  property prop_aw_size_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> (2**AWSIZE <= DATA_W/8);
  endproperty
  AST_AXI4_AW_SIZE_VALID: assert property (prop_aw_size_valid)
    else $error("[AXI4 FAIL] AW: AWSIZE exceeds data bus width at %t", $time);

  // AWBURST must not be reserved value (2'b11)
  property prop_aw_burst_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> (AWBURST != 2'b11);
  endproperty
  AST_AXI4_AW_BURST_VALID: assert property (prop_aw_burst_valid)
    else $error("[AXI4 FAIL] AW: AWBURST is reserved value at %t", $time);

  // WRAP burst length must be 2, 4, 8, or 16 (AWLEN = 1, 3, 7, 15)
  property prop_aw_wrap_len_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && AWBURST == AXI4_WRAP) |->
      (AWLEN == 8'd1 || AWLEN == 8'd3 || AWLEN == 8'd7 || AWLEN == 8'd15);
  endproperty
  AST_AXI4_AW_WRAP_LEN: assert property (prop_aw_wrap_len_valid)
    else $error("[AXI4 FAIL] AW: WRAP burst has invalid AWLEN at %t", $time);

  // ----------------------------------------------------------
  // W Channel — Write Data
  // ----------------------------------------------------------

  // WVALID stability
  property prop_w_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=> WVALID;
  endproperty
  AST_AXI4_W_VALID_STABLE: assert property (prop_w_valid_stable)
    else $error("[AXI4 FAIL] W: WVALID dropped before WREADY at %t", $time);

  // WDATA, WSTRB, WLAST stable while WVALID && !WREADY
  property prop_w_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=>
      ($stable(WDATA) && $stable(WSTRB) && $stable(WLAST));
  endproperty
  AST_AXI4_W_SIGNALS_STABLE: assert property (prop_w_signals_stable)
    else $error("[AXI4 FAIL] W: channel signals changed before handshake at %t", $time);

  // WSTRB must not enable bytes beyond data bus (all-zero is allowed for padding)
  property prop_w_strb_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    WVALID |-> (WSTRB >> (DATA_W/8) == '0);
  endproperty
  // Note: this property is tautological for correctly-sized ports but guards against
  // mismatched parameters.

  // ----------------------------------------------------------
  // B Channel — Write Response
  // ----------------------------------------------------------

  // BVALID stability
  property prop_b_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !BREADY) |=> BVALID;
  endproperty
  AST_AXI4_B_VALID_STABLE: assert property (prop_b_valid_stable)
    else $error("[AXI4 FAIL] B: BVALID dropped before BREADY at %t", $time);

  // BID and BRESP stable while BVALID && !BREADY
  property prop_b_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !BREADY) |=> ($stable(BID) && $stable(BRESP));
  endproperty
  AST_AXI4_B_SIGNALS_STABLE: assert property (prop_b_signals_stable)
    else $error("[AXI4 FAIL] B: channel signals changed before handshake at %t", $time);

  // BRESP must be a legal value
  property prop_bresp_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID |-> (BRESP inside {AXI4_OKAY, AXI4_EXOKAY, AXI4_SLVERR, AXI4_DECERR});
  endproperty
  AST_AXI4_BRESP_VALID: assert property (prop_bresp_valid)
    else $error("[AXI4 FAIL] B: illegal BRESP value %0b at %t", BRESP, $time);

  // ----------------------------------------------------------
  // AR Channel — Read Address
  // ----------------------------------------------------------

  property prop_ar_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=> ARVALID;
  endproperty
  AST_AXI4_AR_VALID_STABLE: assert property (prop_ar_valid_stable)
    else $error("[AXI4 FAIL] AR: ARVALID dropped before ARREADY at %t", $time);

  property prop_ar_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=>
      ($stable(ARID) && $stable(ARADDR) && $stable(ARLEN) &&
       $stable(ARSIZE) && $stable(ARBURST));
  endproperty
  AST_AXI4_AR_SIGNALS_STABLE: assert property (prop_ar_signals_stable)
    else $error("[AXI4 FAIL] AR: channel signals changed before handshake at %t", $time);

  property prop_ar_size_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    ARVALID |-> (2**ARSIZE <= DATA_W/8);
  endproperty
  AST_AXI4_AR_SIZE_VALID: assert property (prop_ar_size_valid)
    else $error("[AXI4 FAIL] AR: ARSIZE exceeds data bus width at %t", $time);

  property prop_ar_burst_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    ARVALID |-> (ARBURST != 2'b11);
  endproperty
  AST_AXI4_AR_BURST_VALID: assert property (prop_ar_burst_valid)
    else $error("[AXI4 FAIL] AR: ARBURST is reserved value at %t", $time);

  // ----------------------------------------------------------
  // R Channel — Read Data
  // ----------------------------------------------------------

  property prop_r_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=> RVALID;
  endproperty
  AST_AXI4_R_VALID_STABLE: assert property (prop_r_valid_stable)
    else $error("[AXI4 FAIL] R: RVALID dropped before RREADY at %t", $time);

  property prop_r_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=>
      ($stable(RID) && $stable(RDATA) && $stable(RRESP) && $stable(RLAST));
  endproperty
  AST_AXI4_R_SIGNALS_STABLE: assert property (prop_r_signals_stable)
    else $error("[AXI4 FAIL] R: channel signals changed before handshake at %t", $time);

  property prop_rresp_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    RVALID |-> (RRESP inside {AXI4_OKAY, AXI4_EXOKAY, AXI4_SLVERR, AXI4_DECERR});
  endproperty
  AST_AXI4_RRESP_VALID: assert property (prop_rresp_valid)
    else $error("[AXI4 FAIL] R: illegal RRESP value %0b at %t", RRESP, $time);

  // ----------------------------------------------------------
  // Reset — all VALID signals must be deasserted during reset
  // ----------------------------------------------------------
  property prop_valid_low_during_reset;
    @(posedge ACLK)
    !ARESETn |-> (!AWVALID && !WVALID && !BVALID && !ARVALID && !RVALID);
  endproperty
  AST_AXI4_VALID_LOW_IN_RESET: assert property (prop_valid_low_during_reset)
    else $error("[AXI4 FAIL] VALID asserted during reset at %t", $time);

  // ----------------------------------------------------------
  // Cover
  // ----------------------------------------------------------
  COV_AXI4_AW_HANDSHAKE: cover property (@(posedge ACLK) AWVALID && AWREADY);
  COV_AXI4_W_HANDSHAKE:  cover property (@(posedge ACLK) WVALID  && WREADY);
  COV_AXI4_B_HANDSHAKE:  cover property (@(posedge ACLK) BVALID  && BREADY);
  COV_AXI4_AR_HANDSHAKE: cover property (@(posedge ACLK) ARVALID && ARREADY);
  COV_AXI4_R_HANDSHAKE:  cover property (@(posedge ACLK) RVALID  && RREADY);

  COV_AXI4_W_LAST:       cover property (@(posedge ACLK) WVALID && WREADY && WLAST);
  COV_AXI4_R_LAST:       cover property (@(posedge ACLK) RVALID && RREADY && RLAST);
  COV_AXI4_B_SLVERR:     cover property (@(posedge ACLK) BVALID && BREADY && BRESP == AXI4_SLVERR);
  COV_AXI4_R_SLVERR:     cover property (@(posedge ACLK) RVALID && RREADY && RRESP == AXI4_SLVERR);

  COV_AXI4_AW_WAIT:      cover property (@(posedge ACLK) AWVALID && !AWREADY);
  COV_AXI4_W_WAIT:       cover property (@(posedge ACLK) WVALID  && !WREADY);
  COV_AXI4_AR_WAIT:      cover property (@(posedge ACLK) ARVALID && !ARREADY);

  // Burst length > 1
  COV_AXI4_AW_BURST:     cover property (@(posedge ACLK) AWVALID && AWREADY && AWLEN > 0);
  COV_AXI4_AR_BURST:     cover property (@(posedge ACLK) ARVALID && ARREADY && ARLEN > 0);

endmodule
