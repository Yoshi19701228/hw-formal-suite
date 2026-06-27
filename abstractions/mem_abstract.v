// mem_abstract.v
// Abstract memory model for formal verification.
//
// Replaces a full SRAM/ROM array (2^ADDR_W x DATA_W bits) with a single
// shadow register that tracks exactly one $anyconst-chosen address.
// All other addresses return $anyseq (unconstrained but non-deterministic).
//
// Soundness:
//   - The chosen address behaves identically to the real memory.
//   - All other addresses are over-approximated (any value is possible).
//   - Any property that passes here is sound for the chosen address;
//     use this model to prove per-address invariants.
//
// Latency:
//   - Default LATENCY=1: ack fires the cycle after req.
//   - For LATENCY>1, extend the shift register below (currently a stub).
//
// Tool compatibility: Verilog-2001. $anyconst/$anyseq are Jasper/Questa
// Formal extensions; annotate with (* anyconst *) where tools prefer attributes.

`default_nettype none

module mem_abstract #(
    parameter ADDR_W  = 20,
    parameter DATA_W  = 32,
    parameter LATENCY = 1    // 1 = single-cycle ack; >1 not yet pipelined
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               req,
    input  wire               we,           // 1 = write, 0 = read
    input  wire [ADDR_W-1:0]  addr,
    input  wire [DATA_W-1:0]  wdata,
    output reg  [DATA_W-1:0]  rdata,
    output reg                ack
);

    // -------------------------------------------------------------------------
    // Symbolic constant: the one address the proof tracks precisely.
    // The formal tool fixes chosen_addr for the entire proof run.
    // -------------------------------------------------------------------------
    (* anyconst *) reg [ADDR_W-1:0] chosen_addr_reg;
    wire [ADDR_W-1:0] chosen_addr;
    assign chosen_addr = chosen_addr_reg;

    // Shadow storage for chosen_addr
    reg [DATA_W-1:0] shadow_data;
    reg              shadow_valid;  // 0 until the address has been written at least once

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shadow_data  <= {DATA_W{1'b0}};
            shadow_valid <= 1'b0;
            rdata        <= {DATA_W{1'b0}};
            ack          <= 1'b0;
        end else begin
            // Acknowledge one cycle after request (LATENCY = 1)
            ack <= req;

            // Write path: capture data only for the tracked address
            if (req && we && (addr == chosen_addr)) begin
                shadow_data  <= wdata;
                shadow_valid <= 1'b1;
            end

            // Read path
            if (req && !we) begin
                if ((addr == chosen_addr) && shadow_valid)
                    rdata <= shadow_data;   // authoritative value for chosen address
                else
                    rdata <= $anyseq;       // unconstrained for all other addresses
            end
        end
    end

    // -------------------------------------------------------------------------
    // Assertion: after a read of chosen_addr (when written at least once),
    // rdata must equal the last written value.
    // -------------------------------------------------------------------------
`ifdef FORMAL
    // MEM_ABS_DVI: Data-Value Integrity for the chosen address.
    // "The cycle after a read of chosen_addr with valid shadow, rdata equals
    //  whatever shadow_data held at the time of the request."
    MEM_ABS_DVI: assert property (
        @(posedge clk) disable iff (!rst_n)
        (req && !we && (addr == chosen_addr) && shadow_valid)
        |=> (rdata == $past(shadow_data))
    );

    // MEM_ABS_ACK_PULSE: ack follows req by exactly 1 cycle.
    MEM_ABS_ACK_PULSE: assert property (
        @(posedge clk) disable iff (!rst_n)
        req |=> ack
    );

    // MEM_ABS_NO_SPURIOUS_ACK: ack is never high without a prior req.
    MEM_ABS_NO_SPURIOUS_ACK: assert property (
        @(posedge clk) disable iff (!rst_n)
        ack |-> $past(req)
    );
`endif

endmodule

`default_nettype wire
