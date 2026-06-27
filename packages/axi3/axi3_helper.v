// ============================================================
// AXI3 Formal Helper — Verilog
// Spec: AMBA AXI Protocol Specification (ARM IHI0022D, rev: AXI3)
//
// Provides:
//   - Per-channel handshake timeout flags
//   - Write beat counter (tracks WLAST vs 4-bit AWLEN)
//   - Outstanding write transaction counter
//   - Outstanding read transaction counter
//
// Note on WID: AXI3 requires WID to match the AWID of the
// corresponding in-order write transaction.  Tracking this
// correctly requires a FIFO of outstanding AWIDs and is left
// to a higher-level checker.  The helper exposes raw signals
// so an external checker can implement the WID-match rule.
// ============================================================
module axi3_helper #(
  parameter int DATA_W          = 32,
  parameter int ID_W            = 4,
  parameter int MAX_WAIT        = 256,
  parameter int MAX_OUTSTANDING = 16
)(
  input  wire              ACLK,
  input  wire              ARESETn,

  // AW
  input  wire              AWVALID,
  input  wire              AWREADY,
  input  wire [3:0]        AWLEN,    // 4-bit in AXI3

  // W
  input  wire              WVALID,
  input  wire              WREADY,
  input  wire              WLAST,

  // B
  input  wire              BVALID,
  input  wire              BREADY,

  // AR
  input  wire              ARVALID,
  input  wire              ARREADY,
  input  wire [3:0]        ARLEN,    // 4-bit in AXI3

  // R
  input  wire              RVALID,
  input  wire              RREADY,
  input  wire              RLAST,

  // --- Outputs: handshake timeout flags ---
  output reg               aw_timeout,
  output reg               w_timeout,
  output reg               b_timeout,
  output reg               ar_timeout,
  output reg               r_timeout,

  // --- Outputs: write beat tracking ---
  // Latched AWLEN at AW handshake; compared against W beat count
  output reg  [3:0]        snap_awlen,
  output reg  [3:0]        cnt_w_beats,   // beats sent in current write burst
  output reg               wlast_mismatch, // WLAST fired on wrong beat

  // --- Outputs: outstanding write transaction counter ---
  output reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_aw_outstanding,
  output reg               aw_overflow,   // too many in-flight write transactions

  // --- Outputs: outstanding read transaction counter ---
  output reg  [$clog2(MAX_OUTSTANDING+1)-1:0] cnt_ar_outstanding,
  output reg               ar_overflow
);

  // ============================================================
  // Handshake timeout counters (replace ##[1:MAX_WAIT] in formal)
  // ============================================================
  reg [$clog2(MAX_WAIT+1)-1:0] cnt_aw, cnt_w, cnt_b, cnt_ar, cnt_r;

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

  // ============================================================
  // Write beat counter — detect WLAST mismatch vs AWLEN (4-bit)
  // ============================================================
  // Latch AWLEN at AW handshake; count W-channel beats; flag if
  // WLAST fires on the wrong beat.
  always @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      snap_awlen      <= 4'h0;
      cnt_w_beats     <= 4'h0;
      wlast_mismatch  <= 1'b0;
    end else begin
      if (AWVALID && AWREADY)
        snap_awlen <= AWLEN;

      if (WVALID && WREADY) begin
        if (WLAST)
          cnt_w_beats <= 4'h0;
        else
          cnt_w_beats <= cnt_w_beats + 4'h1;

        // WLAST must fire exactly when beat count == AWLEN
        wlast_mismatch <= WLAST && (cnt_w_beats != snap_awlen);
      end else begin
        wlast_mismatch <= 1'b0;
      end
    end
  end

  // ============================================================
  // Outstanding write transaction counter
  // ============================================================
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

  // ============================================================
  // Outstanding read transaction counter
  // ============================================================
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

endmodule
