// mem_ctrl_assert_fml.sv
// Formal assertion module for memory controller / SRAM verification.
// Instantiate (or bind) alongside the DUT.
// Order: assert (safety) -> cover (reachability) -> assume (environment).
// No $error calls — this module targets formal property checking only.

`default_nettype none

module mem_ctrl_assert_fml
  import mem_ctrl_pkg::*;
#(
  parameter integer ADDR_W   = 20,
  parameter integer DATA_W   = 32,
  parameter integer MAX_WAIT = MEM_MAX_WAIT_CYCLES,
  // Derived widths
  parameter integer WAIT_BITS = $clog2(MAX_WAIT + 1)
) (
  input wire                  clk,
  input wire                  rst_n,

  // CPU memory interface
  input wire                  cpu_req,
  input wire                  cpu_we,
  input wire [ADDR_W-1:0]    cpu_addr,
  input wire [DATA_W-1:0]    cpu_wdata,
  input wire [DATA_W-1:0]    cpu_rdata,
  input wire                  cpu_ack,

  // Signals from mem_ctrl_helper
  input wire [ADDR_W-1:0]    chosen_addr,
  input wire [DATA_W-1:0]    golden_data,
  input wire                  golden_valid,
  input wire                  wait_timeout,
  // cnt_wait is used only for cover properties
  input wire [WAIT_BITS-1:0] cnt_wait
);

  // Default clock and reset for SVA
  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ===========================================================================
  // SAFETY ASSERTIONS
  // ===========================================================================

  // AST_MEM_NO_WAIT_TIMEOUT
  // Every request must be acknowledged within MAX_WAIT cycles.
  AST_MEM_NO_WAIT_TIMEOUT:
    assert property (
      !wait_timeout
    );

  // AST_MEM_READ_AFTER_WRITE
  // Fundamental correctness: a read to chosen_addr must return the value
  // from the most recent write to that address.
  AST_MEM_READ_AFTER_WRITE:
    assert property (
      (cpu_req && !cpu_we && cpu_ack
       && (cpu_addr == chosen_addr)
       && golden_valid)
      |-> (cpu_rdata == golden_data)
    );

  // AST_MEM_NO_ACK_WITHOUT_REQ
  // The controller must not produce an acknowledgement unless a request
  // is currently pending.
  AST_MEM_NO_ACK_WITHOUT_REQ:
    assert property (
      cpu_ack |-> cpu_req
    );

  // AST_MEM_NO_ACK_IN_RESET
  // No acknowledgement may appear while reset is asserted.
  AST_MEM_NO_ACK_IN_RESET:
    assert property (
      !rst_n |-> !cpu_ack
    );

  // AST_MEM_WRITE_STABLE
  // The CPU must hold write request signals (req, we, addr, wdata) stable
  // from the cycle after a write is initiated until the ack arrives.
  AST_MEM_WRITE_STABLE:
    assert property (
      (cpu_req && cpu_we && !cpu_ack)
      |=> (cpu_req && cpu_we && $stable(cpu_addr) && $stable(cpu_wdata))
    );

  // AST_MEM_READ_STABLE
  // The CPU must hold read request signals (req, we, addr) stable from the
  // cycle after a read is initiated until the ack arrives.
  AST_MEM_READ_STABLE:
    assert property (
      (cpu_req && !cpu_we && !cpu_ack)
      |=> (cpu_req && !cpu_we && $stable(cpu_addr))
    );

  // ===========================================================================
  // REACHABILITY COVERS
  // ===========================================================================

  // COV_MEM_READ_HIT
  // Verify that a successful read of a previously written chosen_addr is reachable.
  COV_MEM_READ_HIT:
    cover property (
      cpu_req && !cpu_we && cpu_ack
      && golden_valid && (cpu_addr == chosen_addr)
    );

  // COV_MEM_WRITE
  // Verify that a successful write to chosen_addr is reachable.
  COV_MEM_WRITE:
    cover property (
      cpu_req && cpu_we && cpu_ack && (cpu_addr == chosen_addr)
    );

  // COV_MEM_RAW
  // Verify a read-after-write sequence to chosen_addr within 4 cycles.
  COV_MEM_RAW:
    cover property (
      (cpu_req && cpu_we  && cpu_ack && (cpu_addr == chosen_addr))
      ##[1:4]
      (cpu_req && !cpu_we && cpu_ack && (cpu_addr == chosen_addr))
    );

  // COV_MEM_ACK_FAST
  // Verify that a request can be acknowledged in the same cycle (0 wait states).
  COV_MEM_ACK_FAST:
    cover property (
      cpu_req && cpu_ack
    );

  // COV_MEM_ACK_SLOW
  // Verify that a request can experience more than MAX_WAIT/2 wait cycles.
  COV_MEM_ACK_SLOW:
    cover property (
      cnt_wait > WAIT_BITS'(MAX_WAIT / 2)
    );

  // ===========================================================================
  // ENVIRONMENT ASSUMPTIONS
  // ===========================================================================

  // ENV_MEM_CHOSEN_ALIGNED
  // chosen_addr must be naturally word-aligned (lower address bits zero).
  ENV_MEM_CHOSEN_ALIGNED:
    assume property (
      chosen_addr[$clog2(DATA_W/8)-1:0] == {$clog2(DATA_W/8){1'b0}}
    );

  // ENV_MEM_NO_REQ_IN_RESET
  // The CPU must not issue a request while reset is asserted.
  ENV_MEM_NO_REQ_IN_RESET:
    assume property (
      !rst_n |-> !cpu_req
    );

  // ENV_MEM_REQ_STABLE
  // The CPU must hold cpu_req high until the controller acknowledges it.
  ENV_MEM_REQ_STABLE:
    assume property (
      (cpu_req && !cpu_ack) |=> cpu_req
    );

endmodule

`default_nettype wire
