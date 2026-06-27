// ============================================================
// Counter Assertion Module — Simulation
//
// Same properties as counter_assert_fml with $error reporting
// added to each assert.  Cover points are included without
// $error (they never fail; they only flag unreachable goals).
//
// Usage:
//   counter_assert_sim #(
//     .WIDTH(8), .OVF_MODE(CTR_WRAP), .DIR(CTR_UP)
//   ) u_sim (
//     .clk, .rst_n, .en, .clr, .count, .overflow, .underflow);
// ============================================================
module counter_assert_sim
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

  localparam [WIDTH-1:0] MAX_VAL = {WIDTH{1'b1}};

  // ----------------------------------------------------------
  // 1. Safety — assertions with $error reporting
  // ----------------------------------------------------------

  // Synchronous reset drives count to zero
  property prop_reset;
    @(posedge clk)
    !rst_n |-> count == '0;
  endproperty
  AST_CTR_RESET: assert property (prop_reset)
    else $error("[counter_assert_sim] AST_CTR_RESET FAIL: count=%0h during reset at time %0t",
                count, $time);

  // Clear forces count to zero on the next cycle
  property prop_clr;
    @(posedge clk) disable iff (!rst_n)
    clr |=> count == '0;
  endproperty
  AST_CTR_CLR: assert property (prop_clr)
    else $error("[counter_assert_sim] AST_CTR_CLR FAIL: count=%0h after clear at time %0t",
                count, $time);

  // Up-counter increments by 1 when enabled and not at maximum
  property prop_up_inc;
    @(posedge clk) disable iff (!rst_n)
    (DIR == CTR_UP && en && !clr && count < MAX_VAL) |=> count == $past(count) + 1'b1;
  endproperty
  AST_CTR_UP_INC: assert property (prop_up_inc)
    else $error("[counter_assert_sim] AST_CTR_UP_INC FAIL: expected %0h got %0h at time %0t",
                $past(count) + 1'b1, count, $time);

  // Down-counter decrements by 1 when enabled and not at zero
  property prop_down_dec;
    @(posedge clk) disable iff (!rst_n)
    (DIR == CTR_DOWN && en && !clr && count > 0) |=> count == $past(count) - 1'b1;
  endproperty
  AST_CTR_DOWN_DEC: assert property (prop_down_dec)
    else $error("[counter_assert_sim] AST_CTR_DOWN_DEC FAIL: expected %0h got %0h at time %0t",
                $past(count) - 1'b1, count, $time);

  // Counter must not change while disabled (and no clear)
  property prop_no_change_disabled;
    @(posedge clk) disable iff (!rst_n)
    !en && !clr |=> $stable(count);
  endproperty
  AST_CTR_NO_CHANGE_DISABLED: assert property (prop_no_change_disabled)
    else $error("[counter_assert_sim] AST_CTR_NO_CHANGE_DISABLED FAIL: count changed from %0h to %0h at time %0t",
                $past(count), count, $time);

  // Overflow flag reflects current count and enable state
  property prop_overflow_flag;
    @(posedge clk) disable iff (!rst_n)
    overflow == (count == MAX_VAL && en && DIR == CTR_UP);
  endproperty
  AST_CTR_OVERFLOW_FLAG: assert property (prop_overflow_flag)
    else $error("[counter_assert_sim] AST_CTR_OVERFLOW_FLAG FAIL: overflow=%0b count=%0h en=%0b at time %0t",
                overflow, count, en, $time);

  // Underflow flag reflects current count and enable state
  property prop_underflow_flag;
    @(posedge clk) disable iff (!rst_n)
    underflow == (count == '0 && en && DIR == CTR_DOWN);
  endproperty
  AST_CTR_UNDERFLOW_FLAG: assert property (prop_underflow_flag)
    else $error("[counter_assert_sim] AST_CTR_UNDERFLOW_FLAG FAIL: underflow=%0b count=%0h en=%0b at time %0t",
                underflow, count, en, $time);

  // Saturation mode: up-counter holds at MAX_VAL when enabled at maximum
  generate
    if (OVF_MODE == CTR_SATURATE) begin : gen_sat
      property prop_saturate_max;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_UP && count == MAX_VAL && en && !clr) |=> count == MAX_VAL;
      endproperty
      AST_CTR_SATURATE_MAX: assert property (prop_saturate_max)
        else $error("[counter_assert_sim] AST_CTR_SATURATE_MAX FAIL: count did not hold at MAX_VAL at time %0t",
                    $time);

      property prop_saturate_min;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_DOWN && count == '0 && en && !clr) |=> count == '0;
      endproperty
      AST_CTR_SATURATE_MIN: assert property (prop_saturate_min)
        else $error("[counter_assert_sim] AST_CTR_SATURATE_MIN FAIL: count did not hold at 0 at time %0t",
                    $time);
    end
  endgenerate

  // Wrap mode: up-counter rolls over from MAX_VAL to 0
  generate
    if (OVF_MODE == CTR_WRAP) begin : gen_wrap
      property prop_wrap_max;
        @(posedge clk) disable iff (!rst_n)
        (DIR == CTR_UP && count == MAX_VAL && en && !clr) |=> count == '0;
      endproperty
      AST_CTR_WRAP_MAX: assert property (prop_wrap_max)
        else $error("[counter_assert_sim] AST_CTR_WRAP_MAX FAIL: count did not wrap to 0 at time %0t",
                    $time);
    end
  endgenerate

  // ----------------------------------------------------------
  // 2. Reachability — cover points only (no $error)
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

endmodule
