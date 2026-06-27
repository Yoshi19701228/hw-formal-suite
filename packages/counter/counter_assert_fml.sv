// ============================================================
// Counter Assertion Module — Formal Verification
//
// Parameterised by bit-width, overflow mode, and count direction.
// No helper module is required — all properties are combinable
// without unbounded sequence repetition.
//
// Usage:
//   counter_assert_fml #(
//     .WIDTH(8), .OVF_MODE(CTR_WRAP), .DIR(CTR_UP)
//   ) u_fml (
//     .clk, .rst_n, .en, .clr, .count, .overflow, .underflow);
// ============================================================
module counter_assert_fml
  import counter_pkg::*;
#(
  parameter int              WIDTH    = 8,
  parameter counter_overflow_e OVF_MODE = CTR_WRAP,
  parameter counter_dir_e      DIR      = CTR_UP
)(
  input logic              clk,
  input logic              rst_n,
  input logic              en,
  input logic              clr,
  input logic [WIDTH-1:0]  count,
  input logic              overflow,
  input logic              underflow
);

  localparam [WIDTH-1:0] MAX_VAL = {WIDTH{1'b1}};  // (1 << WIDTH) - 1

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // Synchronous reset drives count to zero
  property prop_reset;
    @(posedge clk)
    !rst_n |-> count == '0;
  endproperty
  AST_CTR_RESET: assert property (prop_reset);

  // Clear forces count to zero on the next cycle
  property prop_clr;
    @(posedge clk) disable iff (!rst_n)
    clr |=> count == '0;
  endproperty
  AST_CTR_CLR: assert property (prop_clr);

  // Up-counter increments by 1 when enabled and not at maximum
  property prop_up_inc;
    @(posedge clk) disable iff (!rst_n)
    (DIR == CTR_UP && en && !clr && count < MAX_VAL) |=> count == $past(count) + 1'b1;
  endproperty
  AST_CTR_UP_INC: assert property (prop_up_inc);

  // Down-counter decrements by 1 when enabled and not at zero
  property prop_down_dec;
    @(posedge clk) disable iff (!rst_n)
    (DIR == CTR_DOWN && en && !clr && count > 0) |=> count == $past(count) - 1'b1;
  endproperty
  AST_CTR_DOWN_DEC: assert property (prop_down_dec);

  // Counter must not change while disabled (and no clear)
  property prop_no_change_disabled;
    @(posedge clk) disable iff (!rst_n)
    !en && !clr |=> $stable(count);
  endproperty
  AST_CTR_NO_CHANGE_DISABLED: assert property (prop_no_change_disabled);

  // Overflow flag reflects current count and enable state
  property prop_overflow_flag;
    @(posedge clk) disable iff (!rst_n)
    overflow == (count == MAX_VAL && en && DIR == CTR_UP);
  endproperty
  AST_CTR_OVERFLOW_FLAG: assert property (prop_overflow_flag);

  // Underflow flag reflects current count and enable state
  property prop_underflow_flag;
    @(posedge clk) disable iff (!rst_n)
    underflow == (count == '0 && en && DIR == CTR_DOWN);
  endproperty
  AST_CTR_UNDERFLOW_FLAG: assert property (prop_underflow_flag);

  // Saturation mode: up-counter holds at MAX_VAL when enabled at maximum
  generate
    if (OVF_MODE == CTR_SATURATE) begin : gen_sat
      property prop_saturate_max;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_UP && count == MAX_VAL && en && !clr) |=> count == MAX_VAL;
      endproperty
      AST_CTR_SATURATE_MAX: assert property (prop_saturate_max);

      property prop_saturate_min;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_DOWN && count == '0 && en && !clr) |=> count == '0;
      endproperty
      AST_CTR_SATURATE_MIN: assert property (prop_saturate_min);
    end
  endgenerate

  // Wrap mode: up-counter rolls over from MAX_VAL to 0
  generate
    if (OVF_MODE == CTR_WRAP) begin : gen_wrap
      property prop_wrap_max;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_UP && count == MAX_VAL && en && !clr) |=> count == '0;
      endproperty
      AST_CTR_WRAP_MAX: assert property (prop_wrap_max);
    end
  endgenerate

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------

  COV_CTR_MAX:
    cover property (@(posedge clk) disable iff (!rst_n) count == MAX_VAL);

  COV_CTR_MIN:
    cover property (@(posedge clk) disable iff (!rst_n) count == '0);

  COV_CTR_MID:
    cover property (@(posedge clk) disable iff (!rst_n) count == MAX_VAL / 2);

  COV_CTR_OVERFLOW:
    cover property (@(posedge clk) disable iff (!rst_n) overflow);

  COV_CTR_UNDERFLOW:
    cover property (@(posedge clk) disable iff (!rst_n) underflow);

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------
  // en is a synchronous control signal — no external constraint needed;
  // the clock already gates all transitions.

endmodule
