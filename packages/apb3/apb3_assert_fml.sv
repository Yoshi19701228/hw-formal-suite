// ============================================================
// APB3 Assertion Module — Formal Verification
// Spec: AMBA 3 APB Protocol Specification (ARM IHI0024C)
//
// Usage (non-intrusive bind):
//   bind apb3_slave apb3_assert_fml #(.ADDR_W(32), .DATA_W(32)) u_fml (.*);
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
  input logic [DATA_W-1:0] PRDATA
);

  // ============================================================
  // [Helper Logic] PREADY timeout counter
  // Replaces ##[0:MAX_WAIT] PREADY — avoids state-space explosion
  // ============================================================
  reg [$clog2(MAX_WAIT+1)-1:0] cnt_pready_wait;
  reg                          pready_timeout;

  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      cnt_pready_wait <= '0;
      pready_timeout  <= 1'b0;
    end else begin
      if (PSEL && PENABLE && !PREADY)
        cnt_pready_wait <= cnt_pready_wait + 1;
      else
        cnt_pready_wait <= '0;

      pready_timeout <= (cnt_pready_wait >= MAX_WAIT - 1) && PSEL && PENABLE && !PREADY;
    end
  end

  // ============================================================
  // 1. Safety
  // ============================================================

  // Every setup phase must transition to access phase in the next cycle
  property prop_setup_to_access;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> PENABLE;
  endproperty
  AST_APB3_SETUP_TO_ACCESS: assert property (prop_setup_to_access);

  // PENABLE requires PSEL
  property prop_penable_requires_psel;
    @(posedge PCLK) disable iff (!PRESETn)
    PENABLE |-> PSEL;
  endproperty
  AST_APB3_PENABLE_REQUIRES_PSEL: assert property (prop_penable_requires_psel);

  // Setup phase: PADDR, PWRITE, PWDATA stable through access phase
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

  // Access phase: signals stable while waiting for PREADY
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

  // PREADY must arrive within MAX_WAIT cycles
  property prop_pready_no_timeout;
    @(posedge PCLK) disable iff (!PRESETn)
    !pready_timeout;
  endproperty
  AST_APB3_PREADY_TIMEOUT: assert property (prop_pready_no_timeout);

  // PSLVERR valid only at end of access phase
  property prop_pslverr_valid;
    @(posedge PCLK) disable iff (!PRESETn)
    PSLVERR |-> (PSEL && PENABLE && PREADY);
  endproperty
  AST_APB3_PSLVERR_VALID: assert property (prop_pslverr_valid);

  // PENABLE deasserts one cycle after transfer completes
  property prop_penable_deasserts;
    @(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY) |=> !PENABLE;
  endproperty
  AST_APB3_PENABLE_DEASSERTS: assert property (prop_penable_deasserts);

  // ============================================================
  // 2. Reachability
  // ============================================================
  COV_APB3_WRITE_OK:   cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY && !PSLVERR);
  COV_APB3_READ_OK:    cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY && !PSLVERR);
  COV_APB3_WRITE_ERR:  cover property (@(posedge PCLK) PSEL && PENABLE &&  PWRITE && PREADY &&  PSLVERR);
  COV_APB3_READ_ERR:   cover property (@(posedge PCLK) PSEL && PENABLE && !PWRITE && PREADY &&  PSLVERR);
  COV_APB3_WAIT_STATE: cover property (@(posedge PCLK) PSEL && PENABLE && !PREADY);
  COV_APB3_BACK2BACK:  cover property (@(posedge PCLK) (PSEL && PENABLE && PREADY) ##1 PSEL);

  // ============================================================
  // 3. Environment Constraints
  // ============================================================

  // PRESETn must be asserted for at least 1 full cycle at startup
  property assume_reset_duration;
    @(posedge PCLK) $fell(PRESETn) |-> !PRESETn [*1:$] ##1 PRESETn;
  endproperty
  ENV_APB3_RESET_DURATION: assume property (assume_reset_duration);

  // Master must go through setup phase before asserting PENABLE
  property assume_no_direct_penable;
    @(posedge PCLK) disable iff (!PRESETn)
    $rose(PENABLE) |-> $past(PSEL && !PENABLE);
  endproperty
  ENV_APB3_NO_DIRECT_PENABLE: assume property (assume_no_direct_penable);

endmodule
