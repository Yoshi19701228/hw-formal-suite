// ============================================================
// [テスト] FSM SVA — Formal (non-determinism)
// スニペット: sva-fml-fsm-helper + sva-fml-fsm を展開したサンプル
// ============================================================

// --- Copilot Chat Test ---
// Copilot Chat (Cmd+Shift+I) に以下をコピペして試す:
//
//   【フォーマル検証用】
//   4 状態 one-hot FSM (IDLE=4'b0001, REQ=4'b0010, PROC=4'b0100, DONE=4'b1000) の
//   デッドロック・ライブロック・初期状態を検証する SVA と
//   Verilog helper を生成して。
//   progress state は DONE, 最大待機サイクルは 32。
//   クロック: clk, リセット: rst_n (active-low)

// ============================================================
// 期待される生成結果 — helper (.v)
// ============================================================

// --- fsm_formal_helper.v ---
/*
module fsm_formal_helper #(
  parameter STATE_W      = 4,
  parameter PROGRESS_MASK = 4'b1000,  // DONE
  parameter MAX_NO_PROG  = 32
) (
  input  wire             clk,
  input  wire             rst_n,
  input  wire [STATE_W-1:0] state,
  input  wire [STATE_W-1:0] next_state,
  output reg              deadlock,
  output reg  [$clog2(MAX_NO_PROG+1)-1:0] cnt_no_progress,
  output reg              livelock,
  output wire [STATE_W-1:0] chosen_state
);
  assign chosen_state = $anyconst;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) deadlock <= 1'b0;
    else        deadlock <= |state && !|next_state;
  end

  wire in_progress = |(state & PROGRESS_MASK);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n || in_progress) begin
      cnt_no_progress <= '0;
      livelock        <= 1'b0;
    end else begin
      cnt_no_progress <= cnt_no_progress + 1;
      livelock        <= (cnt_no_progress >= MAX_NO_PROG - 1);
    end
  end
endmodule
*/

// ============================================================
// 期待される生成結果 — SVA (.sv)
// ============================================================

localparam IDLE = 4'b0001;
localparam REQ  = 4'b0010;
localparam PROC = 4'b0100;
localparam DONE = 4'b1000;
localparam FSM_PROGRESS_MASK = DONE;

// 1. Safety

property prop_state_during_reset;
  @(posedge clk) !rst_n |-> (state == IDLE);
endproperty
AST_STATE_IN_RESET: assert property (prop_state_during_reset);

property prop_reset_to_init;
  @(posedge clk) $rose(rst_n) |=> (state == IDLE);
endproperty
AST_RESET_TO_INIT: assert property (prop_reset_to_init);

property prop_valid_state;
  @(posedge clk) disable iff (!rst_n) $onehot(state);
endproperty
AST_VALID_STATE: assert property (prop_valid_state);

property prop_no_deadlock;
  @(posedge clk) disable iff (!rst_n) !deadlock;
endproperty
AST_NO_DEADLOCK: assert property (prop_no_deadlock);

property prop_no_livelock;
  @(posedge clk) disable iff (!rst_n) !livelock;
endproperty
AST_NO_LIVELOCK: assert property (prop_no_livelock);

// 2. Reachability

COV_INIT_STATE:   cover property (@(posedge clk) state == IDLE);
COV_CHOSEN_STATE: cover property (@(posedge clk) state == chosen_state);
COV_PROGRESS:     cover property (@(posedge clk) |(state & FSM_PROGRESS_MASK));

// 3. Environment

property assume_chosen_valid;
  @(posedge clk) $onehot(chosen_state);
endproperty
ENV_CHOSEN_VALID: assume property (assume_chosen_valid);
