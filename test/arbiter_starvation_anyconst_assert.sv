// ============================================================
// [Arbiter] Starvation-freedom SVA with $anyconst (Formal)
// ============================================================
module arbiter_starvation_anyconst_assert #(
  parameter integer N = 4,
  parameter integer MAX_WAIT = 16
) (
  input wire                 clk,
  input wire                 rst_n,
  input wire [N-1:0]         req,
  input wire [N-1:0]         gnt,
  input wire [$clog2(N)-1:0] chosen,
  input wire                 starvation
);

  // 1. Safety -------------------------------------------------

  property prop_no_starvation;
    @(posedge clk) disable iff (!rst_n)
    !starvation;
  endproperty
  AST_NO_STARVATION: assert property (prop_no_starvation);

  property prop_no_spurious_grant_for_chosen;
    @(posedge clk) disable iff (!rst_n)
    gnt[chosen] |-> req[chosen];
  endproperty
  AST_NO_SPURIOUS_GRANT_FOR_CHOSEN: assert property (prop_no_spurious_grant_for_chosen);

  // 2. Reachability ------------------------------------------

  COV_CHOSEN_REQ:            cover property (@(posedge clk) req[chosen]);
  COV_CHOSEN_GNT:            cover property (@(posedge clk) gnt[chosen]);
  COV_CHOSEN_WAIT_THEN_GNT:  cover property (@(posedge clk) req[chosen] && !gnt[chosen] ##1 gnt[chosen]);

  // 3. Environment Constraints -------------------------------

  property assume_chosen_valid;
    @(posedge clk)
    chosen < N;
  endproperty
  ENV_CHOSEN_VALID: assume property (assume_chosen_valid);

  // Keep chosen request active until it is granted.
  property assume_chosen_req_holds_until_grant;
    @(posedge clk) disable iff (!rst_n)
    (req[chosen] && !gnt[chosen]) |=> req[chosen];
  endproperty
  ENV_CHOSEN_REQ_HOLDS_UNTIL_GRANT: assume property (assume_chosen_req_holds_until_grant);

endmodule
