// ============================================================
// FIFO Formal Helper — Verilog
// Provides: shadow counter, overflow/underflow flags, and a
// $anyconst chosen_entry index for data-value invariant proofs.
// Avoids ##[1:N] ranges that cause state-space explosion.
//
// Usage:
//   fifo_helper #(.DEPTH(16), .DATA_W(32)) u_hlp (
//     .clk, .rst_n,
//     .push, .pop, .wdata, .count, .full, .empty,
//     .almost_full, .almost_empty,
//     .chosen_entry, .shadow_count,
//     .count_mismatch, .overflow_flag, .underflow_flag
//   );
// ============================================================
module fifo_helper #(
  parameter int DEPTH  = 16,
  parameter int DATA_W = 32
)(
  input  wire                        clk,
  input  wire                        rst_n,

  // DUT control signals
  input  wire                        push,
  input  wire                        pop,
  input  wire [DATA_W-1:0]           wdata,

  // DUT status outputs
  input  wire [$clog2(DEPTH):0]      count,
  input  wire                        full,
  input  wire                        empty,
  input  wire                        almost_full,
  input  wire                        almost_empty,

  // Helper outputs consumed by fifo_assert_fml
  output wire [$clog2(DEPTH)-1:0]    chosen_entry,   // $anyconst: fixed witness index
  output reg  [$clog2(DEPTH+1)-1:0]  shadow_count,   // ghost fill counter
  output reg                         count_mismatch, // shadow_count != DUT count
  output reg                         overflow_flag,  // push attempted when full
  output reg                         underflow_flag  // pop attempted when empty
);

  // ----------------------------------------------------------
  // chosen_entry: non-deterministic but fixed for the entire run.
  // Used by the surrounding assertion to anchor a data-value
  // invariant proof without enumerating all entries.
  // ----------------------------------------------------------
  (* anyconst *) reg [$clog2(DEPTH)-1:0] chosen_entry_r;
  assign chosen_entry = chosen_entry_r;

  // ----------------------------------------------------------
  // Shadow counter: mirrors the expected fill level
  // ----------------------------------------------------------
  localparam int CNT_W = $clog2(DEPTH + 1);

  reg first_cycle;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shadow_count   <= '0;
      count_mismatch <= 1'b0;
      first_cycle    <= 1'b1;
    end else begin
      first_cycle <= 1'b0;

      // Update shadow counter based on push/pop activity
      casez ({push && !full, pop && !empty})
        2'b10: shadow_count <= shadow_count + 1;
        2'b01: shadow_count <= shadow_count - 1;
        default: shadow_count <= shadow_count; // 2'b00 or simultaneous push+pop
      endcase

      // Detect mismatch (ignore first cycle after reset)
      if (!first_cycle)
        count_mismatch <= (shadow_count != count[$clog2(DEPTH+1)-1:0]);
      else
        count_mismatch <= 1'b0;
    end
  end

  // ----------------------------------------------------------
  // Protocol violation flags (registered for timing alignment)
  // ----------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_flag  <= 1'b0;
      underflow_flag <= 1'b0;
    end else begin
      overflow_flag  <= push && full;
      underflow_flag <= pop  && empty;
    end
  end

endmodule
