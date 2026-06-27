// ============================================================
// APB5 Assertion Module — Formal Verification
// Spec: AMBA 5 APB Protocol Specification (ARM IHI0024F)
//
// Usage:
//   1. Instantiate apb5_helper and connect outputs to this module.
//   2. Bind or instantiate alongside DUT.
//
//   apb5_helper #(.DATA_W(32), .USER_W(4), .MAX_WAIT(16), .MAX_WAKEUP(8)) u_hlp (
//     .clk, .rst_n, .psel, .penable, .pwrite, .pstrb, .pprot, .pready,
//     .pwakeup, .pauser, .pwuser,
//     .cnt_pready_wait, .pready_timeout,
//     .cnt_wakeup, .wakeup_timeout,
//     .pauser_changed, .pwuser_changed
//   );
//   apb5_assert_fml #(.ADDR_W(32), .DATA_W(32), .USER_W(4),
//                     .MAX_WAIT(16), .MAX_WAKEUP(8)) u_fml (.*);
// ============================================================
module apb5_assert_fml
  import apb5_pkg::*;
#(
  parameter int ADDR_W     = 32,
  parameter int DATA_W     = 32,
  parameter int USER_W     = 4,
  parameter int MAX_WAIT   = APB5_MAX_WAIT_CYCLES,
  parameter int MAX_WAKEUP = APB5_MAX_WAKEUP_CYCLES
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
  // APB5-specific signals
  input logic                        pwakeup,
  input logic                        pnse,
  input logic [USER_W-1:0]           pauser,
  input logic [USER_W-1:0]           pwuser,
  input logic [USER_W-1:0]           pruser,
  input logic [USER_W-1:0]           pbuser,
  // From apb5_helper
  input logic                             pready_timeout,
  input logic                             wakeup_timeout,
  input logic                             pauser_changed,
  input logic                             pwuser_changed
);

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // PENABLE follows PSEL by exactly 1 cycle
  property prop_penable_follows_psel;
    @(posedge clk) disable iff (!rst_n)
    $rose(psel) |=> penable;
  endproperty
  AST_APB5_PENABLE_FOLLOWS_PSEL: assert property (prop_penable_follows_psel);

  // PENABLE requires PSEL
  property prop_penable_requires_psel;
    @(posedge clk) disable iff (!rst_n)
    penable |-> psel;
  endproperty
  AST_APB5_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel);

  // Setup phase: address, control, strobe, prot, pauser stable
  property prop_setup_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(paddr);
  endproperty
  AST_APB5_SETUP_ADDR_STABLE: assert property (prop_setup_addr_stable);

  property prop_setup_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pwrite);
  endproperty
  AST_APB5_SETUP_WRITE_STABLE: assert property (prop_setup_write_stable);

  property prop_setup_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable && pwrite) |=> $stable(pwdata);
  endproperty
  AST_APB5_SETUP_WDATA_STABLE: assert property (prop_setup_wdata_stable);

  property prop_setup_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pstrb);
  endproperty
  AST_APB5_SETUP_PSTRB_STABLE: assert property (prop_setup_pstrb_stable);

  property prop_setup_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pprot);
  endproperty
  AST_APB5_SETUP_PPROT_STABLE: assert property (prop_setup_pprot_stable);

  property prop_setup_pauser_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && !penable) |=> $stable(pauser);
  endproperty
  AST_APB5_SETUP_USER_STABLE: assert property (prop_setup_pauser_stable);

  // Access phase: signals stable while PREADY=0
  property prop_access_addr_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(paddr);
  endproperty
  AST_APB5_ACCESS_ADDR_STABLE: assert property (prop_access_addr_stable);

  property prop_access_write_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pwrite);
  endproperty
  AST_APB5_ACCESS_WRITE_STABLE: assert property (prop_access_write_stable);

  property prop_access_wdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite && !pready) |=> $stable(pwdata);
  endproperty
  AST_APB5_ACCESS_WDATA_STABLE: assert property (prop_access_wdata_stable);

  property prop_access_pstrb_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pstrb);
  endproperty
  AST_APB5_ACCESS_PSTRB_STABLE: assert property (prop_access_pstrb_stable);

  property prop_access_pprot_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && !pready) |=> $stable(pprot);
  endproperty
  AST_APB5_ACCESS_PPROT_STABLE: assert property (prop_access_pprot_stable);

  property prop_access_pwuser_stable;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite && !pready) |=> $stable(pwuser);
  endproperty
  AST_APB5_ACCESS_USER_STABLE: assert property (prop_access_pwuser_stable);

  // PREADY timeout (via helper counter — avoids ##[0:N] in formal)
  property prop_pready_no_timeout;
    @(posedge clk) disable iff (!rst_n)
    !pready_timeout;
  endproperty
  AST_APB5_PREADY_TIMEOUT: assert property (prop_pready_no_timeout);

  // PSLVERR valid only at end of access phase
  property prop_pslverr_only_at_transfer_end;
    @(posedge clk) disable iff (!rst_n)
    pslverr |-> (psel && penable && pready);
  endproperty
  AST_APB5_PSLVERR_VALID: assert property (prop_pslverr_only_at_transfer_end);

  // PENABLE deasserts after transfer completes
  property prop_penable_deasserts_after_transfer;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pready) |=> !penable;
  endproperty
  AST_APB5_PENABLE_DEASSERTS: assert property (prop_penable_deasserts_after_transfer);

  // PSTRB must have at least one byte active during a write
  property prop_pstrb_valid_write;
    @(posedge clk) disable iff (!rst_n)
    (psel && penable && pwrite) |-> pstrb != '0;
  endproperty
  AST_APB5_PSTRB_VALID_WRITE: assert property (prop_pstrb_valid_write);

  // PAUSER must not change during setup phase
  property prop_no_pauser_change;
    @(posedge clk) disable iff (!rst_n)
    !pauser_changed;
  endproperty
  AST_APB5_NO_PAUSER_CHANGE: assert property (prop_no_pauser_change);

  // PWUSER must not change during write access phase
  property prop_no_pwuser_change;
    @(posedge clk) disable iff (!rst_n)
    !pwuser_changed;
  endproperty
  AST_APB5_NO_PWUSER_CHANGE: assert property (prop_no_pwuser_change);

  // Wakeup must not remain asserted beyond MAX_WAKEUP cycles without PSEL
  property prop_wakeup_no_timeout;
    @(posedge clk) disable iff (!rst_n)
    !wakeup_timeout;
  endproperty
  AST_APB5_WAKEUP_TIMEOUT: assert property (prop_wakeup_no_timeout);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------
  COV_APB5_WRITE_OK:      cover property (@(posedge clk) psel && penable &&  pwrite && pready && !pslverr);
  COV_APB5_READ_OK:       cover property (@(posedge clk) psel && penable && !pwrite && pready && !pslverr);
  COV_APB5_WRITE_ERR:     cover property (@(posedge clk) psel && penable &&  pwrite && pready &&  pslverr);
  COV_APB5_READ_ERR:      cover property (@(posedge clk) psel && penable && !pwrite && pready &&  pslverr);
  COV_APB5_WAIT_STATE:    cover property (@(posedge clk) psel && penable && !pready);
  COV_APB5_BACK_TO_BACK:  cover property (@(posedge clk) (psel && penable && pready) ##1 psel);
  COV_APB5_PARTIAL_WRITE: cover property (@(posedge clk) pwrite && psel && penable &&
                                           pstrb != {(DATA_W/8){1'b1}} && pstrb != '0);
  COV_APB5_PRIVILEGED:    cover property (@(posedge clk) pprot[0] && psel);
  COV_APB5_NON_SECURE:    cover property (@(posedge clk) pprot[1] && psel);
  COV_APB5_INSTRUCTION:   cover property (@(posedge clk) pprot[2] && psel);
  // APB5-specific cover points
  COV_APB5_WAKEUP:        cover property (@(posedge clk) pwakeup);
  COV_APB5_NSE:           cover property (@(posedge clk) pnse && psel);
  COV_APB5_WAKEUP_TO_PSEL: cover property (@(posedge clk) pwakeup ##[1:MAX_WAKEUP] psel);
  COV_APB5_PAUSER_SET:    cover property (@(posedge clk) |pauser && psel);
  COV_APB5_PBUSER_RESP:   cover property (@(posedge clk) |pbuser && psel && penable && pready);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // PRESETn must be held low for at least 4 cycles at startup
  property assume_reset_duration;
    @(posedge clk) $fell(rst_n) |-> !rst_n [*4];
  endproperty
  ENV_APB5_RESET_DURATION: assume property (assume_reset_duration);

  // Master must not assert PSEL and PENABLE simultaneously (setup phase required first)
  property assume_no_direct_penable;
    @(posedge clk) disable iff (!rst_n)
    $rose(penable) |-> $past(psel);
  endproperty
  ENV_APB5_NO_DIRECT_PENABLE: assume property (assume_no_direct_penable);

  // If PWAKEUP asserts, PSEL must follow within MAX_WAKEUP cycles
  property assume_wakeup_before_psel;
    @(posedge clk) disable iff (!rst_n)
    $rose(pwakeup) |-> ##[1:MAX_WAKEUP] psel;
  endproperty
  ENV_APB5_WAKEUP_BEFORE_PSEL: assume property (assume_wakeup_before_psel);

endmodule
