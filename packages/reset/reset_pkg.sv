// ============================================================
// Reset Sequencer Verification Package
// ============================================================
package reset_pkg;

  parameter int RESET_MIN_PULSE_CYCLES = 4;  // minimum reset assertion width (cycles)
  parameter int RESET_MAX_PROP_CYCLES  = 8;  // maximum propagation delay between domains (cycles)

endpackage
