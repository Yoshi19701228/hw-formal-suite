// ============================================================
// [Helper Logic] 4-port arbiter starvation checker (Formal)
// ============================================================
module arbiter_starvation_anyconst_helper #(
  parameter integer N = 4,
  parameter integer MAX_WAIT = 16
) (
  input  wire                     clk,
  input  wire                     rst_n,
  input  wire [N-1:0]             req,
  input  wire [N-1:0]             gnt,
  output wire [$clog2(N)-1:0]     chosen,
  output reg  [$clog2(MAX_WAIT+1)-1:0] cnt_wait_chosen,
  output reg                      starvation
);

  // Formal tool chooses one requester index and keeps it constant.
  assign chosen = $anyconst;

  wire chosen_req = req[chosen];
  wire chosen_gnt = gnt[chosen];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_wait_chosen <= '0;
      starvation      <= 1'b0;
    end else begin
      if (chosen_req && !chosen_gnt)
        cnt_wait_chosen <= cnt_wait_chosen + 1'b1;
      else
        cnt_wait_chosen <= '0;

      starvation <= (cnt_wait_chosen >= MAX_WAIT - 1) && chosen_req && !chosen_gnt;
    end
  end

endmodule
