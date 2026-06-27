// ============================================================
// AXI4 Verification Package
// Spec: AMBA AXI and ACE Protocol Specification (ARM IHI0022H)
// ============================================================
package axi4_pkg;

  // RESP encoding
  typedef enum logic [1:0] {
    AXI4_OKAY   = 2'b00,
    AXI4_EXOKAY = 2'b01,
    AXI4_SLVERR = 2'b10,
    AXI4_DECERR = 2'b11
  } axi4_resp_e;

  // BURST encoding
  typedef enum logic [1:0] {
    AXI4_FIXED  = 2'b00,
    AXI4_INCR   = 2'b01,
    AXI4_WRAP   = 2'b10
  } axi4_burst_e;

  // SIZE encoding (bytes per beat = 2**SIZE)
  typedef enum logic [2:0] {
    AXI4_SIZE_1B   = 3'b000,
    AXI4_SIZE_2B   = 3'b001,
    AXI4_SIZE_4B   = 3'b010,
    AXI4_SIZE_8B   = 3'b011,
    AXI4_SIZE_16B  = 3'b100,
    AXI4_SIZE_32B  = 3'b101,
    AXI4_SIZE_64B  = 3'b110,
    AXI4_SIZE_128B = 3'b111
  } axi4_size_e;

  // Default bounds (override via module parameters)
  parameter int AXI4_MAX_WAIT_CYCLES   = 256;  // max handshake stall
  parameter int AXI4_MAX_OUTSTANDING   = 16;   // max in-flight write transactions

endpackage
