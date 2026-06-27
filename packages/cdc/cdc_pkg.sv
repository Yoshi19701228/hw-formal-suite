package cdc_pkg;
  // Synchronizer types
  typedef enum logic [1:0] {
    CDC_SYNC_2FF   = 2'b00,  // 2-flop synchronizer
    CDC_SYNC_3FF   = 2'b01,  // 3-flop synchronizer
    CDC_SYNC_GRAY  = 2'b10,  // gray-code based (async FIFO pointers)
    CDC_SYNC_HAND  = 2'b11   // handshake synchronizer
  } cdc_sync_type_e;

  parameter int CDC_MAX_SYNC_LATENCY  = 4;  // max sync latency in dst_clk cycles
  parameter int CDC_MAX_SETTLE_CYCLES = 8;  // max cycles for settled signal
endpackage
