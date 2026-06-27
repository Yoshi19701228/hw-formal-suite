// ============================================================
// [Helper Logic] req_valid pending cycle counter
// Replaces ##[1:MAX_LATENCY] ack_valid to avoid state-space explosion.
// ============================================================
module req_ack_helper #(
  parameter MAX_LATENCY = 16
) (
  input  wire clk,
  input  wire rst_n,
  input  wire req_valid,
  input  wire ack_valid,
  output reg  [$clog2(MAX_LATENCY+1)-1:0] cnt_req_pending,
  output reg  timeout
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_req_pending <= '0;
      timeout         <= 1'b0;
    end else begin
      if (req_valid && !ack_valid)
        cnt_req_pending <= cnt_req_pending + 1;
      else
        cnt_req_pending <= '0;

      timeout <= (cnt_req_pending >= MAX_LATENCY - 1) && req_valid && !ack_valid;
    end
  end
endmodule
