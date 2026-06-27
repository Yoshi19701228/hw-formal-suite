package watchdog_pkg;
  typedef enum logic [1:0] {
    WDT_IDLE    = 2'b00,
    WDT_RUNNING = 2'b01,
    WDT_EXPIRED = 2'b10,
    WDT_RESET   = 2'b11
  } wdt_state_e;

  parameter int WDT_MIN_TIMEOUT = 4;     // min allowed timeout value
  parameter int WDT_MAX_TIMEOUT = 65536; // max allowed timeout value
endpackage
