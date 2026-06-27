package fifo_pkg;
  typedef enum logic [1:0] {
    FIFO_SYNC       = 2'b00,  // synchronous FIFO
    FIFO_ASYNC      = 2'b01,  // asynchronous FIFO (gray-code pointers)
    FIFO_SHOW_AHEAD = 2'b10   // show-ahead (first-word fall-through) FIFO
  } fifo_type_e;

  parameter int FIFO_MAX_DEPTH = 256;
endpackage
