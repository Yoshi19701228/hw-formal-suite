# HW Formal Suite — VS Code + GitHub Copilot

Describe what you want to verify in English or Japanese, and get SystemVerilog Assertions, protocol verification packages, and formal abstraction models generated automatically.
Supports both **Simulator** and **Formal Verification** modes.

---

## Setup

1. Open the `hw-formal-suite/` folder in VS Code (**folder**, not a single file)
2. Install recommended extensions when prompted (see below)
3. `.github/copilot-instructions.md` is loaded automatically by Copilot ✅

> **Requires**: VS Code 1.90+ and GitHub Copilot Chat 0.16+

### Recommended Extensions

| Extension | Purpose |
|---|---|
| `GitHub.copilot` | Assertion generation |
| `GitHub.copilot-chat` | Chat interface (`Cmd+Shift+I`) |
| `mshr-k.veriloghdl` or `eirikpre.systemverilog` | `.sv` / `.v` language support for snippets |

VS Code shows an "Install Recommended Extensions" prompt automatically, or search `@recommended` in the Extensions panel.

---

## Usage

Open Copilot Chat (`Cmd+Shift+I`) and describe what you want to verify:

**English examples:**
```
[Simulator] Generate SVA to verify AXI4 write channel handshake.
Signal names: awvalid, awready, wvalid, wready. Clock: clk, reset: rst_n.
```

```
[Formal] Verify that req gets an ack within 16 cycles.
Signal names: req_valid, ack_valid. Use non-determinism where appropriate.
```

```
[Formal] Generate FSM assertions for deadlock freedom, livelock freedom,
and initial state. States: IDLE, REQ, PROC, DONE (one-hot, 4 bits).
Progress state: DONE. Max wait: 32 cycles.
```

**Japanese examples:**
```
【シミュレータ用】AXI4 の Write handshake を検証する SVA を作って。
信号名: awvalid, awready, wvalid, wready。クロック: clk、リセット: rst_n。
```

```
【フォーマル検証用】req から 16 サイクル以内に ack が返ることを確認したい。
信号名: req_valid, ack_valid。non-determinism を活用して。
```

If you do not specify an environment, Copilot will ask before generating.

---

## Integration: helper + assertion の使い方

> 詳細は **[docs/integration.md](docs/integration.md)** を参照。

### helper と assertion の役割

```
*_helper.v           DUT の外に置く Verilog モジュール
  ├── timeout counter    → ##[1:N] の代替フラグを出力
  ├── ghost state        → golden_data / shadow_count などを出力
  └── $anyconst 値       → chosen_addr など

      ↓ output wires をそのまま接続

*_assert_fml.sv      SVA アサーションモジュール (bind またはインスタンス化)
  ├── DUT の信号を入力として受け取る
  └── helper の出力も入力として受け取る
```

### シミュレータ: 2 ステップ

```systemverilog
// ① ファイルをコンパイルリストに追加
// vlog packages/apb3/apb3_assert_sim.sv

// ② testbench で bind
bind apb3_slave apb3_assert_sim #(.ADDR_W(32), .DATA_W(32)) u_chk (.*);
//                                                                   ^^
//                           DUT 内の信号名とポート名が一致していれば .* でOK
```

### フォーマル: ラッパーパターン (推奨)

helper の出力を assertion に渡すため、**同じスコープ**に両方をインスタンス化します。

```systemverilog
// formal_top/apb3_formal_top.sv
module apb3_formal_top;
  logic clk, rst_n, psel, penable, pwrite, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;

  apb3_slave u_dut (.PCLK(clk), .PRESETn(rst_n), .PSEL(psel), /* ... */);

  // ① helper を DUT の隣にインスタンス化
  logic [4:0] cnt_pready_wait;
  logic       pready_timeout;

  apb3_helper #(.DATA_W(32)) u_hlp (
    .clk(clk), .rst_n(rst_n),
    .psel(psel), .penable(penable), .pready(pready),
    .cnt_pready_wait(cnt_pready_wait),   // ← 出力
    .pready_timeout(pready_timeout)      // ← 出力
  );

  // ② assertion モジュールに DUT 信号 + helper 出力を渡す
  apb3_assert_fml #(.ADDR_W(32), .DATA_W(32)) u_fml (
    .clk(clk), .rst_n(rst_n),
    .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata), .pready(pready),
    .prdata(prdata), .pslverr(pslverr),
    .cnt_pready_wait(cnt_pready_wait),   // ← helper から
    .pready_timeout(pready_timeout)      // ← helper から
  );
endmodule
```

> `bind` に helper と assertion を両方 bind すると helper の出力ワイヤが assertion から見えなくなります。**フォーマルはラッパーパターンを使ってください。**

Copilot Chat で `「[DUT名] のフォーマル用ラッパーを生成して」` と入力すると、使用パッケージのポートリストに基づいてラッパーを自動生成します。

---

## Two Modes

### Simulator

| Item | Details |
|---|---|
| Output | `assert property` + `cover property` |
| Error reporting | `$error("[ASSERT FAIL] NAME: %t", $time)` |
| Complex sequences | `##[M:N]`, `[*N]`, `throughout`, etc. — all supported |
| File layout | Single `.sv` file |

### Formal Verification

| Item | Details |
|---|---|
| Output | `assert` (safety) + `cover` (reachability) + `assume` (environment) |
| Error reporting | None (not supported by formal tools) |
| Convergence | Complex delays / repetitions replaced by Verilog helper logic |
| File layout | `*_helper.v` (Verilog) + `*_assert.sv` (SVA) |

**Why Verilog helper logic?**

| SVA construct | Problem | Helper replacement |
|---|---|---|
| `##[1:16] ack` | State-space explosion | Timeout counter (`cnt_req_pending`) |
| `$past(sig, N)` N > 1 | State growth | Shift register (`sr_addr`) |
| `[*N]` N > 4 | State-space explosion | Cycle counter |
| Accumulated counts | Hard to express in SVA | Outstanding counter |

**Non-determinism (`$anyconst`)** — used in Formal mode for arbiter and FSM patterns to prove properties hold for *any* port / state without enumerating all cases.

---

## Snippets

Type a prefix in a `.sv` or `.v` file and press `Tab` to expand.

### Simulator

| Prefix | Content |
|---|---|
| `sva-sim-prop` | Basic property + assert + cover |
| `sva-sim-handshake` | valid/ready stability |
| `sva-sim-req-ack` | req → ack timeout (`##[1:N]`) |
| `sva-sim-fifo` | FIFO overflow / underflow |
| `sva-sim-arbiter` | Arbiter: mutex + no spurious grant + fairness (generate) |
| `sva-sim-fsm` | FSM: initial state + encoding + deadlock + livelock + reachability |

### Formal Verification

| Prefix | Content |
|---|---|
| `sva-fml-prop` | Simple property + assert + reachability cover |
| `sva-fml-assume` | Environment constraint (`assume property`) |
| `sva-fml-handshake` | valid/ready stability + reachability cover + assume |
| `sva-fml-cnt-helper` | Timeout counter helper (`.v`) + SVA |
| `sva-fml-sr-helper` | Shift register helper (`.v`) |
| `sva-fml-out-helper` | Outstanding transaction counter helper (`.v`) |
| `sva-fml-arbiter-helper` | Arbiter non-determinism helper (`.v`) — `$anyconst` |
| `sva-fml-arbiter` | Arbiter SVA: mutex + starvation + reachability + assume |
| `sva-fml-fsm-helper` | FSM helper (`.v`) — deadlock flag + livelock counter + `$anyconst` |
| `sva-fml-fsm` | FSM SVA: initial state + deadlock + livelock + reachability + assume |

### Common

| Prefix | Content |
|---|---|
| `sva-mutex` | Mutual exclusion |
| `sva-onehot` | One-hot encoding check |
| `sva-seq` | Named sequence block |

---

## Generated File Layout

```
Simulator:
  design_assert.sv          assert + cover + $error

Formal:
  design_helper.v           Verilog helper logic (counters, shift registers, flags)
  design_assert.sv          (1) assert  — safety
                            (2) cover   — reachability
                            (3) assume  — environment constraints
```

---

## Protocol Packages

Pre-built assertion modules for standard bus protocols. Use `bind` to attach non-intrusively to any DUT.

```
packages/
  apb3/
    apb3_pkg.sv              Types and default parameters
    apb3_assert_sim.sv       Simulator assertions (bind-able)
    apb3_assert_fml.sv       Formal assertions (bind-able)
    apb3_helper.v            Verilog helper: PREADY timeout counter
  apb4/
    apb4_pkg.sv              apb4_prot_t struct, dir/resp enums, MAX_WAIT
    apb4_assert_sim.sv       All APB3 rules + PSTRB/PPROT stability, partial-write cover
    apb4_assert_fml.sv       Formal assertions (no $error, uses helper flags)
    apb4_helper.v            PREADY timeout counter + pstrb_changed flag
  apb5/
    apb5_pkg.sv              Adds MAX_WAKEUP_CYCLES to APB4 types
    apb5_assert_sim.sv       All APB4 rules + PWAKEUP timeout, user signal stability
    apb5_assert_fml.sv       Formal assertions with wakeup_timeout, pauser/pwuser flags
    apb5_helper.v            PREADY + wakeup timeout counters + user signal change flags
  axi3/
    axi3_pkg.sv              resp/burst/lock/size enums, MAX_BURST=16
    axi3_assert_sim.sv       All 5 channels: stability, 4-bit AWLEN, 2-bit LOCK, WID
    axi3_assert_fml.sv       Formal assertions: timeouts, WLAST, outstanding overflow
    axi3_helper.v            5-channel timeouts, 4-bit beat counter, outstanding counters
  axi4/
    axi4_pkg.sv              Types (resp/burst/size enums) and defaults
    axi4_assert_sim.sv       Simulator assertions (bind-able)
    axi4_assert_fml.sv       Formal assertions (bind-able)
    axi4_helper.v            Verilog helpers: timeouts, beat counter, outstanding counter
  cache/
    cache_pkg.sv             Types: MESI states, write policy, operation type
    cache_assert_fml.sv      Formal assertions: DVI, writeback, refill, timeouts
    cache_helper.v           $anyconst addr, ghost state, timeout counters
  cdc/
    cdc_pkg.sv               Sync type enum and latency parameters
    cdc_assert_fml.sv        Formal assertions: no-glitch, settled value, timeout
    cdc_helper.v             Uncertainty window, settled flag, sync timeout counter
  fifo/
    fifo_pkg.sv              FIFO type enum and max depth
    fifo_assert_sim.sv       Simulator assertions: overflow, underflow, count, flags
    fifo_assert_fml.sv       Formal assertions: same + $anyconst entry DVI
    fifo_helper.v            $anyconst entry, shadow count, overflow/underflow flags
  intc/
    intc_pkg.sv              Trigger type enum and max latency
    intc_assert_fml.sv       Formal assertions: mask, sticky, ack, no-starvation
    intc_helper.v            $anyconst IRQ, starvation counter
  reset/
    reset_pkg.sv             Min pulse and max propagation parameters
    reset_assert_fml.sv      Formal assertions: pulse width, propagation, no-glitch
    reset_helper.v           $anyconst domain, pulse counter, propagation shift register
  counter/
    counter_pkg.sv           Overflow mode and direction enums
    counter_assert_sim.sv    Simulator assertions with $error
    counter_assert_fml.sv    Formal assertions (no helper needed)
  dma/
    dma_pkg.sv               State, direction enums and timing parameters
    dma_assert_fml.sv        Formal assertions: beat timeout, address range, done
    dma_helper.v             $anyconst beat, beat counter, expected address, timeouts
  watchdog/
    watchdog_pkg.sv          State enum and timeout bounds
    watchdog_assert_sim.sv   Simulator assertions with $error
    watchdog_assert_fml.sv   Formal assertions: no false positive/negative, kick, reset
    watchdog_helper.v        Shadow counter, true_timeout, false_positive/negative flags
  xbar/
    xbar_pkg.sv              State enum and latency/outstanding parameters
    xbar_assert_fml.sv       Formal assertions: routing, timeout, outstanding overflow
    xbar_helper.v            $anyconst master/slave, latency counter, outstanding counter
  ecc/
    ecc_pkg.sv               Error type enum and pipeline latency
    ecc_assert_fml.sv        Formal assertions: correct decode, SEC, DED, no false error
    ecc_helper.v             $anyconst bit positions, golden data delay, error injection
  mem_ctrl/
    mem_ctrl_pkg.sv          State enum and timing parameters
    mem_ctrl_assert_fml.sv   Formal assertions: read-after-write (DVI), timing, stability
    mem_ctrl_helper.v        $anyconst addr, ghost state (golden_data), wait timeout
```

### Quick Start

```systemverilog
// APB3 — Simulator (bind to slave)
bind apb3_slave apb3_assert_sim #(.ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)) u_chk (.*);

// AXI4 — Formal (instantiate helper, then bind assertion module)
axi4_helper      #(.DATA_W(64), .MAX_WAIT(256)) u_hlp (.*);
bind axi4_master axi4_assert_fml #(.ADDR_W(32), .DATA_W(64)) u_chk (.*);

// Cache — Formal ($anyconst + ghost state)
cache_helper     #(.ADDR_W(32), .DATA_W(32), .LINE_W(256)) u_hlp (.*);
bind cache_top   cache_assert_fml #(.ADDR_W(32), .DATA_W(32), .WRITE_POLICY(WRITE_BACK)) u_chk (.*);
```

### Cache Verification — Trigger Phrase

Say **"フォーマル検証でキャッシュ検証をしたいの"** (or "cache verification with formal") in Copilot Chat and it will:
1. Ask write policy (write-back / write-through), structure, and interface signals
2. Generate `cache_helper.v` (ghost state + $anyconst) and `cache_assert_fml.sv`
3. Explain each property (DVI, writeback completeness, refill correctness, etc.)

**Key technique — $anyconst + Ghost State:**

```
$anyconst chosen_addr  →  ghost state tracks golden_data for chosen_addr
                       →  assertions compare DUT output against golden_data
                       →  one proof covers ALL addresses simultaneously
```

### Assertions Covered

| Protocol | Safety | Reachability (Cover) | Formal Helper |
|---|---|---|---|
| **APB3** | PENABLE timing, signal stability, PREADY timeout, PSLVERR validity | write/read OK/ERR, wait states, back-to-back | PREADY timeout counter |
| **APB4** | All APB3 + PSTRB stability on write, PPROT stability, no strobe change in setup | partial write, privileged, non-secure, instruction access | PREADY timeout + pstrb_changed flag |
| **APB5** | All APB4 + PWAKEUP timeout, PAUSER/PWUSER stability, no user signal change | wakeup→PSEL path, NSE, user signals set, PBUSER response | APB4 helpers + wakeup counter + user change flags |
| **AXI3** | All 5 channels: signal stability, 4-bit AWLEN (max 16 beats), WRAP length, 2-bit LOCK, BRESP/RRESP legality, WLAST beat count | handshakes, wait states, exclusive R/W, WRAP burst, max-length burst | 5-channel timeout counters, 4-bit beat counter, outstanding counters |
| **AXI4** | xVALID stability, signal stability, SIZE/BURST validity, WLAST beat count, xRESP legality, outstanding overflow | per-channel handshake, LAST beats, SLVERR, stalls, bursts | per-channel timeout counters, beat counter, outstanding counters |
| **Cache** | DVI (data value invariant), no spurious hit, writeback completeness, refill correctness, miss/WB timeouts | hit, miss, store, miss→hit path, writeback, refill | $anyconst addr + ghost state (golden_data/valid/dirty) |
| **CDC** | No glitch outside uncertainty window, settled value matches source, sync timeout, reset stability | rising/falling edge sync, settled reached, uncertain window | Uncertainty window counter, settled flag, sync timeout counter |
| **FIFO** | No overflow/underflow, count integrity vs shadow, full/empty/almost flags | push, pop, full, empty, almost_full, simultaneous push+pop, full→empty | $anyconst entry + shadow_count + overflow/underflow flags |
| **INTC** | Mask respected, IRQ sticky, ack clears pending, no spurious output, no starvation | IRQ fires, chosen IRQ pending/acked, masked, multi-pending | $anyconst IRQ index + starvation counter |
| **Reset** | POR asserts all domains, min pulse width, propagation within bound, no glitch | domain assert/deassert, all asserted, all released | $anyconst domain + pulse counter + propagation shift register |
| **Counter** | Reset, clear, increment/decrement, saturate/wrap at boundary, overflow/underflow flags | max, min, mid value, overflow, underflow | None (properties simple enough without helper) |
| **DMA** | Beat timeout, transfer timeout, address within descriptor bounds, done after all beats | beat 0, beat N, done, fast complete | $anyconst beat + beat counter + expected address wires |
| **Watchdog** | No false positive (spurious expiry), no false negative (missed expiry), kick prevents, disabled no-expiry | expired, kick-prevents, enabled, ack | Shadow counter + true_timeout + false_positive/negative flags |
| **Crossbar** | No routing timeout, no outstanding overflow, correct routing to destination, reset clear | chosen master granted, chosen slave served, multi-outstanding | $anyconst master/slave + latency counter + outstanding counter |
| **ECC** | Correct decode (no DED), SEC on single-bit error, DED on double-bit, no false error flags | clean decode, SEC, DED, single/double injected | $anyconst bit positions + golden data delay + error injection wires |
| **MemCtrl** | Read-after-write returns written value (DVI), no ack without req, write/read signal stability | read hit, write, RAW, fast ack, slow ack | $anyconst addr + ghost state (golden_data/valid) + wait timeout |

---

## Formal Abstraction Models

When a sub-component causes state-space explosion, replace it with a model from `abstractions/`.

```
abstractions/
  mem_abstract.v      Abstract memory: $anyconst addr + 1 shadow register; other addrs = $anyseq
  fifo_abstract.v     Abstract FIFO: exact count/full/empty; data = $anyseq
  counter_abstract.v  Abstract counter: $anyconst initial value; proves at any start state
  pipeline_abstract.v Abstract pipeline: $anyconst latency, 1-token model
  arith_abstract.v    Abstract arithmetic (MUL/DIV/MAC): $anyseq + algebraic constraints
  clkdiv_abstract.v   Abstract clock divider: divided clock → clk_en pulse
  README.md           When to use, soundness vs completeness, substitution patterns
```

### Soundness Rule

Abstract models are **over-approximations**: a failing property on the abstract model is a real bug; a passing property may need verification on the full model.

| Model | State reduction | What is preserved | What is abstracted |
|---|---|---|---|
| `mem_abstract` | N×DATA_W → DATA_W | Read-after-write for `$anyconst` addr | Other addresses (use `$anyseq`) |
| `fifo_abstract` | DEPTH×DATA_W → log2(DEPTH) | count, full, empty, almost flags | Individual data entries |
| `counter_abstract` | 2^WIDTH states → symbolic | Increment, overflow, reset behavior | Starting state (uses `$anyconst` init) |
| `pipeline_abstract` | N×DATA_W → DATA_W + log2(N) | Handshake, ordering, data for 1 token | Pipeline depth (uses `$anyconst` latency) |
| `arith_abstract` | full combinatorial | 0-operand, identity, valid timing | Non-corner-case outputs (use `$anyseq`) |
| `clkdiv_abstract` | continuous clock | Pulse period, ratio bounds | Clock waveform (replaces with `clk_en`) |

---

## Supported Patterns

| Pattern | Simulator | Formal |
|---|---|---|
| Handshake (valid/ready) | ✅ | ✅ |
| FIFO overflow/underflow | ✅ | ✅ |
| req/ack timeout | ✅ (`##[1:N]`) | ✅ (counter helper) |
| Mutual exclusion | ✅ | ✅ |
| One-hot encoding | ✅ | ✅ |
| AXI4 channel protocol | ✅ | ✅ |
| Data stability (`$stable`) | ✅ | ✅ |
| Minimum pulse width | ✅ | ✅ |
| Arbiter (fairness) | ✅ (generate) | ✅ (`$anyconst`) |
| FSM deadlock freedom | ✅ | ✅ (helper flag) |
| FSM livelock freedom | ✅ (`##[1:N]`) | ✅ (counter → safety) |
| FSM initial state | ✅ | ✅ |
| FSM state reachability | ✅ (generate) | ✅ (`$anyconst`) |
