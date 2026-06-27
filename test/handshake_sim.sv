// ============================================================
// [テスト] Handshake SVA — Simulator
// スニペット: sva-sim-handshake を展開したサンプル
// Copilot Chat で生成したものを貼り付ける場所として使用
// ============================================================

// ---- ここにスニペットやCopilotが生成したSVAを貼り付けてテスト ----

// --- Snippet Test: sva-sim-handshake ---
// .sv ファイル内で "sva-sim-handshake" と入力 → Tab で展開確認

// --- Copilot Chat Test ---
// Copilot Chat (Cmd+Shift+I) に以下をコピペして試す:
//
//   【シミュレータ用】
//   valid/ready ハンドシェイクを検証する SVA を作って。
//   信号名: valid, ready, data (32bit)
//   クロック: clk, リセット: rst_n (active-low)

// ============================================================
// 期待される生成結果（参考）
// ============================================================

// valid が High の間、ready が来るまで valid を保持
property prop_valid_stable;
  @(posedge clk) disable iff (!rst_n)
  (valid && !ready) |=> valid;
endproperty

property prop_data_stable;
  @(posedge clk) disable iff (!rst_n)
  (valid && !ready) |=> $stable(data);
endproperty

AST_VALID_STABLE: assert property (prop_valid_stable)
  else $error("[ASSERT FAIL] VALID_STABLE: valid dropped before ready at %t", $time);
AST_DATA_STABLE:  assert property (prop_data_stable)
  else $error("[ASSERT FAIL] DATA_STABLE: data changed while valid at %t", $time);

COV_HANDSHAKE:    cover property (@(posedge clk) valid && ready);
COV_VALID_WAIT:   cover property (@(posedge clk) valid && !ready);
