// ============================================================
// APB4 Formal Helper — Verilog
// Provides: timeout flag (replaces ##[0:MAX_WAIT] PREADY)
//           pstrb_changed flag (PSTRB instability in setup phase)
// ============================================================
module apb4_helper #(
  parameter integer DATA_W   = 32,
  parameter integer MAX_WAIT = 16
)(
  input  wire                       clk,
  input  wire                       rst_n,
  input  wire                       psel,
  input  wire                       penable,
  input  wire                       pwrite,
  input  wire [DATA_W/8-1:0]        pstrb,
  input  wire [2:0]                 pprot,
  input  wire                       pready,

  // Outputs consumed by apb4_assert_fml
  output reg  [$clog2(MAX_WAIT+1)-1:0] cnt_pready_wait,
  output reg                            pready_timeout,
  output reg                            pstrb_changed
);

  // Previous cycle value of pstrb for change detection
  reg [DATA_W/8-1:0] pstrb_prev;

  // Count cycles in access phase without PREADY
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_pready_wait <= {($clog2(MAX_WAIT+1)){1'b0}};
      pready_timeout  <= 1'b0;
      pstrb_prev      <= {(DATA_W/8){1'b0}};
      pstrb_changed   <= 1'b0;
    end else begin
      // PREADY wait counter: increment during access phase without PREADY
      if (psel && penable && !pready)
        cnt_pready_wait <= cnt_pready_wait + 1;
      else
        cnt_pready_wait <= {($clog2(MAX_WAIT+1)){1'b0}};

      pready_timeout <= (cnt_pready_wait >= MAX_WAIT - 1) && psel && penable && !pready;

      // Track pstrb stability: flag if pstrb changes during setup phase
      // Setup phase = psel asserted, penable not yet asserted
      pstrb_prev    <= pstrb;
      pstrb_changed <= psel && !penable && (pstrb != pstrb_prev);
    end
  end

endmodule
