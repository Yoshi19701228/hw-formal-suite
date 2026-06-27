package mem_ctrl_pkg;
  typedef enum logic [1:0] {
    MEM_IDLE    = 2'b00,
    MEM_READ    = 2'b01,
    MEM_WRITE   = 2'b10,
    MEM_REFRESH = 2'b11   // DRAM refresh (optional)
  } mem_state_e;

  parameter int MEM_MAX_WAIT_CYCLES       = 16;   // max cycles before ack
  parameter int MEM_MAX_REFRESH_INTERVAL  = 7800; // DRAM: max cycles between refresh
endpackage
