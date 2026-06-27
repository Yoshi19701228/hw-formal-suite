// xbar_helper.v
// Helper module for crossbar / NoC formal verification.
// Provides non-deterministic master/slave selection, a cycle-accurate
// latency counter, and an outstanding-transaction counter.
// No assertions are placed here; all properties live in xbar_assert_fml.sv.

module xbar_helper #(
  parameter integer N_MASTERS       = 4,
  parameter integer N_SLAVES        = 4,
  parameter integer MAX_LATENCY     = 64,
  parameter integer MAX_OUTSTANDING = 16,
  // Derived widths exposed as parameters so the instantiating module
  // can connect ports without repeating $clog2 expressions.
  parameter integer MASTER_BITS     = $clog2(N_MASTERS),
  parameter integer SLAVE_BITS      = $clog2(N_SLAVES),
  parameter integer LAT_BITS        = $clog2(MAX_LATENCY    + 1),
  parameter integer OUT_BITS        = $clog2(MAX_OUTSTANDING + 1)
) (
  input  wire                        clk,
  input  wire                        rst_n,

  // Master-side signals
  input  wire [N_MASTERS-1:0]        m_req,              // master request signals
  input  wire [N_MASTERS*SLAVE_BITS-1:0] m_dst_flat,     // flattened master destinations
  input  wire [N_MASTERS-1:0]        m_ack,              // master acknowledged

  // Slave-side signals
  input  wire [N_SLAVES-1:0]         s_req,              // slave receives request
  input  wire [N_SLAVES-1:0]         s_ack,              // slave acknowledges

  // Non-deterministic selection — drive with $anyconst in the formal bind
  input  wire [MASTER_BITS-1:0]      chosen_master,
  input  wire [SLAVE_BITS-1:0]       chosen_slave,

  // Pass-through so the assertion module can read the symbolic values
  output wire [MASTER_BITS-1:0]      chosen_master_out,
  output wire [SLAVE_BITS-1:0]       chosen_slave_out,

  // Latency tracking for chosen_master
  output reg  [LAT_BITS-1:0]         cnt_latency,
  output reg                         routing_timeout,

  // Outstanding transaction tracking (all masters / slaves combined)
  output reg  [OUT_BITS-1:0]         outstanding_cnt,
  output reg                         outstanding_overflow
);

  // -------------------------------------------------------------------------
  // Non-deterministic symbolic constants
  // The formal tool constrains these via $anyconst so they are stable.
  // -------------------------------------------------------------------------
  assign chosen_master_out = chosen_master;
  assign chosen_slave_out  = chosen_slave;

  // -------------------------------------------------------------------------
  // Latency counter for chosen_master
  // Counts consecutive cycles where m_req[chosen_master] is high
  // but m_ack[chosen_master] has not been asserted.
  // Resets to 0 on acknowledgement or when the request drops.
  // -------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_latency     <= {LAT_BITS{1'b0}};
      routing_timeout <= 1'b0;
    end else begin
      if (m_req[chosen_master] && !m_ack[chosen_master]) begin
        // Request pending but not yet acked; increment, saturate at MAX_LATENCY
        if (cnt_latency < MAX_LATENCY[LAT_BITS-1:0])
          cnt_latency <= cnt_latency + 1'b1;
      end else begin
        // Acked or no request: clear counter
        cnt_latency <= {LAT_BITS{1'b0}};
      end

      // Timeout fires when latency reaches the threshold
      routing_timeout <= (cnt_latency >= (MAX_LATENCY - 1));
    end
  end

  // -------------------------------------------------------------------------
  // Outstanding transaction counter
  // Increments when any master's request is accepted (m_req & m_ack).
  // Decrements when any slave completes (s_ack).
  // Saturates to prevent wrap-around.
  // -------------------------------------------------------------------------
  wire any_accepted  = |(m_req & m_ack);
  wire any_completed = |s_ack;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      outstanding_cnt      <= {OUT_BITS{1'b0}};
      outstanding_overflow <= 1'b0;
    end else begin
      case ({any_accepted, any_completed})
        2'b10: begin
          // Transaction accepted, none completed this cycle
          if (outstanding_cnt < MAX_OUTSTANDING[OUT_BITS-1:0])
            outstanding_cnt <= outstanding_cnt + 1'b1;
        end
        2'b01: begin
          // Transaction completed, none accepted this cycle
          if (outstanding_cnt > {OUT_BITS{1'b0}})
            outstanding_cnt <= outstanding_cnt - 1'b1;
        end
        2'b11: ; // One in, one out: net zero change
        default: ; // 2'b00: no activity
      endcase

      // Overflow flag: count has reached or exceeded the limit
      outstanding_overflow <= (outstanding_cnt >= MAX_OUTSTANDING[OUT_BITS-1:0]);
    end
  end

endmodule
