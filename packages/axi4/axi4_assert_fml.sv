// ============================================================
// AXI4 Assertion Module — Formal Verification
// Spec: AMBA AXI and ACE Protocol Specification (ARM IHI0022H)
//
// Usage (bind):
//   bind <dut_module> axi4_assert_fml #(.ADDR_W(32), .DATA_W(64)) u_fml (.*);
// ============================================================
module axi4_assert_fml
  import axi4_pkg::*;
#(
  parameter int ADDR_W       = 32,
  parameter int DATA_W       = 64,
  parameter int ID_W         = 4,
  parameter int MAX_WAIT     = AXI4_MAX_WAIT_CYCLES,
  parameter int MAX_OUTSTANDING = AXI4_MAX_OUTSTANDING
)(
  input logic              ACLK,
  input logic              ARESETn,

  // AW
  input logic              AWVALID,
  input logic              AWREADY,
  input logic [ID_W-1:0]   AWID,
  input logic [ADDR_W-1:0] AWADDR,
  input logic [7:0]        AWLEN,
  input logic [2:0]        AWSIZE,
  input logic [1:0]        AWBURST,

  // W
  input logic              WVALID,
  input logic              WREADY,
  input logic [DATA_W-1:0] WDATA,
  input logic [DATA_W/8-1:0] WSTRB,
  input logic              WLAST,

  // B
  input logic              BVALID,
  input logic              BREADY,
  input logic [ID_W-1:0]   BID,
  input logic [1:0]        BRESP,

  // AR
  input logic              ARVALID,
  input logic              ARREADY,
  input logic [ID_W-1:0]   ARID,
  input logic [ADDR_W-1:0] ARADDR,
  input logic [7:0]        ARLEN,
  input logic [2:0]        ARSIZE,
  input logic [1:0]        ARBURST,

  // R
  input logic              RVALID,
  input logic              RREADY,
  input logic [ID_W-1:0]   RID,
  input logic [DATA_W-1:0] RDATA,
  input logic [1:0]        RRESP,
  input logic              RLAST
);

  // ============================================================
  // [Helper Logic] — handshake timeout counters, write beat
  //   tracking, outstanding transaction counters
  //   (inlined from axi4_helper.v)
  // ============================================================
  reg [$clog2(MAX_WAIT+1)-1:0] cnt_aw, cnt_w, cnt_b, cnt_ar, cnt_r;
  reg               aw_timeout;
  reg               w_timeout;
  reg               b_timeout;
  reg               ar_timeout;
  reg               r_timeout;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      cnt_aw <= '0; aw_timeout <= 1'b0;
      cnt_w  <= '0; w_timeout  <= 1'b0;
      cnt_b  <= '0; b_timeout  <= 1'b0;
      cnt_ar <= '0; ar_timeout <= 1'b0;
      cnt_r  <= '0; r_timeout  <= 1'b0;
    end else begin
      // AW
      if (AWVALID && !AWREADY) cnt_aw <= cnt_aw + 1; else cnt_aw <= '0;
      aw_timeout <= (cnt_aw >= MAX_WAIT - 1) && AWVALID && !AWREADY;
      // W
      if (WVALID  && !WREADY)  cnt_w  <= cnt_w  + 1; else cnt_w  <= '0;
      w_timeout  <= (cnt_w  >= MAX_WAIT - 1) && WVALID  && !WREADY;
      // B
      if (BVALID  && !BREADY)  cnt_b  <= cnt_b  + 1; else cnt_b  <= '0;
      b_timeout  <= (cnt_b  >= MAX_WAIT - 1) && BVALID  && !BREADY;
      // AR
      if (ARVALID && !ARREADY) cnt_ar <= cnt_ar + 1; else cnt_ar <= '0;
      ar_timeout <= (cnt_ar >= MAX_WAIT - 1) && ARVALID && !ARREADY;
      // R
      if (RVALID  && !RREADY)  cnt_r  <= cnt_r  + 1; else cnt_r  <= '0;
      r_timeout  <= (cnt_r  >= MAX_WAIT - 1) && RVALID  && !RREADY;
    end
  end

  reg  [7:0]        snap_awlen;
  reg  [7:0]        cnt_w_beats;
  reg               wlast_mismatch;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      snap_awlen      <= '0;
      cnt_w_beats     <= '0;
      wlast_mismatch  <= 1'b0;
    end else begin
      if (AWVALID && AWREADY)
        snap_awlen <= AWLEN;

      if (WVALID && WREADY) begin
        if (WLAST)
          cnt_w_beats <= '0;
        else
          cnt_w_beats <= cnt_w_beats + 1;

        // WLAST must fire exactly when beat count == AWLEN
        wlast_mismatch <= WLAST && (cnt_w_beats != snap_awlen);
      end else begin
        wlast_mismatch <= 1'b0;
      end
    end
  end

  reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_aw_outstanding;
  reg               aw_overflow;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      cnt_aw_outstanding <= '0;
      aw_overflow        <= 1'b0;
    end else begin
      case ({AWVALID && AWREADY, BVALID && BREADY})
        2'b10: cnt_aw_outstanding <= cnt_aw_outstanding + 1;
        2'b01: cnt_aw_outstanding <= cnt_aw_outstanding - 1;
        default: ;
      endcase
      aw_overflow <= (cnt_aw_outstanding >= MAX_OUTSTANDING) && AWVALID && AWREADY;
    end
  end

  reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_ar_outstanding;
  reg               ar_overflow;

  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      cnt_ar_outstanding <= '0;
      ar_overflow        <= 1'b0;
    end else begin
      case ({ARVALID && ARREADY, RVALID && RREADY && RLAST})
        2'b10: cnt_ar_outstanding <= cnt_ar_outstanding + 1;
        2'b01: cnt_ar_outstanding <= cnt_ar_outstanding - 1;
        default: ;
      endcase
      ar_overflow <= (cnt_ar_outstanding >= MAX_OUTSTANDING) && ARVALID && ARREADY;
    end
  end

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // Reset: all VALID signals must be deasserted
  property prop_valid_low_during_reset;
    @(posedge ACLK)
    !ARESETn |-> (!AWVALID && !WVALID && !BVALID && !ARVALID && !RVALID);
  endproperty
  AST_AXI4_VALID_IN_RESET: assert property (prop_valid_low_during_reset);

  // --- AW Channel ---
  property prop_aw_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=> AWVALID;
  endproperty
  AST_AXI4_AW_VALID_STABLE: assert property (prop_aw_valid_stable);

  property prop_aw_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (AWVALID && !AWREADY) |=>
      ($stable(AWID) && $stable(AWADDR) && $stable(AWLEN) &&
       $stable(AWSIZE) && $stable(AWBURST));
  endproperty
  AST_AXI4_AW_SIGNALS_STABLE: assert property (prop_aw_signals_stable);

  property prop_aw_size_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> (2**AWSIZE <= DATA_W/8);
  endproperty
  AST_AXI4_AW_SIZE_VALID: assert property (prop_aw_size_valid);

  property prop_aw_burst_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> (AWBURST != 2'b11);
  endproperty
  AST_AXI4_AW_BURST_VALID: assert property (prop_aw_burst_valid);

  // No timeout on AW channel (helper counter replaces ##[1:MAX_WAIT])
  property prop_aw_no_timeout;
    @(posedge ACLK) disable iff (!ARESETn) !aw_timeout;
  endproperty
  AST_AXI4_AW_TIMEOUT: assert property (prop_aw_no_timeout);

  // No outstanding overflow
  property prop_aw_no_overflow;
    @(posedge ACLK) disable iff (!ARESETn) !aw_overflow;
  endproperty
  AST_AXI4_AW_OVERFLOW: assert property (prop_aw_no_overflow);

  // --- W Channel ---
  property prop_w_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=> WVALID;
  endproperty
  AST_AXI4_W_VALID_STABLE: assert property (prop_w_valid_stable);

  property prop_w_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (WVALID && !WREADY) |=>
      ($stable(WDATA) && $stable(WSTRB) && $stable(WLAST));
  endproperty
  AST_AXI4_W_SIGNALS_STABLE: assert property (prop_w_signals_stable);

  property prop_w_no_timeout;
    @(posedge ACLK) disable iff (!ARESETn) !w_timeout;
  endproperty
  AST_AXI4_W_TIMEOUT: assert property (prop_w_no_timeout);

  // WLAST must fire on the correct beat (helper tracks this)
  property prop_wlast_correct;
    @(posedge ACLK) disable iff (!ARESETn) !wlast_mismatch;
  endproperty
  AST_AXI4_WLAST_CORRECT: assert property (prop_wlast_correct);

  // --- B Channel ---
  property prop_b_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !BREADY) |=> BVALID;
  endproperty
  AST_AXI4_B_VALID_STABLE: assert property (prop_b_valid_stable);

  property prop_b_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (BVALID && !BREADY) |=> ($stable(BID) && $stable(BRESP));
  endproperty
  AST_AXI4_B_SIGNALS_STABLE: assert property (prop_b_signals_stable);

  property prop_bresp_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    BVALID |-> (BRESP inside {AXI4_OKAY, AXI4_EXOKAY, AXI4_SLVERR, AXI4_DECERR});
  endproperty
  AST_AXI4_BRESP_VALID: assert property (prop_bresp_valid);

  property prop_b_no_timeout;
    @(posedge ACLK) disable iff (!ARESETn) !b_timeout;
  endproperty
  AST_AXI4_B_TIMEOUT: assert property (prop_b_no_timeout);

  // --- AR Channel ---
  property prop_ar_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=> ARVALID;
  endproperty
  AST_AXI4_AR_VALID_STABLE: assert property (prop_ar_valid_stable);

  property prop_ar_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (ARVALID && !ARREADY) |=>
      ($stable(ARID) && $stable(ARADDR) && $stable(ARLEN) &&
       $stable(ARSIZE) && $stable(ARBURST));
  endproperty
  AST_AXI4_AR_SIGNALS_STABLE: assert property (prop_ar_signals_stable);

  property prop_ar_size_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    ARVALID |-> (2**ARSIZE <= DATA_W/8);
  endproperty
  AST_AXI4_AR_SIZE_VALID: assert property (prop_ar_size_valid);

  property prop_ar_no_timeout;
    @(posedge ACLK) disable iff (!ARESETn) !ar_timeout;
  endproperty
  AST_AXI4_AR_TIMEOUT: assert property (prop_ar_no_timeout);

  property prop_ar_no_overflow;
    @(posedge ACLK) disable iff (!ARESETn) !ar_overflow;
  endproperty
  AST_AXI4_AR_OVERFLOW: assert property (prop_ar_no_overflow);

  // --- R Channel ---
  property prop_r_valid_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=> RVALID;
  endproperty
  AST_AXI4_R_VALID_STABLE: assert property (prop_r_valid_stable);

  property prop_r_signals_stable;
    @(posedge ACLK) disable iff (!ARESETn)
    (RVALID && !RREADY) |=>
      ($stable(RID) && $stable(RDATA) && $stable(RRESP) && $stable(RLAST));
  endproperty
  AST_AXI4_R_SIGNALS_STABLE: assert property (prop_r_signals_stable);

  property prop_rresp_valid;
    @(posedge ACLK) disable iff (!ARESETn)
    RVALID |-> (RRESP inside {AXI4_OKAY, AXI4_EXOKAY, AXI4_SLVERR, AXI4_DECERR});
  endproperty
  AST_AXI4_RRESP_VALID: assert property (prop_rresp_valid);

  property prop_r_no_timeout;
    @(posedge ACLK) disable iff (!ARESETn) !r_timeout;
  endproperty
  AST_AXI4_R_TIMEOUT: assert property (prop_r_no_timeout);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------
  COV_AXI4_AW_HANDSHAKE:  cover property (@(posedge ACLK) AWVALID && AWREADY);
  COV_AXI4_W_HANDSHAKE:   cover property (@(posedge ACLK) WVALID  && WREADY);
  COV_AXI4_B_HANDSHAKE:   cover property (@(posedge ACLK) BVALID  && BREADY);
  COV_AXI4_AR_HANDSHAKE:  cover property (@(posedge ACLK) ARVALID && ARREADY);
  COV_AXI4_R_HANDSHAKE:   cover property (@(posedge ACLK) RVALID  && RREADY);

  COV_AXI4_WLAST:         cover property (@(posedge ACLK) WVALID && WREADY && WLAST);
  COV_AXI4_RLAST:         cover property (@(posedge ACLK) RVALID && RREADY && RLAST);
  COV_AXI4_B_SLVERR:      cover property (@(posedge ACLK) BVALID && BREADY && BRESP == AXI4_SLVERR);
  COV_AXI4_R_SLVERR:      cover property (@(posedge ACLK) RVALID && RREADY && RRESP == AXI4_SLVERR);

  COV_AXI4_AW_STALL:      cover property (@(posedge ACLK) AWVALID && !AWREADY);
  COV_AXI4_W_STALL:       cover property (@(posedge ACLK) WVALID  && !WREADY);
  COV_AXI4_AR_STALL:      cover property (@(posedge ACLK) ARVALID && !ARREADY);

  COV_AXI4_WRITE_BURST:   cover property (@(posedge ACLK) AWVALID && AWREADY && AWLEN > 0);
  COV_AXI4_READ_BURST:    cover property (@(posedge ACLK) ARVALID && ARREADY && ARLEN > 0);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // All VALID signals must be deasserted at the end of reset
  property assume_valid_low_after_reset;
    @(posedge ACLK)
    $rose(ARESETn) |-> (!AWVALID && !WVALID && !BVALID && !ARVALID && !RVALID);
  endproperty
  ENV_AXI4_VALID_AFTER_RESET: assume property (assume_valid_low_after_reset);

  // AWLEN is within a reasonable bound for the test (optional — tighten if needed)
  property assume_aw_len_bounded;
    @(posedge ACLK) disable iff (!ARESETn)
    AWVALID |-> (AWLEN <= 8'hFF);
  endproperty
  ENV_AXI4_AW_LEN: assume property (assume_aw_len_bounded);

  property assume_ar_len_bounded;
    @(posedge ACLK) disable iff (!ARESETn)
    ARVALID |-> (ARLEN <= 8'hFF);
  endproperty
  ENV_AXI4_AR_LEN: assume property (assume_ar_len_bounded);

endmodule
