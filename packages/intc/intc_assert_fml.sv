// ============================================================
// Interrupt Controller Assertion Module — Formal Verification
//
// Usage (bind):
//   bind <dut_module> intc_assert_fml #(.N_IRQ(8), .MAX_LATENCY(32)) u_fml (.*);
// ============================================================
module intc_assert_fml
  import intc_pkg::*;
#(
  parameter int N_IRQ       = 8,
  parameter int MAX_LATENCY = INTC_MAX_LATENCY
)(
  input logic                      clk,
  input logic                      rst_n,
  input logic [N_IRQ-1:0]          irq_raw,
  input logic [N_IRQ-1:0]          irq_mask,
  input logic [N_IRQ-1:0]          irq_pending,
  input logic [N_IRQ-1:0]          irq_ack,
  input logic                      irq_out
);

  // ============================================================
  // [Helper Logic] — chosen_irq selection, pending counter,
  //   starvation flag
  //   (inlined from intc_helper.v)
  // ============================================================

  // Non-deterministic channel selection — held constant by formal engine
  (* anyconst *) reg [$clog2(N_IRQ)-1:0] chosen_irq_r;
  wire [$clog2(N_IRQ)-1:0] chosen_irq = chosen_irq_r;

  // Pending-without-ack cycle counter for the chosen channel
  reg  [$clog2(MAX_LATENCY+1)-1:0] cnt_pending;
  reg                               starvation;

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

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // All active (unmasked) pending IRQs are zero => no interrupt output
  property prop_mask_respected;
    @(posedge clk) disable iff (!rst_n)
    (irq_pending & ~irq_mask) == '0 |-> !irq_out;
  endproperty
  AST_INTC_MASK_RESPECTED: assert property (prop_mask_respected);

  // Rising edge of raw IRQ sticks in pending register (if not simultaneously acked)
  property prop_pending_sticky;
    @(posedge clk) disable iff (!rst_n)
    ($rose(irq_raw[chosen_irq]) && !irq_ack[chosen_irq]) |=> irq_pending[chosen_irq];
  endproperty
  AST_INTC_PENDING_STICKY: assert property (prop_pending_sticky);

  // Acknowledge pulse clears the pending bit next cycle
  property prop_ack_clears_pending;
    @(posedge clk) disable iff (!rst_n)
    irq_ack[chosen_irq] |=> !irq_pending[chosen_irq];
  endproperty
  AST_INTC_ACK_CLEARS_PENDING: assert property (prop_ack_clears_pending);

  // Interrupt output implies at least one unmasked pending IRQ
  property prop_no_spurious_out;
    @(posedge clk) disable iff (!rst_n)
    irq_out |-> |(irq_pending & ~irq_mask);
  endproperty
  AST_INTC_NO_SPURIOUS_OUT: assert property (prop_no_spurious_out);

  // No channel may wait longer than MAX_LATENCY cycles without being served
  property prop_no_starvation;
    @(posedge clk) disable iff (!rst_n)
    !starvation;
  endproperty
  AST_INTC_NO_STARVATION: assert property (prop_no_starvation);

  // Reset deasserts all pending bits and the combined output
  property prop_reset;
    @(posedge clk)
    !rst_n |-> (!irq_pending && !irq_out);
  endproperty
  AST_INTC_RESET: assert property (prop_reset);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------

  // Combined interrupt output fires at least once
  COV_INTC_IRQ_FIRES:
    cover property (@(posedge clk) disable iff (!rst_n) irq_out);

  // Chosen channel becomes pending
  COV_INTC_CHOSEN_PENDING:
    cover property (@(posedge clk) disable iff (!rst_n) irq_pending[chosen_irq]);

  // Chosen channel receives an acknowledge
  COV_INTC_CHOSEN_ACK:
    cover property (@(posedge clk) disable iff (!rst_n) irq_ack[chosen_irq]);

  // Raw IRQ arrives while masked
  COV_INTC_MASKED_IGNORED:
    cover property (@(posedge clk) disable iff (!rst_n) irq_raw[chosen_irq] && irq_mask[chosen_irq]);

  // More than one channel pending simultaneously
  COV_INTC_MULTI_PENDING:
    cover property (@(posedge clk) disable iff (!rst_n) $countones(irq_pending) > 1);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // chosen_irq is a valid channel index
  property assume_chosen_valid;
    @(posedge clk)
    chosen_irq < N_IRQ;
  endproperty
  ENV_INTC_CHOSEN_VALID: assume property (assume_chosen_valid);

  // Acknowledge is a single-cycle pulse
  property assume_ack_pulse;
    @(posedge clk) disable iff (!rst_n)
    irq_ack[chosen_irq] |=> !irq_ack[chosen_irq];
  endproperty
  ENV_INTC_ACK_PULSE: assume property (assume_ack_pulse);

endmodule
