// ============================================================
// APB3 Assertion Module — Formal Verification
// Spec: AMBA 3 APB Protocol Specification (ARM IHI0024C)
//
// Usage:
//   1. Instantiate apb3_helper and connect outputs to this module.
//   2. Bind or instantiate alongside DUT.
//
//   apb3_helper     #(.MAX_WAIT(16)) u_hlp (.PCLK, .PRESETn, .PSEL, .PENABLE, .PREADY,
//                                            .cnt_pready_wait, .pready_timeout);
//   apb3_assert_fml #(.ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)) u_fml (.*);
// ============================================================
module apb3_assert_fml
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
  input logic [DATA_W-1:0] PRDATA,
  // From apb3_helper
  input logic              pready_timeout
);

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // PENABLE follows PSEL by exactly 1 cycle
  property prop_penable_follows_psel;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PSEL) |=> PENABLE;
  endproperty
  AST_APB3_PENABLE_FOLLOWS_PSEL: assert property (prop_penable_follows_psel);

  // PENABLE requires PSEL
  property prop_penable_requires_psel;
    @(posedge PCLK) disable iff (!PRESETn)
    PENABLE |-> PSEL;
  endproperty
  AST_APB3_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel);

  // Setup phase: PADDR, PWRITE stable
  property prop_setup_addr_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> $stable(PADDR);
  endproperty
  AST_APB3_SETUP_ADDR_STABLE: assert property (prop_setup_addr_stable);

  property prop_setup_write_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> $stable(PWRITE);
  endproperty
  AST_APB3_SETUP_WRITE_STABLE: assert property (prop_setup_write_stable);

  property prop_setup_wdata_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE && PWRITE) |=> $stable(PWDATA);
  endproperty
  AST_APB3_SETUP_WDATA_STABLE: assert property (prop_setup_wdata_stable);

  // Access phase: signals stable while PREADY=0
  property prop_access_addr_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=> $stable(PADDR);
  endproperty
  AST_APB3_ACCESS_ADDR_STABLE: assert property (prop_access_addr_stable);

  property prop_access_write_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=> $stable(PWRITE);
  endproperty
  AST_APB3_ACCESS_WRITE_STABLE: assert property (prop_access_write_stable);

  property prop_access_wdata_stable;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PWRITE && !PREADY) |=> $stable(PWDATA);
  endproperty
  AST_APB3_ACCESS_WDATA_STABLE: assert property (prop_access_wdata_stable);

  // PREADY timeout (via helper counter — avoids ##[0:N] in formal)
  property prop_pready_no_timeout;
    @(posedge PCLK) disable iff (!PRESETn)
    !pready_timeout;
  endproperty
  AST_APB3_PREADY_TIMEOUT: assert property (prop_pready_no_timeout);

  // PSLVERR valid only at end of access phase
  property prop_pslverr_only_at_transfer_end;
    @(posedge PCLK) disable iff (!PRESETn)
    PSLVERR |-> (PSEL && PENABLE && PREADY);
  endproperty
  AST_APB3_PSLVERR_VALID: assert property (prop_pslverr_only_at_transfer_end);

  // PENABLE deasserts after transfer completes
  property prop_penable_deasserts_after_transfer;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY) |=> !PENABLE;
  endproperty
  AST_APB3_PENABLE_DEASSERTS: assert property (prop_penable_deasserts_after_transfer);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------
  COV_APB3_WRITE_OK:   cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY && !PSLVERR);
  COV_APB3_READ_OK:    cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY && !PSLVERR);
  COV_APB3_WRITE_ERR:  cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY &&  PSLVERR);
  COV_APB3_READ_ERR:   cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY &&  PSLVERR);
  COV_APB3_WAIT_STATE: cover property (@(posedge PCLK) PSEL && PENABLE && !PREADY);
  COV_APB3_BACK2BACK:  cover property (@(posedge PCLK) (PSEL && PENABLE && PREADY) ##1 PSEL);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // PRESETn must be asserted for at least 1 full cycle at startup
  property assume_reset_duration;
    @(posedge PCLK) $fell(PRESETn) |-> !PRESETn [*1:$] ##1 PRESETn;
  endproperty
  ENV_APB3_RESET_DURATION: assume property (assume_reset_duration);

  // Master must not assert PSEL and PENABLE simultaneously (setup phase required first)
  property assume_no_direct_penable;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PENABLE) |-> $past(PSEL && !PENABLE);
  endproperty
  ENV_APB3_NO_DIRECT_PENABLE: assume property (assume_no_direct_penable);

endmodule
