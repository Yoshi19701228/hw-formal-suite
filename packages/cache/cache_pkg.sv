// ============================================================
// Cache Verification Package
// Supports: write-back / write-through, direct-mapped / set-associative
// ============================================================
package cache_pkg;

  // MESI coherence states
  typedef enum logic [1:0] {
    MESI_INVALID  = 2'b00,
    MESI_SHARED   = 2'b01,
    MESI_EXCLUSIVE = 2'b10,
    MESI_MODIFIED  = 2'b11
  } mesi_state_e;

  // Cache write policy
  typedef enum logic {
    WRITE_THROUGH = 1'b0,
    WRITE_BACK    = 1'b1
  } write_policy_e;

  // Cache operation type
  typedef enum logic {
    CACHE_LOAD  = 1'b0,
    CACHE_STORE = 1'b1
  } cache_op_e;

  // Default bounds (override via module parameters)
  parameter int CACHE_MAX_REFILL_CYCLES = 64;  // max cycles a miss may take
  parameter int CACHE_MAX_WB_CYCLES     = 32;  // max cycles a writeback may take

endpackage
