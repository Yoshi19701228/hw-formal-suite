// xbar_assert_fml.sv
// Formal assertion module for crossbar / NoC verification.
// Instantiate (or bind) alongside the DUT.
// Order: assert (safety) -> cover (reachability) -> assume (environment).
// No $error calls — this module targets formal property checking only.

`default_nettype none

module xbar_assert_fml
  import xbar_pkg::*;
#(
  parameter integer N_MASTERS       = 4,
  parameter integer N_SLAVES        = 4,
  parameter integer MAX_LATENCY     = XBAR_MAX_LATENCY,
  parameter integer MAX_OUTSTANDING = XBAR_MAX_OUTSTANDING,
  // Derived widths
  parameter integer MASTER_BITS     = $clog2(N_MASTERS),
  parameter integer SLAVE_BITS      = $clog2(N_SLAVES),
  parameter integer OUT_BITS        = $clog2(MAX_OUTSTANDING + 1)
) (
  input wire                        clk,
  input wire                        rst_n,

  // Master-side signals
  input wire [N_MASTERS-1:0]        m_req,
  input wire [N_MASTERS*SLAVE_BITS-1:0] m_dst_flat,   // packed: m_dst[i] = m_dst_flat[i*SLAVE_BITS +: SLAVE_BITS]
  input wire [N_MASTERS-1:0]        m_ack,

  // Slave-side signals
  input wire [N_SLAVES-1:0]         s_req,
  input wire [N_SLAVES-1:0]         s_ack,

  // Signals from xbar_helper
  input wire [MASTER_BITS-1:0]      chosen_master,
  input wire [SLAVE_BITS-1:0]       chosen_slave,
  input wire                        routing_timeout,
  input wire [OUT_BITS-1:0]         outstanding_cnt,
  input wire                        outstanding_overflow
);

  // Convenience: unpack the destination for chosen_master
  wire [SLAVE_BITS-1:0] chosen_master_dst =
      m_dst_flat[chosen_master * SLAVE_BITS +: SLAVE_BITS];

  // Default clock and reset for SVA
  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ===========================================================================
  // SAFETY ASSERTIONS
  // ===========================================================================

  // AST_XBAR_NO_ROUTING_TIMEOUT
  // Chosen master's request must be served before the latency deadline.
  AST_XBAR_NO_ROUTING_TIMEOUT:
    assert property (
      !routing_timeout
    );

  // AST_XBAR_NO_OUTSTANDING_OVERFLOW
  // Number of in-flight transactions must not exceed the maximum.
  AST_XBAR_NO_OUTSTANDING_OVERFLOW:
    assert property (
      !outstanding_overflow
    );

  // AST_XBAR_CORRECT_ROUTING
  // When chosen_master's request is granted, the correct slave must receive it.
  AST_XBAR_CORRECT_ROUTING:
    assert property (
      (m_req[chosen_master] && m_ack[chosen_master])
      |-> s_req[chosen_master_dst]
    );

  // AST_XBAR_SLAVE_REQ_IMPLIES_MASTER
  // A slave is only activated when at least one master is still requesting
  // (i.e. has not yet been acked).
  AST_XBAR_SLAVE_REQ_IMPLIES_MASTER:
    assert property (
      s_req[chosen_slave]
      |-> |(m_req & ~m_ack)
    );

  // AST_XBAR_RESET_CLEAR
  // During reset, no master acknowledgements or slave requests may be asserted.
  AST_XBAR_RESET_CLEAR:
    assert property (
      !rst_n |-> (!(|m_ack) && !(|s_req))
    );

  // ===========================================================================
  // REACHABILITY COVERS
  // ===========================================================================

  // COV_XBAR_CHOSEN_MASTER_GRANTED
  // Verify that the chosen master can receive an acknowledgement.
  COV_XBAR_CHOSEN_MASTER_GRANTED:
    cover property (
      m_ack[chosen_master]
    );

  // COV_XBAR_CHOSEN_SLAVE_SERVED
  // Verify that the chosen slave can receive a request.
  COV_XBAR_CHOSEN_SLAVE_SERVED:
    cover property (
      s_req[chosen_slave]
    );

  // COV_XBAR_MULTI_OUTSTANDING
  // Verify that more than one transaction can be in-flight simultaneously.
  COV_XBAR_MULTI_OUTSTANDING:
    cover property (
      outstanding_cnt > {{(OUT_BITS-1){1'b0}}, 1'b1}
    );

  // COV_XBAR_ALL_MASTERS_REQ
  // Verify that all masters can request simultaneously.
  COV_XBAR_ALL_MASTERS_REQ:
    cover property (
      &m_req
    );

  // COV_XBAR_FULL_OUTSTANDING
  // Verify that half of the maximum outstanding count is reachable.
  COV_XBAR_FULL_OUTSTANDING:
    cover property (
      outstanding_cnt == OUT_BITS'(MAX_OUTSTANDING / 2)
    );

  // ===========================================================================
  // ENVIRONMENT ASSUMPTIONS
  // ===========================================================================

  // ENV_XBAR_CHOSEN_MASTER_VALID
  // The symbolic chosen_master index is within the valid range.
  ENV_XBAR_CHOSEN_MASTER_VALID:
    assume property (
      chosen_master < MASTER_BITS'(N_MASTERS)
    );

  // ENV_XBAR_CHOSEN_SLAVE_VALID
  // The symbolic chosen_slave index is within the valid range.
  ENV_XBAR_CHOSEN_SLAVE_VALID:
    assume property (
      chosen_slave < SLAVE_BITS'(N_SLAVES)
    );

  // ENV_XBAR_DST_VALID
  // When chosen_master issues a request, its destination index must be valid.
  ENV_XBAR_DST_VALID:
    assume property (
      m_req[chosen_master] |-> chosen_master_dst < SLAVE_BITS'(N_SLAVES)
    );

  // ENV_XBAR_REQ_STABLE
  // A master holds its request high until it is acknowledged.
  ENV_XBAR_REQ_STABLE:
    assume property (
      (m_req[chosen_master] && !m_ack[chosen_master])
      |=> m_req[chosen_master]
    );

endmodule

`default_nettype wire
