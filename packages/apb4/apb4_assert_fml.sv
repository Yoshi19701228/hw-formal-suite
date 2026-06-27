// ============================================================
// APB4 Assertion Module — Formal Verification
// Spec: AMBA 4 APB Protocol Specification (ARM IHI0024E)
//
// Usage:
//   1. Instantiate apb4_helper and connect outputs to this module.
//   2. Bind or instantiate alongside DUT.
//
//   apb4_helper #(.DATA_W(32), .MAX_WAIT(16)) u_hlp (
//     .clk, .rst_n, .psel, .penable, .pwrite, .pstrb, .pprot, .pready,
//     .cnt_pready_wait, .pready_timeout, .pstrb_changed
//   );
//   apb4_assert_fml #(.ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)) u_fml (.*);
// ============================================================
module apb4_assert_fml
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
  input logic                          pready_timeout,
  input logic                          pstrb_changed
);

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // PENABLE follows PSEL by exactly 1 cycle
  property prop_penable_follows_psel;
    @(posedge clk) disable iff (!rst_n)
    $rose(psel) |=> penable;
  endproperty
  AST_APB4_PENABLE_FOLLOWS_PSEL: assert property (prop_penable_follows_psel);

  // PENABLE requires PSEL
  property prop_penable_requires_psel;
    @(posedge clk) disable iff (!rst_n)
    penable |-> psel;
  endproperty
  AST_APB4_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel);

  // Setup phase: paddr, pwrite, pwdata, pstrb, pprot stable
  property prop_setup_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(paddr);
  endproperty
  AST_APB4_SETUP_ADDR_STABLE: assert property (prop_setup_addr_stable);

  property prop_setup_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pwrite);
  endproperty
  AST_APB4_SETUP_WRITE_STABLE: assert property (prop_setup_write_stable);

  property prop_setup_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable && pwrite) |=> $stable(pwdata);
  endproperty
  AST_APB4_SETUP_WDATA_STABLE: assert property (prop_setup_wdata_stable);

  property prop_setup_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pstrb);
  endproperty
  AST_APB4_SETUP_PSTRB_STABLE: assert property (prop_setup_pstrb_stable);

  property prop_setup_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pprot);
  endproperty
  AST_APB4_SETUP_PPROT_STABLE: assert property (prop_setup_pprot_stable);

  // Access phase: signals stable while PREADY=0
  property prop_access_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(paddr);
  endproperty
  AST_APB4_ACCESS_ADDR_STABLE: assert property (prop_access_addr_stable);

  property prop_access_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pwrite);
  endproperty
  AST_APB4_ACCESS_WRITE_STABLE: assert property (prop_access_write_stable);

  property prop_access_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite && !pready) |=> $stable(pwdata);
  endproperty
  AST_APB4_ACCESS_WDATA_STABLE: assert property (prop_access_wdata_stable);

  property prop_access_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pstrb);
  endproperty
  AST_APB4_ACCESS_PSTRB_STABLE: assert property (prop_access_pstrb_stable);

  property prop_access_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pprot);
  endproperty
  AST_APB4_ACCESS_PPROT_STABLE: assert property (prop_access_pprot_stable);

  // PREADY timeout (via helper counter — avoids ##[0:N] in formal)
  property prop_pready_no_timeout;
    @(posedge clk) disable iff (!rst_n)
    !pready_timeout;
  endproperty
  AST_APB4_PREADY_TIMEOUT: assert property (prop_pready_no_timeout);

  // PSLVERR valid only at end of access phase
  property prop_pslverr_only_at_transfer_end;
    @(posedge clk) disable iff (!rst_n)
    pslverr |-> (psel && penable && pready);
  endproperty
  AST_APB4_PSLVERR_VALID: assert property (prop_pslverr_only_at_transfer_end);

  // PENABLE deasserts after transfer completes
  property prop_penable_deasserts_after_transfer;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pready) |=> !penable;
  endproperty
  AST_APB4_PENABLE_DEASSERTS: assert property (prop_penable_deasserts_after_transfer);

  // PSTRB must have at least one byte active during a write
  property prop_pstrb_valid_write;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite) |-> pstrb != '0;
  endproperty
  AST_APB4_PSTRB_VALID_WRITE: assert property (prop_pstrb_valid_write);

  // PSTRB must not change during setup phase (from helper)
  property prop_no_pstrb_change;
    @(posedge clk) disable iff (!rst_n)
    !pstrb_changed;
  endproperty
  AST_APB4_NO_PSTRB_CHANGE: assert property (prop_no_pstrb_change);

  // ----------------------------------------------------------
  // 2. Reachability
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

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // PRESETn must be held low for at least 4 cycles at startup
  property assume_reset_duration;
    @(posedge clk) $fell(rst_n) |-> !rst_n [*4];
  endproperty
  ENV_APB4_RESET_DURATION: assume property (assume_reset_duration);

  // Master must not assert PSEL and PENABLE simultaneously (setup phase required first)
  property assume_no_direct_penable;
    @(posedge clk) disable iff (!rst_n)
    $rose(penable) |-> $past(psel);
  endproperty
  ENV_APB4_NO_DIRECT_PENABLE: assume property (assume_no_direct_penable);

endmodule
