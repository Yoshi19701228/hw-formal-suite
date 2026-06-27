// dma_assert_fml.sv
// Formal verification assertion module for DMA controller.
// Order: assert (safety) -> cover (reachability) -> assume (environment).
// No $error; intended for formal property checking tools (Jasper, SymbiYosys, etc.).
//
// Usage (bind):
//   bind <dut_module> dma_assert_fml #(...) u_fml (.*);

module dma_assert_fml
  import dma_pkg::*;
#(
  parameter int ADDR_W    = 32,
  parameter int DATA_W    = 32,
  parameter int MAX_BURST = DMA_MAX_BURST,
  parameter int MAX_XFER  = DMA_MAX_XFER_CYCLES,
  parameter int MAX_BEAT  = DMA_MAX_BEAT_CYCLES
) (
  input wire                            clk,
  input wire                            rst_n,

  // Descriptor
  input wire [ADDR_W-1:0]              desc_src_addr,
  input wire [ADDR_W-1:0]              desc_dst_addr,
  input wire [$clog2(MAX_BURST):0]     desc_len,

  // DUT control / status
  input wire                            dma_start,
  input wire [ADDR_W-1:0]              bus_addr,
  input wire                            bus_req,
  input wire                            bus_ack,
  input wire                            dma_done,
  input wire [DATA_W-1:0]              bus_wdata
);

  // ============================================================
  // [Helper Logic] — beat counter, address tracking, timeouts
  //   (inlined from dma_helper.v)
  // ============================================================
  localparam int STRIDE      = DATA_W / 8;
  localparam int BEAT_W      = $clog2(MAX_BURST+1);
  localparam int BEAT_CTR_W  = $clog2(MAX_BEAT+1);
  localparam int XFER_CTR_W  = $clog2(MAX_XFER+1);

  // chosen_beat: non-deterministic constant selected by formal tool
  (* anyconst *) reg [BEAT_W-1:0] chosen_beat_r;
  wire [$clog2(MAX_BURST+1)-1:0] chosen_beat = chosen_beat_r;

  // Expected addresses (combinatorial)
  wire [ADDR_W-1:0] expected_src_addr = desc_src_addr + ({{(ADDR_W-BEAT_W){1'b0}}, chosen_beat} * STRIDE);
  wire [ADDR_W-1:0] expected_dst_addr = desc_dst_addr + ({{(ADDR_W-BEAT_W){1'b0}}, chosen_beat} * STRIDE);

  // beat_cnt: counts completed bus beats; resets on dma_start
  reg  [$clog2(MAX_BURST+1)-1:0] beat_cnt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      beat_cnt <= {BEAT_W{1'b0}};
    end else if (dma_start) begin
      beat_cnt <= {BEAT_W{1'b0}};
    end else if (bus_req && bus_ack) begin
      beat_cnt <= beat_cnt + 1'b1;
    end
  end

  // addr_mismatch: flag when beat chosen_beat completes with wrong address.
  reg addr_mismatch;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_mismatch <= 1'b0;
    end else if (bus_req && bus_ack && (beat_cnt == chosen_beat)) begin
      addr_mismatch <= (bus_addr != expected_src_addr) && (bus_addr != expected_dst_addr);
    end else begin
      addr_mismatch <= 1'b0;
    end
  end

  // cnt_beat: cycles waiting for current beat ack
  reg  [BEAT_CTR_W-1:0] cnt_beat;
  reg                    beat_timeout;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_beat     <= {BEAT_CTR_W{1'b0}};
      beat_timeout <= 1'b0;
    end else if (bus_ack || !bus_req) begin
      cnt_beat     <= {BEAT_CTR_W{1'b0}};
      beat_timeout <= 1'b0;
    end else if (bus_req) begin
      if (cnt_beat < MAX_BEAT - 1) begin
        cnt_beat <= cnt_beat + 1'b1;
      end else begin
        beat_timeout <= 1'b1;
      end
    end
  end

  // cnt_xfer: cycles from dma_start until dma_done
  reg  [XFER_CTR_W-1:0] cnt_xfer;
  reg                    xfer_timeout;
  reg                    xfer_active;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_xfer     <= {XFER_CTR_W{1'b0}};
      xfer_timeout <= 1'b0;
      xfer_active  <= 1'b0;
    end else if (dma_done) begin
      cnt_xfer     <= {XFER_CTR_W{1'b0}};
      xfer_timeout <= 1'b0;
      xfer_active  <= 1'b0;
    end else if (dma_start) begin
      cnt_xfer     <= {XFER_CTR_W{1'b0}};
      xfer_timeout <= 1'b0;
      xfer_active  <= 1'b1;
    end else if (xfer_active) begin
      if (cnt_xfer < MAX_XFER - 1) begin
        cnt_xfer <= cnt_xfer + 1'b1;
      end else begin
        xfer_timeout <= 1'b1;
      end
    end
  end

  // -----------------------------------------------------------------------
  // Local parameters
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // Default clocking and reset
  // -----------------------------------------------------------------------
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // -----------------------------------------------------------------------
  // SAFETY ASSERTIONS
  // -----------------------------------------------------------------------

  // AST_DMA_BEAT_TIMEOUT
  // Each individual bus beat must complete within MAX_BEAT clock cycles.
  AST_DMA_BEAT_TIMEOUT: assert property (
    !beat_timeout
  );

  // AST_DMA_XFER_TIMEOUT
  // The full transfer must complete within MAX_XFER clock cycles of dma_start.
  AST_DMA_XFER_TIMEOUT: assert property (
    !xfer_timeout
  );

  // AST_DMA_BEAT_COUNT
  // dma_done may only be asserted after all desc_len beats have been transferred.
  AST_DMA_BEAT_COUNT: assert property (
    dma_done |-> (beat_cnt == desc_len)
  );

  // AST_DMA_ADDR_IN_RANGE
  // Every acknowledged bus address must fall within the source OR destination
  // window: [src_base, src_base + len*stride) or [dst_base, dst_base + len*stride).
  AST_DMA_ADDR_IN_RANGE: assert property (
    (bus_req && bus_ack) |->
      ( (bus_addr >= desc_src_addr &&
         bus_addr <  desc_src_addr + ({{(ADDR_W-$clog2(MAX_BURST+1)){1'b0}}, desc_len} * STRIDE))
      ||
        (bus_addr >= desc_dst_addr &&
         bus_addr <  desc_dst_addr + ({{(ADDR_W-$clog2(MAX_BURST+1)){1'b0}}, desc_len} * STRIDE)) )
  );

  // AST_DMA_DONE_PULSE
  // dma_done must be a single-cycle pulse; it must deassert the cycle after it fires.
  AST_DMA_DONE_PULSE: assert property (
    dma_done |=> !dma_done
  );

  // -----------------------------------------------------------------------
  // COVER POINTS (reachability)
  // -----------------------------------------------------------------------

  // COV_DMA_BEAT_ZERO: first beat can complete
  COV_DMA_BEAT_ZERO: cover property (
    beat_cnt == 0 && bus_ack
  );

  // COV_DMA_BEAT_MAX: last beat can complete
  COV_DMA_BEAT_MAX: cover property (
    beat_cnt == desc_len - 1 && bus_ack
  );

  // COV_DMA_DONE: transfer can complete
  COV_DMA_DONE: cover property (
    dma_done
  );

  // COV_DMA_BEAT_TIMEOUT_NEAR: beat counter can reach halfway, testing stress
  COV_DMA_BEAT_TIMEOUT_NEAR: cover property (
    beat_cnt > (MAX_BEAT / 2)
  );

  // COV_DMA_XFER_COMPLETE_FAST: transfer completes exactly on beat count
  COV_DMA_XFER_COMPLETE_FAST: cover property (
    dma_done && (beat_cnt == desc_len)
  );

  // -----------------------------------------------------------------------
  // ENVIRONMENT ASSUMPTIONS
  // -----------------------------------------------------------------------

  // ENV_DMA_CHOSEN_VALID: formal tool constrains chosen_beat to a valid index
  ENV_DMA_CHOSEN_VALID: assume property (
    chosen_beat < desc_len
  );

  // ENV_DMA_LEN_BOUNDED: descriptor length is within legal range
  ENV_DMA_LEN_BOUNDED: assume property (
    (desc_len <= MAX_BURST) && (desc_len > 0)
  );

  // ENV_DMA_ADDRS_NONOVERLAP: source and destination windows must not overlap
  ENV_DMA_ADDRS_NONOVERLAP: assume property (
    (desc_dst_addr >= desc_src_addr + ({{(ADDR_W-$clog2(MAX_BURST+1)){1'b0}}, desc_len} * STRIDE)) ||
    (desc_src_addr >= desc_dst_addr + ({{(ADDR_W-$clog2(MAX_BURST+1)){1'b0}}, desc_len} * STRIDE))
  );

  // ENV_DMA_START_PULSE: dma_start is a single-cycle pulse
  ENV_DMA_START_PULSE: assume property (
    dma_start |=> !dma_start
  );

endmodule
