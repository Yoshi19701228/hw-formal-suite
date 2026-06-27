// ============================================================
// APB4 Verification Package
// Spec: AMBA 4 APB Protocol Specification (ARM IHI0024E)
// ============================================================
package apb4_pkg;

  // Protection attribute bits (pprot[2:0])
  typedef struct packed {
    logic instr;       // [2]: 0=data access, 1=instruction access
    logic non_secure;  // [1]: 0=secure,      1=non-secure access
    logic privileged;  // [0]: 0=normal,       1=privileged access
  } apb4_prot_t;

  // Transfer direction
  typedef enum logic { APB4_READ = 1'b0, APB4_WRITE = 1'b1 } apb4_dir_e;

  // Slave error response
  typedef enum logic { APB4_OKAY = 1'b0, APB4_SLVERR = 1'b1 } apb4_resp_e;

  // Default bounds (override via module parameters)
  parameter int APB4_MAX_WAIT_CYCLES = 16;  // max cycles PREADY may be deasserted

endpackage
