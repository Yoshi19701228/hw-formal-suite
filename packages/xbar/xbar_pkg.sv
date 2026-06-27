package xbar_pkg;
  typedef enum logic [1:0] {
    XBAR_IDLE    = 2'b00,
    XBAR_GRANTED = 2'b01,
    XBAR_WAIT    = 2'b10,
    XBAR_DONE    = 2'b11
  } xbar_state_e;

  parameter int XBAR_MAX_LATENCY     = 64;  // max routing latency in cycles
  parameter int XBAR_MAX_OUTSTANDING = 16;  // max in-flight transactions
endpackage
