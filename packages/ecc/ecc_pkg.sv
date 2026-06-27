package ecc_pkg;
  typedef enum logic [1:0] {
    ECC_NO_ERROR     = 2'b00,  // no error detected
    ECC_SINGLE_ERROR = 2'b01,  // single-bit error correctable
    ECC_DOUBLE_ERROR = 2'b10,  // double-bit error uncorrectable
    ECC_MULTI_ERROR  = 2'b11   // multiple errors (undefined)
  } ecc_error_type_e;

  parameter int ECC_MAX_PIPELINE_LATENCY = 4; // encode->decode pipeline stages
endpackage
