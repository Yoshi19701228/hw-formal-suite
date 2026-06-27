// ============================================================
// [Helper Logic] AXI4 write AW/W/B tracker (Formal)
// Scope: multi-outstanding accounting with bounded progress timeouts
// ============================================================
module axi4_write_helper #(
  parameter integer MAX_AW2W = 16,
  parameter integer MAX_W2B  = 16,
  parameter integer MAX_OUT  = 8
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        awvalid,
  input  wire        awready,
  input  wire        wvalid,
  input  wire        wready,
  input  wire        bvalid,
  input  wire        bready,
  output wire        pending_aw,
  output wire        pending_b,
  output reg  [$clog2(MAX_OUT+1)-1:0] outstanding_aw,
  output reg  [$clog2(MAX_OUT+1)-1:0] outstanding_b,
  output reg  [$clog2(MAX_AW2W+1)-1:0] cnt_aw2w,
  output reg  [$clog2(MAX_W2B+1)-1:0]  cnt_w2b,
  output reg         aw2w_timeout,
  output reg         w2b_timeout,
  output reg         aw_overflow,
  output reg         aw_underflow,
  output reg         b_overflow,
  output reg         b_underflow
);

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid && wready;
  wire b_hs  = bvalid && bready;

  assign pending_aw = (outstanding_aw != '0);
  assign pending_b  = (outstanding_b != '0);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      outstanding_aw <= '0;
      outstanding_b  <= '0;
      cnt_aw2w       <= '0;
      cnt_w2b        <= '0;
      aw2w_timeout   <= 1'b0;
      w2b_timeout    <= 1'b0;
      aw_overflow    <= 1'b0;
      aw_underflow   <= 1'b0;
      b_overflow     <= 1'b0;
      b_underflow    <= 1'b0;
    end else begin
      aw_overflow  <= 1'b0;
      aw_underflow <= 1'b0;
      b_overflow   <= 1'b0;
      b_underflow  <= 1'b0;

      case ({aw_hs, w_hs})
        2'b10: begin
          if (outstanding_aw < MAX_OUT)
            outstanding_aw <= outstanding_aw + 1'b1;
          else
            aw_overflow <= 1'b1;
        end
        2'b01: begin
          if (outstanding_aw > 0)
            outstanding_aw <= outstanding_aw - 1'b1;
          else
            aw_underflow <= 1'b1;
        end
        default: ;
      endcase

      case ({w_hs, b_hs})
        2'b10: begin
          if (outstanding_b < MAX_OUT)
            outstanding_b <= outstanding_b + 1'b1;
          else
            b_overflow <= 1'b1;
        end
        2'b01: begin
          if (outstanding_b > 0)
            outstanding_b <= outstanding_b - 1'b1;
          else
            b_underflow <= 1'b1;
        end
        default: ;
      endcase

      // Measure global forward progress while requests are pending.
      if ((outstanding_aw == '0) || w_hs)
        cnt_aw2w <= '0;
      else
        cnt_aw2w <= cnt_aw2w + 1'b1;

      if ((outstanding_b == '0) || b_hs)
        cnt_w2b <= '0;
      else
        cnt_w2b <= cnt_w2b + 1'b1;

      aw2w_timeout <= (outstanding_aw != '0) && !w_hs && (cnt_aw2w >= MAX_AW2W - 1);
      w2b_timeout  <= (outstanding_b  != '0) && !b_hs && (cnt_w2b  >= MAX_W2B - 1);
    end
  end

endmodule
