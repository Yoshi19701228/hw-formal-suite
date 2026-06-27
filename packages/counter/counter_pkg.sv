// ============================================================
// Counter Verification Package
// ============================================================
package counter_pkg;

  typedef enum logic [1:0] {
    CTR_WRAP     = 2'b00,  // wrap around on overflow/underflow
    CTR_SATURATE = 2'b01,  // saturate at max/min value
    CTR_HALT     = 2'b10   // halt (stop counting) at max/min value
  } counter_overflow_e;

  typedef enum logic {
    CTR_UP   = 1'b0,  // count upward
    CTR_DOWN = 1'b1   // count downward
  } counter_dir_e;

endpackage
