// ============================================================
// Cache Assertion Module — Formal Verification
//
// Verification strategy:
//   1. $anyconst selects one address (chosen_addr) for the proof.
//      The formal solver proves every property holds for ANY address.
//   2. Ghost state (cache_helper) tracks the authoritative "golden"
//      value for chosen_addr independently of the DUT.
//   3. Assertions compare DUT output against the ghost state.
//
// Properties covered:
//   [DVI]  Data Value Invariant  — hit data matches golden_data
//   [HIT]  Hit/Miss consistency  — hit only when valid & tags match
//   [WB]   Writeback completeness — dirty eviction triggers writeback
//   [REF]  Refill correctness    — post-refill data matches memory
//   [MISS] Miss timeout          — refill completes in bounded cycles
//   [WBT]  Writeback timeout     — writeback completes in bounded cycles
//
// Usage:
//   cache_helper #(.ADDR_W(32), .DATA_W(32)) u_hlp (
//     .clk, .rst_n,
//     .cpu_req, .cpu_addr, .cpu_we, .cpu_wdata,
//     .cpu_rdata, .cpu_ack, .cpu_hit, .cpu_miss,
//     .mem_req, .mem_addr, .mem_we, .mem_wdata, .mem_rdata, .mem_ack,
//     .chosen_addr, .golden_data, .golden_valid, .golden_dirty,
//     .miss_timeout, .wb_timeout
//   );
//   cache_assert_fml #(.ADDR_W(32), .DATA_W(32)) u_fml (.*);
// ============================================================
module cache_assert_fml
  import cache_pkg::*;
#(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int LINE_W = 256,
  parameter write_policy_e WRITE_POLICY = WRITE_BACK
)(
  input logic              clk,
  input logic              rst_n,

  // CPU-side interface
  input logic              cpu_req,
  input logic [ADDR_W-1:0] cpu_addr,
  input logic              cpu_we,
  input logic [DATA_W-1:0] cpu_wdata,
  input logic [DATA_W-1:0] cpu_rdata,
  input logic              cpu_ack,
  input logic              cpu_hit,
  input logic              cpu_miss,

  // Memory-side interface
  input logic              mem_req,
  input logic [ADDR_W-1:0] mem_addr,
  input logic              mem_we,
  input logic [LINE_W-1:0] mem_wdata,
  input logic [LINE_W-1:0] mem_rdata,
  input logic              mem_ack,

  // From cache_helper
  input logic [ADDR_W-1:0] chosen_addr,
  input logic [DATA_W-1:0] golden_data,
  input logic              golden_valid,
  input logic              golden_dirty,
  input logic              miss_timeout,
  input logic              wb_timeout
);

  // ----------------------------------------------------------
  // 1. Safety
  // ----------------------------------------------------------

  // [DVI] Data Value Invariant
  // When the cache returns data for chosen_addr on a hit,
  // the returned value must equal the ghost golden_data.
  // This is the fundamental correctness property of a cache.
  property prop_dvi_load;
    @(posedge clk) disable iff (!rst_n)
    (cpu_req && !cpu_we && cpu_hit && cpu_ack && (cpu_addr == chosen_addr))
    |-> (cpu_rdata == golden_data);
  endproperty
  AST_CACHE_DVI_LOAD: assert property (prop_dvi_load);

  // [DVI-STORE] After a store to chosen_addr, a subsequent load
  // on the same cycle (or the ack cycle) must see the new value.
  // (Write-through: data visible immediately;
  //  Write-back: data visible from cache on next hit)
  property prop_dvi_store_read_after_write;
    @(posedge clk) disable iff (!rst_n)
    (cpu_req && cpu_we && cpu_ack && (cpu_addr == chosen_addr))
    |=> (cpu_req && !cpu_we && cpu_hit && (cpu_addr == chosen_addr))
        |-> (cpu_rdata == $past(cpu_wdata, 1));
  endproperty
  AST_CACHE_DVI_RAW: assert property (prop_dvi_store_read_after_write);

  // [HIT] Hit only when golden state is valid for chosen_addr
  // (Prevents spurious hits — cache must not report a hit for
  //  an address that was never loaded or has been invalidated)
  property prop_no_spurious_hit;
    @(posedge clk) disable iff (!rst_n)
    (cpu_req && cpu_hit && (cpu_addr == chosen_addr))
    |-> golden_valid;
  endproperty
  AST_CACHE_NO_SPURIOUS_HIT: assert property (prop_no_spurious_hit);

  // [HIT-MISS] Hit and miss are mutually exclusive
  property prop_hit_miss_mutex;
    @(posedge clk) disable iff (!rst_n)
    cpu_req |-> !(cpu_hit && cpu_miss);
  endproperty
  AST_CACHE_HIT_MISS_MUTEX: assert property (prop_hit_miss_mutex);

  // [WB] Write-back completeness
  // A dirty eviction (mem_req with mem_we) for chosen_addr must
  // carry the golden dirty data.
  // This ensures no silent data loss on eviction.
  generate
    if (WRITE_POLICY == WRITE_BACK) begin : g_wb

      property prop_wb_data_correct;
        @(posedge clk) disable iff (!rst_n)
        (mem_req && mem_we && (mem_addr == chosen_addr) && golden_dirty)
        |-> (mem_wdata[DATA_W-1:0] == golden_data);
      endproperty
      AST_CACHE_WB_DATA: assert property (prop_wb_data_correct);

      // [WB-BEFORE-EVICT] Dirty line must trigger writeback request
      // before or upon being replaced.
      // (golden_dirty && new miss for chosen_addr) → mem_req && mem_we
      property prop_dirty_evict_triggers_wb;
        @(posedge clk) disable iff (!rst_n)
        (cpu_req && cpu_miss && (cpu_addr == chosen_addr) && golden_dirty)
        |-> ##[0:4] (mem_req && mem_we && (mem_addr == chosen_addr));
      endproperty
      AST_CACHE_DIRTY_EVICT_WB: assert property (prop_dirty_evict_triggers_wb);

      // [WB-TIMEOUT] Writeback must complete within MAX_WB_CYCLES
      property prop_wb_no_timeout;
        @(posedge clk) disable iff (!rst_n)
        !wb_timeout;
      endproperty
      AST_CACHE_WB_TIMEOUT: assert property (prop_wb_no_timeout);

    end
  endgenerate

  // [REF] Refill correctness
  // After a refill for chosen_addr, the data returned by the next
  // load hit must match what memory provided.
  property prop_refill_correctness;
    @(posedge clk) disable iff (!rst_n)
    (mem_req && !mem_we && mem_ack && (mem_addr == chosen_addr))
    |=> (cpu_req && !cpu_we && cpu_hit && (cpu_addr == chosen_addr))
        |-> (cpu_rdata == $past(mem_rdata[DATA_W-1:0], 1));
  endproperty
  AST_CACHE_REFILL_CORRECT: assert property (prop_refill_correctness);

  // [MISS-TIMEOUT] Miss must be resolved within MAX_MISS_CYCLES
  property prop_miss_no_timeout;
    @(posedge clk) disable iff (!rst_n)
    !miss_timeout;
  endproperty
  AST_CACHE_MISS_TIMEOUT: assert property (prop_miss_no_timeout);

  // [RESET] No cpu_ack during reset
  property prop_no_ack_in_reset;
    @(posedge clk)
    !rst_n |-> !cpu_ack;
  endproperty
  AST_CACHE_NO_ACK_IN_RESET: assert property (prop_no_ack_in_reset);

  // ----------------------------------------------------------
  // 2. Reachability
  // ----------------------------------------------------------

  // chosen_addr can be loaded (hit)
  COV_CACHE_HIT_CHOSEN:   cover property (
    @(posedge clk) cpu_req && !cpu_we && cpu_hit && (cpu_addr == chosen_addr));

  // chosen_addr can miss
  COV_CACHE_MISS_CHOSEN:  cover property (
    @(posedge clk) cpu_req && cpu_miss && (cpu_addr == chosen_addr));

  // chosen_addr can be stored
  COV_CACHE_STORE_CHOSEN: cover property (
    @(posedge clk) cpu_req && cpu_we && cpu_ack && (cpu_addr == chosen_addr));

  // Miss followed by hit (refill path reachable)
  COV_CACHE_MISS_THEN_HIT: cover property (
    @(posedge clk)
    (cpu_req && cpu_miss && (cpu_addr == chosen_addr))
    ##[1:$]
    (cpu_req && !cpu_we && cpu_hit && (cpu_addr == chosen_addr)));

  // Write-back triggered for chosen_addr
  COV_CACHE_WB_CHOSEN: cover property (
    @(posedge clk) mem_req && mem_we && (mem_addr == chosen_addr));

  // Refill triggered for chosen_addr
  COV_CACHE_REFILL_CHOSEN: cover property (
    @(posedge clk) mem_req && !mem_we && (mem_addr == chosen_addr));

  // Store-then-load (read-after-write path)
  COV_CACHE_RAW: cover property (
    @(posedge clk)
    (cpu_req && cpu_we && cpu_ack && (cpu_addr == chosen_addr))
    ##1
    (cpu_req && !cpu_we && cpu_hit && (cpu_addr == chosen_addr)));

  // ----------------------------------------------------------
  // 3. Environment Constraints
  // ----------------------------------------------------------

  // chosen_addr is aligned to DATA_W/8 bytes
  property assume_chosen_aligned;
    @(posedge clk)
    chosen_addr[($clog2(DATA_W/8))-1:0] == '0;
  endproperty
  ENV_CACHE_CHOSEN_ALIGNED: assume property (assume_chosen_aligned);

  // cpu_req is deasserted during reset
  property assume_no_req_in_reset;
    @(posedge clk)
    !rst_n |-> !cpu_req;
  endproperty
  ENV_CACHE_NO_REQ_IN_RESET: assume property (assume_no_req_in_reset);

  // mem_ack arrives within MAX_MISS_CYCLES of mem_req (environment bound)
  property assume_mem_responds;
    @(posedge clk) disable iff (!rst_n)
    $rose(mem_req) |-> ##[1:64] mem_ack;
  endproperty
  ENV_CACHE_MEM_RESPONDS: assume property (assume_mem_responds);

endmodule
