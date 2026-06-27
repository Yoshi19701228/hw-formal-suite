// ============================================================
// APB3 Assertion Module — Simulator
// Spec: AMBA 3 APB Protocol Specification (ARM IHI0024C)
//
// Usage (bind to DUT):
//   bind <dut_module> apb3_assert_sim #(
//     .ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)
//   ) u_apb3_chk (.*);
// ============================================================
module apb3_assert_sim
  import apb3_pkg::*;
#(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int MAX_WAIT = APB3_MAX_WAIT_CYCLES
)(
  input logic              PCLK,
  input logic              PRESETn,
  input logic              PSEL,
  input logic              PENABLE,
  input logic              PWRITE,
  input logic              PREADY,
  input logic              PSLVERR,
  input logic [ADDR_W-1:0] PADDR,
  input logic [DATA_W-1:0] PWDATA,
  input logic [DATA_W-1:0] PRDATA
);

  // ----------------------------------------------------------
  // R1: PENABLE must be asserted exactly 1 cycle after PSEL rises
  // ----------------------------------------------------------
  property prop_penable_follows_psel;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PSEL) |=> PENABLE;
  endproperty
  AST_APB3_PENABLE_FOLLOWS_PSEL: assert property (prop_penable_follows_psel)
    else $error("[APB3 FAIL] PENABLE not asserted 1 cycle after PSEL at %t", $time);

  // ----------------------------------------------------------
  // R2: PENABLE must not be asserted without PSEL
  // ----------------------------------------------------------
  property prop_penable_requires_psel;
    @(posedge PCLK) disable iff (!PRESETn)
    PENABLE |-> PSEL;
  endproperty
  AST_APB3_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel)
    else $error("[APB3 FAIL] PENABLE asserted without PSEL at %t", $time);

  // ----------------------------------------------------------
  // R3: Setup phase (PSEL=1, PENABLE=0) — address and control stable
  // ----------------------------------------------------------
  property prop_setup_addr_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> $stable(PADDR);
  endproperty
  AST_APB3_SETUP_ADDR_STABLE: assert property (prop_setup_addr_stable)
    else $error("[APB3 FAIL] PADDR changed during setup phase at %t", $time);

  property prop_setup_write_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> $stable(PWRITE);
  endproperty
  AST_APB3_SETUP_WRITE_STABLE: assert property (prop_setup_write_stable)
    else $error("[APB3 FAIL] PWRITE changed during setup phase at %t", $time);

  property prop_setup_wdata_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE && PWRITE) |=> $stable(PWDATA);
  endproperty
  AST_APB3_SETUP_WDATA_STABLE: assert property (prop_setup_wdata_stable)
    else $error("[APB3 FAIL] PWDATA changed during setup phase at %t", $time);

  // ----------------------------------------------------------
  // R4: Access phase (PSEL=1, PENABLE=1, PREADY=0) — signals stable
  // ----------------------------------------------------------
  property prop_access_addr_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=> $stable(PADDR);
  endproperty
  AST_APB3_ACCESS_ADDR_STABLE: assert property (prop_access_addr_stable)
    else $error("[APB3 FAIL] PADDR changed during access phase at %t", $time);

  property prop_access_write_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=> $stable(PWRITE);
  endproperty
  AST_APB3_ACCESS_WRITE_STABLE: assert property (prop_access_write_stable)
    else $error("[APB3 FAIL] PWRITE changed during access phase at %t", $time);

  property prop_access_wdata_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PWRITE && !PREADY) |=> $stable(PWDATA);
  endproperty
  AST_APB3_ACCESS_WDATA_STABLE: assert property (prop_access_wdata_stable)
    else $error("[APB3 FAIL] PWDATA changed during access phase at %t", $time);

  // ----------------------------------------------------------
  // R5: PREADY must assert within MAX_WAIT cycles of PENABLE
  // ----------------------------------------------------------
  property prop_pready_timeout;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PENABLE) |-> ##[0:MAX_WAIT] PREADY;
  endproperty
  AST_APB3_PREADY_TIMEOUT: assert property (prop_pready_timeout)
    else $error("[APB3 FAIL] PREADY not asserted within %0d cycles at %t", MAX_WAIT, $time);

  // ----------------------------------------------------------
  // R6: PSLVERR valid only at end of access phase (PSEL=1, PENABLE=1, PREADY=1)
  // ----------------------------------------------------------
  property prop_pslverr_only_at_transfer_end;
    @(posedge PCLK) disable iff (!PRESETn)
    PSLVERR |-> (PSEL && PENABLE && PREADY);
  endproperty
  AST_APB3_PSLVERR_VALID: assert property (prop_pslverr_only_at_transfer_end)
    else $error("[APB3 FAIL] PSLVERR outside completed access phase at %t", $time);

  // ----------------------------------------------------------
  // R7: After transfer completes, PSEL must deassert or restart setup
  //     i.e., PENABLE must deassert after PREADY
  // ----------------------------------------------------------
  property prop_penable_deasserts_after_transfer;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY) |=> !PENABLE;
  endproperty
  AST_APB3_PENABLE_DEASSERTS: assert property (prop_penable_deasserts_after_transfer)
    else $error("[APB3 FAIL] PENABLE not deasserted after transfer completes at %t", $time);

  // ----------------------------------------------------------
  // Cover
  // ----------------------------------------------------------
  COV_APB3_WRITE_OK:    cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY && !PSLVERR);
  COV_APB3_READ_OK:     cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY && !PSLVERR);
  COV_APB3_WRITE_ERR:   cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY &&  PSLVERR);
  COV_APB3_READ_ERR:    cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY &&  PSLVERR);
  COV_APB3_WAIT_STATE:  cover property (@(posedge PCLK) PSEL && PENABLE && !PREADY);
  COV_APB3_BACK2BACK:   cover property (@(posedge PCLK) (PSEL && PENABLE && PREADY) ##1 PSEL);

endmodule
