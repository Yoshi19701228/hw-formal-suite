// ============================================================
// APB5 Formal Helper — Verilog
// Provides: timeout flag (replaces ##[0:MAX_WAIT] PREADY)
//           wakeup timeout flag (pwakeup held without psel)
//           pauser_changed / pwuser_changed stability flags
// ============================================================
module apb5_helper #(
  parameter integer DATA_W     = 32,
  parameter integer USER_W     = 4,
  parameter integer MAX_WAIT   = 16,
  parameter integer MAX_WAKEUP = 8
)(
  input  wire                           clk,
  input  wire                           rst_n,
  input  wire                           psel,
  input  wire                           penable,
  input  wire                           pwrite,
  input  wire [DATA_W/8-1:0]            pstrb,
  input  wire [2:0]                     pprot,
  input  wire                           pready,
  input  wire                           pwakeup,
  input  wire [USER_W-1:0]              pauser,
  input  wire [USER_W-1:0]              pwuser,

  // PREADY wait counter outputs
  output reg  [$clog2(MAX_WAIT+1)-1:0]   cnt_pready_wait,
  output reg                              pready_timeout,

  // Wakeup counter outputs
  output reg  [$clog2(MAX_WAKEUP+1)-1:0] cnt_wakeup,
  output reg                              wakeup_timeout,

  // User signal stability flags
  output reg                              pauser_changed,
  output reg                              pwuser_changed
);

  // Previous cycle values for change detection
  reg [USER_W-1:0] pauser_prev;
  reg [USER_W-1:0] pwuser_prev;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_pready_wait <= {($clog2(MAX_WAIT+1)){1'b0}};
      pready_timeout  <= 1'b0;
      cnt_wakeup      <= {($clog2(MAX_WAKEUP+1)){1'b0}};
      wakeup_timeout  <= 1'b0;
      pauser_prev     <= {USER_W{1'b0}};
      pwuser_prev     <= {USER_W{1'b0}};
      pauser_changed  <= 1'b0;
      pwuser_changed  <= 1'b0;
    end else begin
      // PREADY wait counter: increment during access phase without PREADY
      if (psel && penable && !pready)
        cnt_pready_wait <= cnt_pready_wait + 1;
      else
        cnt_pready_wait <= {($clog2(MAX_WAIT+1)){1'b0}};

      pready_timeout <= (cnt_pready_wait >= MAX_WAIT - 1) && psel && penable && !pready;

      // Wakeup counter: counts cycles pwakeup is asserted without psel
      // Resets when psel asserts (wakeup was honored)
      if (psel) begin
        cnt_wakeup     <= {($clog2(MAX_WAKEUP+1)){1'b0}};
        wakeup_timeout <= 1'b0;
      end else if (pwakeup) begin
        cnt_wakeup     <= cnt_wakeup + 1;
        wakeup_timeout <= (cnt_wakeup >= MAX_WAKEUP - 1);
      end else begin
        cnt_wakeup     <= {($clog2(MAX_WAKEUP+1)){1'b0}};
        wakeup_timeout <= 1'b0;
      end

      // Track pauser stability: flag if pauser changes during setup phase
      // Setup phase = psel asserted, penable not yet asserted
      pauser_prev    <= pauser;
      pauser_changed <= psel && !penable && (pauser != pauser_prev);

      // Track pwuser stability: flag if pwuser changes during write access phase
      pwuser_prev    <= pwuser;
      pwuser_changed <= psel && penable && pwrite && (pwuser != pwuser_prev);
    end
  end

endmodule
