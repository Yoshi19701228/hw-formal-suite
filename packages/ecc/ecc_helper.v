// ecc_helper.v
// Helper module for SECDED (Hamming + overall parity) ECC formal verification.
// Tracks a golden delayed copy of encoder input, detects injected single- and
// double-bit errors, and exposes $anyconst bit-position selectors.
// No assertions are placed here; all properties live in ecc_assert_fml.sv.

module ecc_helper #(
  parameter integer DATA_W      = 32,   // data width into the encoder
  parameter integer CHECK_W     = 7,    // SECDED check bits (p1..p32 + p_overall)
  parameter integer MAX_LATENCY = 4,    // encode->decode pipeline depth in cycles
  // Derived widths
  parameter integer CODEWORD_W  = DATA_W + CHECK_W,
  parameter integer BIT_SEL_W   = $clog2(CODEWORD_W)
) (
  input  wire                    clk,
  input  wire                    rst_n,

  // Encoder side
  input  wire [DATA_W-1:0]       enc_data_in,   // data presented to the encoder
  input  wire                    enc_valid,      // encoder input valid

  // Encoded output (DATA_W data bits + CHECK_W check bits)
  input  wire [CODEWORD_W-1:0]  enc_out,        // encoder output codeword

  // Decoder side (potentially corrupted codeword fed in)
  input  wire [CODEWORD_W-1:0]  dec_in,         // decoder input
  input  wire [DATA_W-1:0]      dec_data_out,   // corrected data from decoder
  input  wire                   dec_valid,       // decoder output valid
  input  wire                   dec_sec,         // single-error corrected flag
  input  wire                   dec_ded,         // double-error detected flag

  // Non-deterministic bit positions for error injection (driven by $anyconst)
  input  wire [BIT_SEL_W-1:0]  chosen_bit,      // first bit to flip
  input  wire [BIT_SEL_W-1:0]  chosen_bit2,     // second bit for double-error injection

  // Outputs to the assertion module
  output wire [BIT_SEL_W-1:0]  chosen_bit_out,   // mirrors chosen_bit
  output wire [BIT_SEL_W-1:0]  chosen_bit2_out,  // mirrors chosen_bit2

  output reg  [DATA_W-1:0]     golden_data,       // enc_data_in delayed by MAX_LATENCY cycles
  output wire [CODEWORD_W-1:0] corrupted,         // dec_in XOR'd conceptually (informational)
  output wire                  single_err_injected, // dec_in == enc_out ^ (1<<chosen_bit)
  output wire                  double_err_injected  // dec_in == enc_out ^ (1<<b1) ^ (1<<b2)
);

  // -------------------------------------------------------------------------
  // Non-deterministic bit selectors pass-through
  // -------------------------------------------------------------------------
  assign chosen_bit_out  = chosen_bit;
  assign chosen_bit2_out = chosen_bit2;

  // -------------------------------------------------------------------------
  // Golden data: shift-register delay of enc_data_in by MAX_LATENCY cycles.
  // This models the expected correct data that should emerge from the decoder
  // MAX_LATENCY cycles after it was presented to the encoder.
  // -------------------------------------------------------------------------
  reg [DATA_W-1:0] data_pipe [0:MAX_LATENCY-1];
  integer i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < MAX_LATENCY; i = i + 1)
        data_pipe[i] <= {DATA_W{1'b0}};
      golden_data <= {DATA_W{1'b0}};
    end else begin
      data_pipe[0] <= enc_data_in;
      for (i = 1; i < MAX_LATENCY; i = i + 1)
        data_pipe[i] <= data_pipe[i-1];
      golden_data <= data_pipe[MAX_LATENCY-1];
    end
  end

  // -------------------------------------------------------------------------
  // Error masks derived from the chosen bit positions.
  // These are purely combinatorial — the formal tool's $anyconst keeps
  // chosen_bit and chosen_bit2 fixed for the entire proof.
  // -------------------------------------------------------------------------

  // One-hot masks for the selected bit positions
  wire [CODEWORD_W-1:0] mask1 = {{(CODEWORD_W-1){1'b0}}, 1'b1} << chosen_bit;
  wire [CODEWORD_W-1:0] mask2 = {{(CODEWORD_W-1){1'b0}}, 1'b1} << chosen_bit2;

  // Corrupted codeword (informational; not used to drive dec_in from here)
  assign corrupted = enc_out ^ mask1;

  // Single-error injection: exactly one bit of dec_in differs from enc_out,
  // specifically the bit selected by chosen_bit.
  assign single_err_injected = (dec_in == (enc_out ^ mask1));

  // Double-error injection: exactly two bits of dec_in differ from enc_out,
  // at the positions chosen_bit and chosen_bit2, which must be distinct.
  assign double_err_injected = (dec_in == (enc_out ^ mask1 ^ mask2))
                             && (chosen_bit != chosen_bit2);

endmodule
