// ============================================================
// AXI3 Verification Package
// Spec: AMBA AXI Protocol Specification (ARM IHI0022D, rev: AXI3)
// ============================================================
package axi3_pkg;

  // RESP encoding (identical bit values to AXI4)
  typedef enum logic [1:0] {
    AXI3_OKAY   = 2'b00,
    AXI3_EXOKAY = 2'b01,
    AXI3_SLVERR = 2'b10,
    AXI3_DECERR = 2'b11
  } axi3_resp_e;

  // BURST encoding
  typedef enum logic [1:0] {
    AXI3_FIXED  = 2'b00,
    AXI3_INCR   = 2'b01,
    AXI3_WRAP   = 2'b10
  } axi3_burst_e;

  // LOCK encoding (2-bit in AXI3; AXI4 reduced this to 1-bit)
  typedef enum logic [1:0] {
    AXI3_LOCK_NORMAL    = 2'b00,
    AXI3_LOCK_EXCLUSIVE = 2'b01,
    AXI3_LOCK_LOCKED    = 2'b10  // deprecated; 2'b11 is reserved
  } axi3_lock_e;

  // SIZE encoding (bytes per beat = 2**SIZE; identical to AXI4)
  typedef enum logic [2:0] {
    AXI3_SIZE_1B   = 3'b000,
    AXI3_SIZE_2B   = 3'b001,
    AXI3_SIZE_4B   = 3'b010,
    AXI3_SIZE_8B   = 3'b011,
    AXI3_SIZE_16B  = 3'b100,
    AXI3_SIZE_32B  = 3'b101,
    AXI3_SIZE_64B  = 3'b110,
    AXI3_SIZE_128B = 3'b111
  } axi3_size_e;

  // AXI3 limits
  parameter int AXI3_MAX_BURST      = 16;   // max beats per transaction (AWLEN/ARLEN is 4-bit)
  parameter int AXI3_MAX_WAIT_CYCLES = 256;  // max handshake stall cycles
  parameter int AXI3_MAX_OUTSTANDING = 16;   // max in-flight transactions per channel

endpackage
