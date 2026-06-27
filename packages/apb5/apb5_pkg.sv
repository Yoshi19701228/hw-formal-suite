// ============================================================
// APB5 Verification Package
// Spec: AMBA 5 APB Protocol Specification (ARM IHI0024F)
// ============================================================
package apb5_pkg;

  // Protection attribute bits (pprot[2:0]) — same encoding as APB4
  typedef struct packed {
    logic instr;       // [2]: 0=data access, 1=instruction access
    logic non_secure;  // [1]: 0=secure,      1=non-secure access
    logic privileged;  // [0]: 0=normal,       1=privileged access
  } apb5_prot_t;

  // Transfer direction
  typedef enum logic { APB5_READ = 1'b0, APB5_WRITE = 1'b1 } apb5_dir_e;

  // Slave error response
  typedef enum logic { APB5_OKAY = 1'b0, APB5_SLVERR = 1'b1 } apb5_resp_e;

  // Default bounds (override via module parameters)
  parameter int APB5_MAX_WAIT_CYCLES   = 16;  // max cycles PREADY may be deasserted
  parameter int APB5_MAX_WAKEUP_CYCLES = 8;   // max cycles after PWAKEUP before PSEL asserts

endpackage
