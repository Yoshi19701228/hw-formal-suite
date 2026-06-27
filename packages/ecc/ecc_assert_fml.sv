// ecc_assert_fml.sv
// Formal assertion module for SECDED ECC (Hamming + overall parity) verification.
// Instantiate (or bind) alongside the encoder/decoder DUT.
// Order: assert (safety) -> cover (reachability) -> assume (environment).
// No $error calls — this module targets formal property checking only.
//
// Usage (bind):
//   bind <dut_module> ecc_assert_fml #(...) u_fml (.*);

`default_nettype none

module ecc_assert_fml
  import ecc_pkg::*;
#(
  parameter integer DATA_W      = 32,
  parameter integer CHECK_W     = 7,
  parameter integer MAX_LATENCY = ECC_MAX_PIPELINE_LATENCY,
  // Derived widths
  parameter integer CODEWORD_W  = DATA_W + CHECK_W,
  parameter integer BIT_SEL_W   = $clog2(CODEWORD_W)
) (
  input wire                   clk,
  input wire                   rst_n,

  // Encoder side
  input wire [DATA_W-1:0]      enc_data_in,
  input wire                   enc_valid,

  // Encoder output (codeword)
  input wire [CODEWORD_W-1:0] enc_out,

  // Decoder side
  input wire [CODEWORD_W-1:0] dec_in,
  input wire [DATA_W-1:0]     dec_data_out,
  input wire                  dec_valid,
  input wire                  dec_sec,           // single-error corrected
  input wire                  dec_ded            // double-error detected
);

  // ============================================================
  // [Helper Logic] — golden data pipeline and error injection
  //   (inlined from ecc_helper.v)
  // ============================================================

  // Non-deterministic bit selectors (driven by $anyconst via formal tool)
  wire [BIT_SEL_W-1:0] chosen_bit;
  wire [BIT_SEL_W-1:0] chosen_bit2;
  assign chosen_bit  = $anyconst;
  assign chosen_bit2 = $anyconst;

  // Golden data: shift-register delay of enc_data_in by MAX_LATENCY cycles.
  reg [DATA_W-1:0] data_pipe [0:MAX_LATENCY-1];
  reg [DATA_W-1:0] golden_data;
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

  // Error masks derived from the chosen bit positions.
  wire [CODEWORD_W-1:0] mask1 = {{(CODEWORD_W-1){1'b0}}, 1'b1} << chosen_bit;
  wire [CODEWORD_W-1:0] mask2 = {{(CODEWORD_W-1){1'b0}}, 1'b1} << chosen_bit2;

  // Single-error injection: exactly one bit of dec_in differs from enc_out
  wire single_err_injected = (dec_in == (enc_out ^ mask1));

  // Double-error injection: exactly two bits of dec_in differ from enc_out
  wire double_err_injected = (dec_in == (enc_out ^ mask1 ^ mask2))
                           && (chosen_bit != chosen_bit2);

  // Default clock and reset for SVA
  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ===========================================================================
  // SAFETY ASSERTIONS
  // ===========================================================================

  // AST_ECC_CORRECT_DATA
  // If no uncorrectable error is flagged and the decoder output is valid,
  // the decoded data must match the original (golden) encoder input.
  AST_ECC_CORRECT_DATA:
    assert property (
      (!dec_ded && dec_valid)
      |-> (dec_data_out == golden_data)
    );

  // AST_ECC_SEC_ON_SINGLE
  // A single injected bit error must always trigger the SEC flag.
  AST_ECC_SEC_ON_SINGLE:
    assert property (
      (single_err_injected && dec_valid)
      |-> dec_sec
    );

  // AST_ECC_DED_ON_DOUBLE
  // A double injected bit error must always trigger the DED flag.
  AST_ECC_DED_ON_DOUBLE:
    assert property (
      (double_err_injected && dec_valid)
      |-> dec_ded
    );

  // AST_ECC_NO_ERROR_CLEAN
  // When the decoder input is identical to the encoder output (no corruption),
  // neither the SEC nor DED flag may be asserted.
  AST_ECC_NO_ERROR_CLEAN:
    assert property (
      (dec_in == enc_out && dec_valid)
      |-> (!dec_sec && !dec_ded)
    );

  // AST_ECC_RESET
  // During reset the decoder output valid must be deasserted.
  AST_ECC_RESET:
    assert property (
      !rst_n |-> !dec_valid
    );

  // ===========================================================================
  // REACHABILITY COVERS
  // ===========================================================================

  // COV_ECC_CLEAN_DECODE
  // Verify that a clean (error-free) decode can complete.
  COV_ECC_CLEAN_DECODE:
    cover property (
      dec_valid && !dec_sec && !dec_ded
    );

  // COV_ECC_SEC
  // Verify that the single-error-corrected path is reachable.
  COV_ECC_SEC:
    cover property (
      dec_sec
    );

  // COV_ECC_DED
  // Verify that the double-error-detected path is reachable.
  COV_ECC_DED:
    cover property (
      dec_ded
    );

  // COV_ECC_SINGLE_INJECTED
  // Verify that a single-bit error injection scenario is reachable.
  COV_ECC_SINGLE_INJECTED:
    cover property (
      single_err_injected
    );

  // COV_ECC_DOUBLE_INJECTED
  // Verify that a double-bit error injection scenario is reachable.
  COV_ECC_DOUBLE_INJECTED:
    cover property (
      double_err_injected
    );

  // ===========================================================================
  // ENVIRONMENT ASSUMPTIONS
  // ===========================================================================

  // ENV_ECC_CHOSEN_BIT_VALID
  // The primary error-injection bit position must index a valid codeword bit.
  ENV_ECC_CHOSEN_BIT_VALID:
    assume property (
      chosen_bit < BIT_SEL_W'(CODEWORD_W)
    );

  // ENV_ECC_CHOSEN_BIT2_VALID
  // The secondary error-injection bit position must index a valid codeword bit.
  ENV_ECC_CHOSEN_BIT2_VALID:
    assume property (
      chosen_bit2 < BIT_SEL_W'(CODEWORD_W)
    );

  // ENV_ECC_BITS_DIFFER
  // The two chosen bit positions must be distinct for a genuine double-bit error.
  ENV_ECC_BITS_DIFFER:
    assume property (
      chosen_bit != chosen_bit2
    );

  // ENV_ECC_ENC_VALID_STABLE
  // No additional constraint is placed on enc_valid; it may toggle freely.
  // This placeholder documents the decision explicitly.
  // (No assume property body needed — all transitions are legal.)

endmodule

`default_nettype wire
