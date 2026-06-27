// ============================================================
// Cache Formal Helper — Verilog
//
// Core technique: $anyconst address selection + Ghost State
//
// $anyconst chosen_addr:
//   The formal tool picks ONE fixed address for the entire proof.
//   Every property proven with this address is also proven for
//   ALL addresses simultaneously (universal quantification).
//
// Ghost State (shadow registers):
//   Maintain the "ground truth" (golden) value and valid/dirty
//   state for chosen_addr alongside the DUT.  The DUT's output
//   is then compared against the ghost state.
//
// Outputs consumed by cache_assert_fml:
//   chosen_addr      — non-deterministic target address
//   golden_data      — last authoritative value for chosen_addr
//   golden_valid     — ghost valid bit for chosen_addr
//   golden_dirty     — ghost dirty bit for chosen_addr
//   miss_timeout     — cache miss took longer than MAX_MISS_CYCLES
//   wb_timeout       — writeback took longer than MAX_WB_CYCLES
// ============================================================
module cache_helper #(
  parameter int ADDR_W         = 32,
  parameter int DATA_W         = 32,
  parameter int LINE_W         = 256,  // cache line width in bits
  parameter int MAX_MISS_CYCLES = 64,
  parameter int MAX_WB_CYCLES   = 32
)(
  input  wire              clk,
  input  wire              rst_n,

  // CPU-side interface
  input  wire              cpu_req,    // CPU request valid
  input  wire [ADDR_W-1:0] cpu_addr,  // CPU address
  input  wire              cpu_we,    // 1=store, 0=load
  input  wire [DATA_W-1:0] cpu_wdata, // store data
  input  wire [DATA_W-1:0] cpu_rdata, // cache returned data
  input  wire              cpu_ack,   // cache acknowledged (hit or refill done)
  input  wire              cpu_hit,   // cache hit signal
  input  wire              cpu_miss,  // cache miss signal

  // Memory-side interface
  input  wire              mem_req,    // cache → memory request
  input  wire [ADDR_W-1:0] mem_addr,  // memory address
  input  wire              mem_we,    // 1=writeback, 0=refill
  input  wire [LINE_W-1:0] mem_wdata, // writeback data
  input  wire [LINE_W-1:0] mem_rdata, // refill data from memory
  input  wire              mem_ack,   // memory acknowledged

  // Outputs for SVA
  output wire [ADDR_W-1:0] chosen_addr,  // $anyconst target address
  output reg  [DATA_W-1:0] golden_data,  // authoritative value for chosen_addr
  output reg               golden_valid, // ghost: chosen_addr is cached and valid
  output reg               golden_dirty, // ghost: chosen_addr is dirty (write-back)
  output reg               miss_timeout, // miss took too long
  output reg               wb_timeout    // writeback took too long
);

  // ----------------------------------------------------------
  // Non-deterministic address selection
  // The formal solver assigns one fixed address for the entire
  // proof — equivalent to "for all addresses".
  // ----------------------------------------------------------
  assign chosen_addr = $anyconst;

  // ----------------------------------------------------------
  // Ghost State — golden_data
  //
  // Updated on:
  //   1. CPU store to chosen_addr (write-through or write-back)
  //   2. Memory refill completing for chosen_addr
  //      (refill brings chosen_addr into cache with mem_rdata)
  //
  // This tracks the "ground truth" the cache must return on a hit.
  // ----------------------------------------------------------
  wire cpu_store_chosen = cpu_req && cpu_we  && cpu_ack &&
                          (cpu_addr == chosen_addr);
  wire refill_chosen    = mem_req && !mem_we && mem_ack &&
                          (mem_addr == chosen_addr);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      golden_data  <= '0;
      golden_valid <= 1'b0;
      golden_dirty <= 1'b0;
    end else begin
      // Store: update golden_data and mark dirty (write-back policy)
      if (cpu_store_chosen) begin
        golden_data  <= cpu_wdata;
        golden_valid <= 1'b1;
        golden_dirty <= 1'b1;   // write-back: dirty until eviction WB
      end

      // Refill: memory delivered chosen_addr data into cache
      // (DATA_W slice of LINE_W; take lower bits as approximation)
      if (refill_chosen && !cpu_store_chosen) begin
        golden_data  <= mem_rdata[DATA_W-1:0];
        golden_valid <= 1'b1;
        golden_dirty <= 1'b0;
      end

      // Writeback completion: chosen_addr flushed — mark invalid
      if (mem_req && mem_we && mem_ack && (mem_addr == chosen_addr))
        golden_dirty <= 1'b0;

      // Cache invalidation (e.g., flush / eviction of clean line)
      // Detected indirectly: if miss fires for chosen_addr, it was evicted
      if (cpu_req && !cpu_we && cpu_miss && (cpu_addr == chosen_addr))
        golden_valid <= 1'b0;
    end
  end

  // ----------------------------------------------------------
  // Timeout counters
  // Replace ##[1:MAX] in SVA to avoid state-space explosion.
  // ----------------------------------------------------------
  reg [$clog2(MAX_MISS_CYCLES+1)-1:0] cnt_miss;
  reg [$clog2(MAX_WB_CYCLES+1)-1:0]   cnt_wb;

  // Miss timeout: cpu_miss asserted but mem_ack (refill) not arriving
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_miss    <= '0;
      miss_timeout <= 1'b0;
    end else begin
      if (cpu_miss && !mem_ack)
        cnt_miss <= cnt_miss + 1;
      else
        cnt_miss <= '0;
      miss_timeout <= (cnt_miss >= MAX_MISS_CYCLES - 1) && cpu_miss && !mem_ack;
    end
  end

  // Writeback timeout: mem_req (write) asserted but mem_ack not arriving
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_wb     <= '0;
      wb_timeout <= 1'b0;
    end else begin
      if (mem_req && mem_we && !mem_ack)
        cnt_wb <= cnt_wb + 1;
      else
        cnt_wb <= '0;
      wb_timeout <= (cnt_wb >= MAX_WB_CYCLES - 1) && mem_req && mem_we && !mem_ack;
    end
  end

endmodule
