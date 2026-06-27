// ============================================================
// APB4 Assertion Module — Simulator
// Spec: AMBA 4 APB Protocol Specification (ARM IHI0024E)
//
// Usage (bind to DUT):
//   // 1. Instantiate helper
//   apb4_helper #(.DATA_W(32), .MAX_WAIT(16)) u_hlp (
//     .clk, .rst_n, .psel, .penable, .pwrite, .pstrb, .pprot, .pready,
//     .cnt_pready_wait, .pready_timeout, .pstrb_changed
//   );
//   // 2. Bind checker
//   bind <dut_module> apb4_assert_sim #(
//     .ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)
//   ) u_apb4_chk (.*);
// ============================================================
module apb4_assert_sim
  import apb4_pkg::*;
#(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int MAX_WAIT = APB4_MAX_WAIT_CYCLES
)(
  input logic                        clk,
  input logic                        rst_n,
  input logic                        psel,
  input logic                        penable,
  input logic                        pwrite,
  input logic [ADDR_W-1:0]           paddr,
  input logic [DATA_W-1:0]           pwdata,
  input logic [DATA_W/8-1:0]         pstrb,
  input logic [2:0]                  pprot,
  input logic                        pready,
  input logic [DATA_W-1:0]           prdata,
  input logic                        pslverr,
  // From apb4_helper
  input logic [$clog2(MAX_WAIT+1)-1:0] cnt_pready_wait,
  input logic                          pstrb_changed
);

  // ----------------------------------------------------------
  // R1: PENABLE must be asserted exactly 1 cycle after PSEL rises
  // ----------------------------------------------------------
  property prop_penable_follows_psel;
    @(posedge clk) disable iff (!rst_n)
    $rose(psel) |=> penable;
  endproperty
  AST_APB4_PENABLE_FOLLOWS_PSEL: assert property (prop_penable_follows_psel)
    else $error("[APB4 FAIL] PENABLE not asserted 1 cycle after PSEL at %t", $time);

  // ----------------------------------------------------------
  // R2: PENABLE must not be asserted without PSEL
  // ----------------------------------------------------------
  property prop_penable_requires_psel;
    @(posedge clk) disable iff (!rst_n)
    penable |-> psel;
  endproperty
  AST_APB4_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel)
    else $error("[APB4 FAIL] PENABLE asserted without PSEL at %t", $time);

  // ----------------------------------------------------------
  // R3: Setup phase (PSEL=1, PENABLE=0) — address, control, strobe, prot stable
  // ----------------------------------------------------------
  property prop_setup_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(paddr);
  endproperty
  AST_APB4_SETUP_ADDR_STABLE: assert property (prop_setup_addr_stable)
    else $error("[APB4 FAIL] PADDR changed during setup phase at %t", $time);

  property prop_setup_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pwrite);
  endproperty
  AST_APB4_SETUP_WRITE_STABLE: assert property (prop_setup_write_stable)
    else $error("[APB4 FAIL] PWRITE changed during setup phase at %t", $time);

  property prop_setup_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable && pwrite) |=> $stable(pwdata);
  endproperty
  AST_APB4_SETUP_WDATA_STABLE: assert property (prop_setup_wdata_stable)
    else $error("[APB4 FAIL] PWDATA changed during setup phase at %t", $time);

  property prop_setup_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pstrb);
  endproperty
  AST_APB4_SETUP_PSTRB_STABLE: assert property (prop_setup_pstrb_stable)
    else $error("[APB4 FAIL] PSTRB changed during setup phase at %t", $time);

  property prop_setup_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pprot);
  endproperty
  AST_APB4_SETUP_PPROT_STABLE: assert property (prop_setup_pprot_stable)
    else $error("[APB4 FAIL] PPROT changed during setup phase at %t", $time);

  // ----------------------------------------------------------
  // R4: Access phase (PSEL=1, PENABLE=1, PREADY=0) — signals stable
  // ----------------------------------------------------------
  property prop_access_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(paddr);
  endproperty
  AST_APB4_ACCESS_ADDR_STABLE: assert property (prop_access_addr_stable)
    else $error("[APB4 FAIL] PADDR changed during access phase at %t", $time);

  property prop_access_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pwrite);
  endproperty
  AST_APB4_ACCESS_WRITE_STABLE: assert property (prop_access_write_stable)
    else $error("[APB4 FAIL] PWRITE changed during access phase at %t", $time);

  property prop_access_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite && !pready) |=> $stable(pwdata);
  endproperty
  AST_APB4_ACCESS_WDATA_STABLE: assert property (prop_access_wdata_stable)
    else $error("[APB4 FAIL] PWDATA changed during access phase at %t", $time);

  property prop_access_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pstrb);
  endproperty
  AST_APB4_ACCESS_PSTRB_STABLE: assert property (prop_access_pstrb_stable)
    else $error("[APB4 FAIL] PSTRB changed during access phase at %t", $time);

  property prop_access_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pprot);
  endproperty
  AST_APB4_ACCESS_PPROT_STABLE: assert property (prop_access_pprot_stable)
    else $error("[APB4 FAIL] PPROT changed during access phase at %t", $time);

  // ----------------------------------------------------------
  // R5: PREADY must assert within MAX_WAIT cycles of PENABLE
  // ----------------------------------------------------------
  property prop_pready_timeout;
    @(posedge clk) disable iff (!rst_n)
    $rose(penable) |-> ##[0:MAX_WAIT] pready;
  endproperty
  AST_APB4_PREADY_TIMEOUT: assert property (prop_pready_timeout)
    else $error("[APB4 FAIL] PREADY not asserted within %0d cycles at %t", MAX_WAIT, $time);

  // ----------------------------------------------------------
  // R6: PSLVERR valid only at end of access phase (PSEL=1, PENABLE=1, PREADY=1)
  // ----------------------------------------------------------
  property prop_pslverr_only_at_transfer_end;
    @(posedge clk) disable iff (!rst_n)
    pslverr |-> (psel && penable && pready);
  endproperty
  AST_APB4_PSLVERR_VALID: assert property (prop_pslverr_only_at_transfer_end)
    else $error("[APB4 FAIL] PSLVERR outside completed access phase at %t", $time);

  // ----------------------------------------------------------
  // R7: PENABLE must deassert after transfer completes
  // ----------------------------------------------------------
  property prop_penable_deasserts_after_transfer;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pready) |=> !penable;
  endproperty
  AST_APB4_PENABLE_DEASSERTS: assert property (prop_penable_deasserts_after_transfer)
    else $error("[APB4 FAIL] PENABLE not deasserted after transfer completes at %t", $time);

  // ----------------------------------------------------------
  // R8: PSTRB must have at least one byte active during a write
  //     (PSTRB is UNPREDICTABLE on reads per AMBA APB4 spec)
  // ----------------------------------------------------------
  property prop_pstrb_valid_write;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite) |-> pstrb != '0;
  endproperty
  AST_APB4_PSTRB_VALID_WRITE: assert property (prop_pstrb_valid_write)
    else $error("[APB4 FAIL] PSTRB is all-zero during write transfer at %t", $time);

  // ----------------------------------------------------------
  // R9: PSTRB must not change during setup phase (from helper)
  // ----------------------------------------------------------
  property prop_no_pstrb_change;
    @(posedge clk) disable iff (!rst_n)
    !pstrb_changed;
  endproperty
  AST_APB4_NO_PSTRB_CHANGE: assert property (prop_no_pstrb_change)
    else $error("[APB4 FAIL] PSTRB changed while PSEL=1 before PENABLE at %t", $time);

  // ----------------------------------------------------------
  // Cover
  // ----------------------------------------------------------
  COV_APB4_WRITE_OK:     cover property (@(posedge clk) psel && penable &&  pwrite && pready && !pslverr);
  COV_APB4_READ_OK:      cover property (@(posedge clk) psel && penable && !pwrite && pready && !pslverr);
  COV_APB4_WRITE_ERR:    cover property (@(posedge clk) psel && penable &&  pwrite && pready &&  pslverr);
  COV_APB4_READ_ERR:     cover property (@(posedge clk) psel && penable && !pwrite && pready &&  pslverr);
  COV_APB4_WAIT_STATE:   cover property (@(posedge clk) psel && penable && !pready);
  COV_APB4_BACK_TO_BACK: cover property (@(posedge clk) (psel && penable && pready) ##1 psel);
  COV_APB4_PARTIAL_WRITE: cover property (@(posedge clk) pwrite && psel && penable &&
                                           pstrb != {(DATA_W/8){1'b1}} && pstrb != '0);
  COV_APB4_PRIVILEGED:   cover property (@(posedge clk) pprot[0] && psel);
  COV_APB4_NON_SECURE:   cover property (@(posedge clk) pprot[1] && psel);
  COV_APB4_INSTRUCTION:  cover property (@(posedge clk) pprot[2] && psel);

endmodule
