// ============================================================
// Reset Sequencer Formal Helper — Verilog
//
// Provides:
//   chosen_domain — $anyconst index for focused per-domain proof
//   cnt_pulse     — cycles chosen_domain reset has been continuously asserted
//   pulse_too_short — reset deasserted before MIN_PULSE cycles elapsed
//   sr_por        — shift register tracking por_n propagation (depth MAX_PROP)
//   prop_timeout  — chosen_domain reset not deasserted within MAX_PROP after
//                   por_n deasserts (i.e. DUT failed to release reset in time)
//
// Usage:
//   reset_helper     #(.N_DOMAINS(4), .MIN_PULSE(4), .MAX_PROP(8)) u_hlp (
//     .clk, .por_n, .rst_out, .chosen_domain,
//     .cnt_pulse, .pulse_too_short, .sr_por, .prop_timeout);
//   reset_assert_fml #(.N_DOMAINS(4), .MIN_PULSE(4), .MAX_PROP(8)) u_fml (.*);
// ============================================================
module reset_helper #(
  parameter integer N_DOMAINS = 4,
  parameter integer MIN_PULSE = 4,
  parameter integer MAX_PROP  = 8
)(
  input  wire                          clk,
  input  wire                          por_n,           // power-on reset, active-low
  input  wire [N_DOMAINS-1:0]          rst_out,         // DUT reset outputs, active-high

  // Outputs consumed by reset_assert_fml
  output wire [$clog2(N_DOMAINS)-1:0]  chosen_domain,
  output reg  [$clog2(MIN_PULSE+1)-1:0] cnt_pulse,
  output reg                            pulse_too_short,
  output reg  [MAX_PROP-1:0]            sr_por,
  output reg                            prop_timeout
);

  // Non-deterministic domain selection — held constant by formal engine
  (* anyconst *) reg [$clog2(N_DOMAINS)-1:0] chosen_domain_r;
  assign chosen_domain = chosen_domain_r;

  // --------------------------------------------------------
  // Pulse-width counter for the chosen domain
  // Increments while rst_out[chosen_domain] is asserted (high)
  // --------------------------------------------------------
  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      cnt_pulse     <= {($clog2(MIN_PULSE+1)){1'b0}};
      pulse_too_short <= 1'b0;
    end else begin
      if (rst_out[chosen_domain_r]) begin
        if (cnt_pulse < MIN_PULSE)
          cnt_pulse <= cnt_pulse + 1;
      end else begin
        // Detect falling edge of chosen domain reset
        pulse_too_short <= (cnt_pulse < MIN_PULSE) && (cnt_pulse != 0);
        cnt_pulse       <= {($clog2(MIN_PULSE+1)){1'b0}};
      end
    end
  end

  // --------------------------------------------------------
  // Shift register: tracks how long ago por_n deasserted
  // sr_por[0] = !por_n one cycle ago, sr_por[MAX_PROP-1] = MAX_PROP cycles ago
  // --------------------------------------------------------
  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      sr_por <= {MAX_PROP{1'b0}};
    end else begin
      sr_por <= {sr_por[MAX_PROP-2:0], !por_n};
    end
  end

  // prop_timeout: por_n has been high (deasserted) for at least MAX_PROP cycles
  // but chosen_domain reset is still asserted — DUT is too slow to release it
  always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
      prop_timeout <= 1'b0;
    end else begin
      prop_timeout <= sr_por[MAX_PROP-1] && rst_out[chosen_domain_r];
    end
  end

endmodule
