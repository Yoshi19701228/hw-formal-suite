// ============================================================
// APB3 Verification Package
// Spec: AMBA 3 APB Protocol Specification (ARM IHI0024C)
// ============================================================
package apb3_pkg;

  // Transfer direction
  typedef enum logic { APB3_READ = 1'b0, APB3_WRITE = 1'b1 } apb3_dir_e;

  // Slave error response
  typedef enum logic { APB3_OKAY = 1'b0, APB3_SLVERR = 1'b1 } apb3_resp_e;

  // Default bounds (override via module parameters)
  parameter int APB3_MAX_WAIT_CYCLES = 16;  // max cycles PREADY may be deasserted

endpackage
