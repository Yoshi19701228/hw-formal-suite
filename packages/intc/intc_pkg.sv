// ============================================================
// Interrupt Controller Verification Package
// ============================================================
package intc_pkg;

  typedef enum logic [1:0] {
    INTC_LEVEL = 2'b00,  // level-sensitive trigger
    INTC_EDGE  = 2'b01,  // edge-sensitive trigger
    INTC_PULSE = 2'b10   // pulse trigger
  } intc_trigger_e;

  parameter int INTC_MAX_LATENCY = 32;  // max cycles from IRQ assert to ack

endpackage
