// mem_ctrl_helper.v
// Helper module for memory controller / SRAM formal verification.
// Tracks a golden "last written value" for a non-deterministically chosen
// address, and measures request-to-acknowledge latency.
// No assertions are placed here; all properties live in mem_ctrl_assert_fml.sv.

module mem_ctrl_helper #(
  parameter integer ADDR_W   = 20,
  parameter integer DATA_W   = 32,
  parameter integer MAX_WAIT = 16,
  // Derived width for the wait counter
  parameter integer WAIT_BITS = $clog2(MAX_WAIT + 1)
) (
  input  wire                clk,
  input  wire                rst_n,

  // CPU memory interface
  input  wire                cpu_req,    // CPU issues a request
  input  wire                cpu_we,     // 1 = write, 0 = read
  input  wire [ADDR_W-1:0]  cpu_addr,   // target address
  input  wire [DATA_W-1:0]  cpu_wdata,  // write data
  input  wire [DATA_W-1:0]  cpu_rdata,  // read data returned by the controller
  input  wire                cpu_ack,    // controller acknowledges the request

  // Non-deterministic address selection (driven by $anyconst in the formal tool)
  input  wire [ADDR_W-1:0]  chosen_addr,

  // Outputs to the assertion module
  output wire [ADDR_W-1:0]  chosen_addr_out, // mirrors chosen_addr
  output reg  [DATA_W-1:0]  golden_data,     // last value written to chosen_addr
  output reg                 golden_valid,    // at least one write to chosen_addr has occurred
  output reg  [WAIT_BITS-1:0] cnt_wait,      // cycles cpu_req pending without cpu_ack
  output reg                 wait_timeout     // cnt_wait has reached MAX_WAIT-1
);

  // -------------------------------------------------------------------------
  // Non-deterministic address pass-through
  // -------------------------------------------------------------------------
  assign chosen_addr_out = chosen_addr;

  // -------------------------------------------------------------------------
  // Golden data register
  // Updated every time the CPU successfully writes to chosen_addr.
  // golden_valid is set on the first such write and never cleared
  // (SRAM retains its contents — there is no power-down in this model).
  // -------------------------------------------------------------------------
  wire write_to_chosen = cpu_req && cpu_we && cpu_ack
                         && (cpu_addr == chosen_addr);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      golden_data  <= {DATA_W{1'b0}};
      golden_valid <= 1'b0;
    end else begin
      if (write_to_chosen) begin
        golden_data  <= cpu_wdata;
        golden_valid <= 1'b1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Wait (latency) counter
  // Counts consecutive cycles where cpu_req is asserted but cpu_ack has not
  // been returned.  Resets to 0 when the request completes or is withdrawn.
  // Saturates at MAX_WAIT to prevent wrap-around.
  // -------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_wait    <= {WAIT_BITS{1'b0}};
      wait_timeout <= 1'b0;
    end else begin
      if (cpu_req && !cpu_ack) begin
        // Request pending; count up, saturate at MAX_WAIT
        if (cnt_wait < MAX_WAIT[WAIT_BITS-1:0])
          cnt_wait <= cnt_wait + 1'b1;
      end else begin
        // No pending request, or request just acknowledged: reset counter
        cnt_wait <= {WAIT_BITS{1'b0}};
      end

      // Timeout fires when the counter reaches the threshold
      wait_timeout <= (cnt_wait >= (MAX_WAIT - 1));
    end
  end

endmodule
