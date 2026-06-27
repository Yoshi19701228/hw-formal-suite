package dma_pkg;
  typedef enum logic [1:0] {
    DMA_IDLE     = 2'b00,
    DMA_FETCH    = 2'b01,
    DMA_TRANSFER = 2'b10,
    DMA_DONE     = 2'b11
  } dma_state_e;

  typedef enum logic {
    DMA_RD = 1'b0,
    DMA_WR = 1'b1
  } dma_dir_e;

  parameter int DMA_MAX_BURST       = 256;  // max beats per transfer
  parameter int DMA_MAX_XFER_CYCLES = 1024; // max cycles for entire transfer
  parameter int DMA_MAX_BEAT_CYCLES = 64;   // max cycles between beats
endpackage
