// ============================================================
// FIFO Formal Scoreboard — Non-Deterministic Data Integrity Check
//
// Verifies that data pushed into the FIFO comes out in the correct
// order with the correct value, using formal non-determinism.
//
// Key technique:
//   $anyconst chosen_slot — symbolically selects which push transaction
//   to track. The formal tool proves the property holds for ALL possible
//   values of chosen_slot in a single proof run.
//
// Usage (bind to FIFO DUT):
//   bind fifo_dut fifo_scoreboard_fml #(
//     .DEPTH(8), .DATA_W(32)
//   ) u_sb (
//     .clk(clk), .rst_n(rst_n),
//     .push(push), .pop(pop),
//     .full(full), .empty(empty),
//     .din(din), .dout(dout),
//     .cnt_used(cnt_used)   // optional occupancy counter
//   );
// ============================================================
module fifo_scoreboard_fml #(
  parameter int DEPTH  = 8,
  parameter int DATA_W = 32
)(
  input logic                        clk,
  input logic                        rst_n,
  input logic                        push,
  input logic                        pop,
  input logic                        full,
  input logic                        empty,
  input logic [DATA_W-1:0]           din,
  input logic [DATA_W-1:0]           dout,
  input logic [$clog2(DEPTH+1)-1:0]  cnt_used  // occupancy (optional; tie to 0 if absent)
);

  // ============================================================
  // [Helper Logic 1] Non-deterministic slot selector
  //
  // chosen_slot is fixed by $anyconst for the entire proof.
  // The prover explores all values simultaneously — proving the
  // property for one symbolic slot proves it for all slots.
  // ============================================================
  logic [$clog2(DEPTH)-1:0] chosen_slot;
  assign chosen_slot = $anyconst;

  // ============================================================
  // [Helper Logic 2] Push / Pop counters
  // ============================================================
  reg [$clog2(DEPTH+1)-1:0] cnt_push;  // total pushes since reset
  reg [$clog2(DEPTH+1)-1:0] cnt_pop;   // total pops  since reset

  wire do_push = push && !full;
  wire do_pop  = pop  && !empty;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_push <= '0;
      cnt_pop  <= '0;
    end else begin
      if (do_push) cnt_push <= cnt_push + 1;
      if (do_pop)  cnt_pop  <= cnt_pop  + 1;
    end
  end

  // ============================================================
  // [Helper Logic 3] Ghost state — shadow the chosen entry
  //
  // golden_data  : data value captured when chosen push occurs
  // golden_valid : set once the chosen push has been observed
  // golden_out   : set once the corresponding pop has been observed
  // ============================================================
  reg [DATA_W-1:0] golden_data;
  reg              golden_valid;   // chosen push seen
  reg              golden_out;     // chosen pop  seen

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      golden_data  <= '0;
      golden_valid <= 1'b0;
      golden_out   <= 1'b0;
    end else begin
      // Capture data on the chosen push transaction
      if (do_push && (cnt_push == chosen_slot) && !golden_valid) begin
        golden_data  <= din;
        golden_valid <= 1'b1;
      end
      // Mark as popped when the matching pop transaction occurs
      if (do_pop && golden_valid && !golden_out &&
          (cnt_pop == chosen_slot)) begin
        golden_out <= 1'b1;
      end
    end
  end

  // ============================================================
  // [Helper Logic 4] Overflow / underflow flags
  // ============================================================
  reg overflow_flag;
  reg underflow_flag;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_flag  <= 1'b0;
      underflow_flag <= 1'b0;
    end else begin
      overflow_flag  <= full  && push;
      underflow_flag <= empty && pop;
    end
  end

  // ============================================================
  // [Helper Logic 5] Occupancy shadow counter (independent check)
  // ============================================================
  reg [$clog2(DEPTH+1)-1:0] shadow_count;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shadow_count <= '0;
    end else begin
      case ({do_push, do_pop})
        2'b10: shadow_count <= shadow_count + 1;
        2'b01: shadow_count <= shadow_count - 1;
        default: ;
      endcase
    end
  end

  // ============================================================
  // 1. Safety — Data Integrity
  // ============================================================

  // Core scoreboard property:
  // When the chosen entry reaches the head of the FIFO and is
  // popped, dout must equal the data captured at push time.
  property prop_data_integrity;
    @(posedge clk) disable iff (!rst_n)
    (do_pop && golden_valid && !golden_out &&
     cnt_pop == chosen_slot) |-> dout == golden_data;
  endproperty
  AST_FIFO_DATA_INTEGRITY: assert property (prop_data_integrity);

  // Push-before-pop ordering:
  // The chosen pop must not occur before the chosen push.
  property prop_push_before_pop;
    @(posedge clk) disable iff (!rst_n)
    (do_pop && cnt_pop == chosen_slot) |-> golden_valid;
  endproperty
  AST_FIFO_PUSH_BEFORE_POP: assert property (prop_push_before_pop);

  // No overflow: push when full is forbidden
  property prop_no_overflow;
    @(posedge clk) disable iff (!rst_n)
    !overflow_flag;
  endproperty
  AST_FIFO_NO_OVERFLOW: assert property (prop_no_overflow);

  // No underflow: pop when empty is forbidden
  property prop_no_underflow;
    @(posedge clk) disable iff (!rst_n)
    !underflow_flag;
  endproperty
  AST_FIFO_NO_UNDERFLOW: assert property (prop_no_underflow);

  // Occupancy consistency: shadow counter must match DUT's cnt_used
  // (skip if cnt_used is tied to 0)
  property prop_count_match;
    @(posedge clk) disable iff (!rst_n || cnt_used == '0)
    shadow_count == cnt_used;
  endproperty
  AST_FIFO_COUNT_MATCH: assert property (prop_count_match);

  // Full/empty flag consistency
  property prop_full_when_count_max;
    @(posedge clk) disable iff (!rst_n)
    (shadow_count == DEPTH) |-> full;
  endproperty
  AST_FIFO_FULL_CONSISTENT: assert property (prop_full_when_count_max);

  property prop_empty_when_count_zero;
    @(posedge clk) disable iff (!rst_n)
    (shadow_count == '0) |-> empty;
  endproperty
  AST_FIFO_EMPTY_CONSISTENT: assert property (prop_empty_when_count_zero);

  // ============================================================
  // 2. Reachability
  // ============================================================

  // Core scoreboard events must be reachable
  COV_SB_PUSH_CAPTURED:  cover property (@(posedge clk) $rose(golden_valid));
  COV_SB_POP_VERIFIED:   cover property (@(posedge clk) $rose(golden_out));
  COV_SB_FULL_PUSH:      cover property (@(posedge clk) full  && do_push);
  COV_SB_EMPTY_POP:      cover property (@(posedge clk) empty && do_pop);
  COV_SB_SIMULTANEOUS:   cover property (@(posedge clk) do_push && do_pop);
  COV_SB_BACK2BACK_PUSH: cover property (@(posedge clk) do_push ##1 do_push);
  COV_SB_BACK2BACK_POP:  cover property (@(posedge clk) do_pop  ##1 do_pop);
  COV_SB_FILL_DRAIN:     cover property (@(posedge clk)
    shadow_count == DEPTH ##[1:$] shadow_count == '0);

  // ============================================================
  // 3. Environment Constraints
  // ============================================================

  // chosen_slot must be within a valid range
  property assume_slot_valid;
    @(posedge clk) chosen_slot < DEPTH;
  endproperty
  ENV_SB_SLOT_VALID: assume property (assume_slot_valid);

  // The chosen push must eventually happen (liveness assumption)
  property assume_chosen_push_occurs;
    @(posedge clk) disable iff (!rst_n)
    !golden_valid |-> ##[0:DEPTH*4] golden_valid;
  endproperty
  ENV_SB_PUSH_OCCURS: assume property (assume_chosen_push_occurs);

endmodule
