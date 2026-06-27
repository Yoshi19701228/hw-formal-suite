// dma_helper.v
// Formal verification helper for DMA controller.
// Tracks beat count, expected addresses, and timeout conditions.
// Use $anyconst-driven chosen_beat to select one beat for address-check properties.

module dma_helper #(
  parameter ADDR_W          = 32,
  parameter DATA_W          = 32,
  parameter MAX_BURST       = 256,
  parameter MAX_XFER_CYCLES = 1024,
  parameter MAX_BEAT_CYCLES = 64
) (
  input  wire                            clk,
  input  wire                            rst_n,

  // Descriptor fields
  input  wire [ADDR_W-1:0]              desc_src_addr,
  input  wire [ADDR_W-1:0]              desc_dst_addr,
  input  wire [$clog2(MAX_BURST):0]     desc_len,       // number of beats (1..MAX_BURST)

  // Control / status from DUT
  input  wire                            dma_start,      // 1-cycle pulse: start transfer
  input  wire [ADDR_W-1:0]              bus_addr,        // current bus address
  input  wire                            bus_req,         // bus request active
  input  wire                            bus_ack,         // beat complete
  input  wire                            dma_done,        // DUT signals transfer complete
  input  wire [DATA_W-1:0]              bus_wdata,       // write data on bus

  // Helper outputs
  output wire [$clog2(MAX_BURST+1)-1:0] chosen_beat,     // $anyconst beat index
  output reg  [$clog2(MAX_BURST+1)-1:0] beat_cnt,        // number of beats completed so far
  output wire [ADDR_W-1:0]              expected_src_addr,// desc_src_addr + chosen_beat*stride
  output wire [ADDR_W-1:0]              expected_dst_addr,// desc_dst_addr + chosen_beat*stride
  output reg                             addr_mismatch,   // bus_addr != expected at chosen beat
  output reg                             beat_timeout,    // no ack within MAX_BEAT_CYCLES
  output reg                             xfer_timeout,    // transfer not done within MAX_XFER_CYCLES

  output reg  [$clog2(MAX_BEAT_CYCLES+1)-1:0]  cnt_beat, // cycles waiting for current beat ack
  output reg  [$clog2(MAX_XFER_CYCLES+1)-1:0]  cnt_xfer  // cycles since dma_start
);

  // -----------------------------------------------------------------------
  // Local parameters
  // -----------------------------------------------------------------------
  localparam int STRIDE      = DATA_W / 8;
  localparam int BEAT_W      = $clog2(MAX_BURST+1);
  localparam int BEAT_CTR_W  = $clog2(MAX_BEAT_CYCLES+1);
  localparam int XFER_CTR_W  = $clog2(MAX_XFER_CYCLES+1);

  // -----------------------------------------------------------------------
  // chosen_beat: non-deterministic constant selected by formal tool
  // -----------------------------------------------------------------------
  (* anyconst *) reg [BEAT_W-1:0] chosen_beat_r;
  assign chosen_beat = chosen_beat_r;

  // -----------------------------------------------------------------------
  // Expected addresses (combinatorial)
  // -----------------------------------------------------------------------
  assign expected_src_addr = desc_src_addr + ({{(ADDR_W-BEAT_W){1'b0}}, chosen_beat} * STRIDE);
  assign expected_dst_addr = desc_dst_addr + ({{(ADDR_W-BEAT_W){1'b0}}, chosen_beat} * STRIDE);

  // -----------------------------------------------------------------------
  // beat_cnt: counts completed bus beats; resets on dma_start
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      beat_cnt <= {BEAT_W{1'b0}};
    end else if (dma_start) begin
      beat_cnt <= {BEAT_W{1'b0}};
    end else if (bus_req && bus_ack) begin
      beat_cnt <= beat_cnt + 1'b1;
    end
  end

  // -----------------------------------------------------------------------
  // addr_mismatch: flag when beat chosen_beat completes with wrong address.
  // We check both src and dst ranges; a mismatch requires the address to
  // match neither expected_src_addr nor expected_dst_addr.
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_mismatch <= 1'b0;
    end else if (bus_req && bus_ack && (beat_cnt == chosen_beat)) begin
      addr_mismatch <= (bus_addr != expected_src_addr) && (bus_addr != expected_dst_addr);
    end else begin
      addr_mismatch <= 1'b0;
    end
  end

  // -----------------------------------------------------------------------
  // cnt_beat: counts cycles where bus_req is asserted but bus_ack has not
  // arrived.  Resets on every bus_ack or when bus_req deasserts.
  // beat_timeout: held high once cnt_beat reaches MAX_BEAT_CYCLES-1.
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_beat     <= {BEAT_CTR_W{1'b0}};
      beat_timeout <= 1'b0;
    end else if (bus_ack || !bus_req) begin
      cnt_beat     <= {BEAT_CTR_W{1'b0}};
      beat_timeout <= 1'b0;
    end else if (bus_req) begin
      if (cnt_beat < MAX_BEAT_CYCLES - 1) begin
        cnt_beat <= cnt_beat + 1'b1;
      end else begin
        beat_timeout <= 1'b1;
      end
    end
  end

  // -----------------------------------------------------------------------
  // cnt_xfer: counts cycles from dma_start until dma_done.
  // xfer_timeout: held high once cnt_xfer reaches MAX_XFER_CYCLES-1.
  // -----------------------------------------------------------------------
  reg xfer_active;

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
      if (cnt_xfer < MAX_XFER_CYCLES - 1) begin
        cnt_xfer <= cnt_xfer + 1'b1;
      end else begin
        xfer_timeout <= 1'b1;
      end
    end
  end

endmodule
