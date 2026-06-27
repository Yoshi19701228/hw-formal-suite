// ============================================================
// APB3 Formal Helper — Verilog
// Provides: timeout flag (replaces ##[0:MAX_WAIT] PREADY)
// ============================================================
module apb3_helper #(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int MAX_WAIT = 16
)(
  input  wire              PCLK,
  input  wire              PRESETn,
  input  wire              PSEL,
  input  wire              PENABLE,
  input  wire              PREADY,

  // Outputs consumed by apb3_assert_fml
  output reg  [$clog2(MAX_WAIT+1)-1:0] cnt_pready_wait,
  output reg                           pready_timeout
);

  // Count cycles in access phase without PREADY
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

endmodule
