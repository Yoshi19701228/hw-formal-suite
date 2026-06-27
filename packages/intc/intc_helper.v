// ============================================================
// Interrupt Controller Formal Helper — Verilog
//
// Provides:
//   chosen_irq   — $anyconst index for focused per-channel proof
//   cnt_pending  — cycles chosen_irq has been pending but unacked
//   starvation   — asserted when cnt_pending reaches MAX_LATENCY-1
//
// Usage:
//   intc_helper #(.N_IRQ(8), .MAX_LATENCY(32)) u_hlp (
//     .clk, .rst_n, .irq_raw, .irq_mask, .irq_pending, .irq_ack,
//     .irq_out, .chosen_irq, .starvation, .cnt_pending);
//   intc_assert_fml #(.N_IRQ(8), .MAX_LATENCY(32)) u_fml (.*);
// ============================================================
module intc_helper #(
  parameter integer N_IRQ       = 8,
  parameter integer MAX_LATENCY = 32
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire [N_IRQ-1:0]            irq_raw,
  input  wire [N_IRQ-1:0]            irq_mask,
  input  wire [N_IRQ-1:0]            irq_pending,
  input  wire [N_IRQ-1:0]            irq_ack,
  input  wire                        irq_out,

  // Outputs consumed by intc_assert_fml
  output wire [$clog2(N_IRQ)-1:0]           chosen_irq,
  output reg  [$clog2(MAX_LATENCY+1)-1:0]   cnt_pending,
  output reg                                 starvation
);

  // Non-deterministic channel selection — held constant by formal engine
  (* anyconst *) reg [$clog2(N_IRQ)-1:0] chosen_irq_r;
  assign chosen_irq = chosen_irq_r;

  // Pending-without-ack cycle counter for the chosen channel
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_pending <= {($clog2(MAX_LATENCY+1)){1'b0}};
      starvation  <= 1'b0;
    end else begin
      if (irq_pending[chosen_irq_r] && !irq_mask[chosen_irq_r] && !irq_ack[chosen_irq_r]) begin
        // Saturate to avoid wrap-around
        if (cnt_pending < MAX_LATENCY)
          cnt_pending <= cnt_pending + 1;
      end else begin
        cnt_pending <= {($clog2(MAX_LATENCY+1)){1'b0}};
      end

      starvation <= (cnt_pending >= MAX_LATENCY - 1) &&
                    irq_pending[chosen_irq_r] &&
                    !irq_mask[chosen_irq_r]   &&
                    !irq_ack[chosen_irq_r];
    end
  end

endmodule
