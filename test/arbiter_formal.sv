// ============================================================
// [テスト] Arbiter SVA — Formal (non-determinism)
// スニペット: sva-fml-arbiter-helper + sva-fml-arbiter を展開したサンプル
// ============================================================

// --- Copilot Chat Test ---
// Copilot Chat (Cmd+Shift+I) に以下をコピペして試す:
//
//   【フォーマル検証用】
//   4 port アービターの mutual exclusion, no spurious grant,
//   starvation-freedom を検証する SVA と Verilog helper を生成して。
//   信号名: req[3:0], gnt[3:0]
//   最大待機サイクル: 16
//   クロック: clk, リセット: rst_n (active-low)

// ============================================================
// 期待される生成結果（スニペット sva-fml-arbiter 展開後の形）
// ============================================================

// 1. Safety

property prop_gnt_mutex;
  @(posedge clk) disable iff (!rst_n) $onehot0(gnt);
endproperty
AST_GNT_MUTEX: assert property (prop_gnt_mutex);

property prop_no_spurious_gnt;
  @(posedge clk) disable iff (!rst_n) (gnt & ~req) == '0;
endproperty
AST_NO_SPURIOUS_GNT: assert property (prop_no_spurious_gnt);

property prop_no_starvation;
  @(posedge clk) disable iff (!rst_n) !starvation;
endproperty
AST_NO_STARVATION: assert property (prop_no_starvation);

property prop_gnt_implies_req;
  @(posedge clk) disable iff (!rst_n) gnt[chosen] |-> req[chosen];
endproperty
AST_GNT_IMPLIES_REQ: assert property (prop_gnt_implies_req);

// 2. Reachability

COV_CHOSEN_GNT:            cover property (@(posedge clk) gnt[chosen]);
COV_CHOSEN_REQ:            cover property (@(posedge clk) req[chosen]);
COV_CHOSEN_GNT_CONTENTION: cover property (@(posedge clk) gnt[chosen] && (req != (1 << chosen)));
COV_ALL_REQ:               cover property (@(posedge clk) &req);

// 3. Environment

property assume_chosen_valid;
  @(posedge clk) chosen < 4;
endproperty
ENV_CHOSEN_VALID: assume property (assume_chosen_valid);

property assume_chosen_requests;
  @(posedge clk) disable iff (!rst_n) ##1 req[chosen];
endproperty
ENV_CHOSEN_REQUESTS: assume property (assume_chosen_requests);
