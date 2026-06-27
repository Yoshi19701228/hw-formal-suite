# Integration Guide

## Overview: helper vs. assertion

Every formal package consists of two files with distinct roles.

```
┌─────────────────────────────────────────────────────────┐
│  *_helper.v                                             │
│                                                         │
│  • Pure Verilog (tool-portable, no SVA)                 │
│  • Instantiated BESIDE the DUT in a wrapper             │
│  • Computes flags the DUT cannot expose:                │
│      - timeout counters  (replaces ##[1:N])             │
│      - ghost state       (golden_data, shadow_count…)   │
│      - $anyconst values  (chosen_addr, chosen_irq…)     │
│  • Outputs wires → fed into the assertion module        │
└────────────────────────┬────────────────────────────────┘
                         │ output wires
                         ▼
┌─────────────────────────────────────────────────────────┐
│  *_assert_fml.sv  (or *_assert_sim.sv)                  │
│                                                         │
│  • SystemVerilog with SVA                               │
│  • Attached to DUT via bind (or port connection)        │
│  • Reads DUT signals + helper outputs                   │
│  • Contains: assert (safety) / cover / assume           │
└─────────────────────────────────────────────────────────┘
```

---

## Simulator — 2 steps

Only `*_assert_sim.sv` is needed. No helper required.

**Step 1** — Add the file to your compile list:
```
vlog packages/apb3/apb3_assert_sim.sv
```

**Step 2** — Bind to the DUT (in testbench or separate file):
```systemverilog
// tb_top.sv  or  bind_apb3.sv
bind apb3_slave apb3_assert_sim #(
  .ADDR_W(32), .DATA_W(32), .MAX_WAIT(16)
) u_chk (
  .clk     (PCLK),
  .rst_n   (PRESETn),
  .psel    (PSEL),
  .penable (PENABLE),
  .pwrite  (PWRITE),
  .paddr   (PADDR),
  .pwdata  (PWDATA),
  .pready  (PREADY),
  .prdata  (PRDATA),
  .pslverr (PSLVERR),
  // helper outputs — not needed for sim; tie to 0
  .cnt_pready_wait ('0),
  .pready_timeout  (1'b0)
);
```

> **Tip:** If the signal names inside the DUT match the port names exactly, use `.*` to connect all at once:
> ```systemverilog
> bind apb3_slave apb3_assert_sim #(.ADDR_W(32),.DATA_W(32)) u_chk (.*);
> ```

---

## Formal — 3 steps

Helper and assertion are both required.

### Step 1 — Create a formal wrapper (top-level file for the tool)

```
formal_top/
  apb3_formal_top.sv   ← you write this (one per DUT)
```

```systemverilog
// apb3_formal_top.sv
module apb3_formal_top;

  // ── Clocks & resets (formal tool drives these) ──────────────
  logic clk, rst_n;

  // ── DUT signals ─────────────────────────────────────────────
  logic        psel, penable, pwrite, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;

  // ── DUT instantiation ───────────────────────────────────────
  apb3_slave u_dut (
    .PCLK    (clk),
    .PRESETn (rst_n),
    .PSEL    (psel),
    .PENABLE (penable),
    .PWRITE  (pwrite),
    .PADDR   (paddr),
    .PWDATA  (pwdata),
    .PREADY  (pready),
    .PRDATA  (prdata),
    .PSLVERR (pslverr)
  );

  // ── Step 2: Helper (beside DUT, not inside) ─────────────────
  logic [$clog2(17)-1:0] cnt_pready_wait;
  logic                   pready_timeout;

  apb3_helper #(.DATA_W(32), .MAX_WAIT(16)) u_hlp (
    .clk            (clk),
    .rst_n          (rst_n),
    .psel           (psel),
    .penable        (penable),
    .pready         (pready),
    .cnt_pready_wait(cnt_pready_wait),
    .pready_timeout (pready_timeout)
  );

  // ── Step 3: Assertion module (bind or direct instantiation) ──
  apb3_assert_fml #(.ADDR_W(32), .DATA_W(32)) u_fml (
    .clk            (clk),
    .rst_n          (rst_n),
    .psel           (psel),
    .penable        (penable),
    .pwrite         (pwrite),
    .paddr          (paddr),
    .pwdata         (pwdata),
    .pready         (pready),
    .prdata         (prdata),
    .pslverr        (pslverr),
    .cnt_pready_wait(cnt_pready_wait),   // ← from helper
    .pready_timeout (pready_timeout)     // ← from helper
  );

endmodule
```

### Step 2 — Compile order

```bash
# Compile in this order: pkg → helper → assertion → DUT → wrapper
vlog packages/apb3/apb3_pkg.sv
vlog packages/apb3/apb3_helper.v
vlog packages/apb3/apb3_assert_fml.sv
vlog rtl/apb3_slave.sv
vlog formal_top/apb3_formal_top.sv
```

### Step 3 — Tool invocation

**JasperGold:**
```tcl
analyze -sv09 packages/apb3/apb3_pkg.sv
analyze -v    packages/apb3/apb3_helper.v
analyze -sv09 packages/apb3/apb3_assert_fml.sv
analyze -sv09 rtl/apb3_slave.sv
analyze -sv09 formal_top/apb3_formal_top.sv

elaborate -top apb3_formal_top
clock clk
reset ~rst_n
prove -all
```

**SymbiYosys:**
```
[options]
mode prove

[files]
packages/apb3/apb3_pkg.sv
packages/apb3/apb3_helper.v
packages/apb3/apb3_assert_fml.sv
rtl/apb3_slave.sv
formal_top/apb3_formal_top.sv

[engines]
smtbmc

[script]
read -formal packages/apb3/apb3_pkg.sv
...
prep -top apb3_formal_top
```

---

## Bind vs. Direct Instantiation

| | `bind` statement | Direct instantiation in wrapper |
|---|---|---|
| DUT unchanged | ✅ Yes | ✅ Yes (wrapper is separate) |
| Where to write | Any file compiled after DUT | Inside `formal_top.sv` |
| Helper wires | Need to be in DUT's scope or wrapper | Easy — wires live in wrapper |
| **Recommendation** | Simulator (no helper needed) | **Formal (helper + assertion)** |

### bind with helper (advanced)

If you want to use `bind` for both helper and assertion:

```systemverilog
// Bind helper first — it becomes a sub-instance of apb3_slave
bind apb3_slave apb3_helper #(.DATA_W(32)) u_hlp (
  .clk            (PCLK),
  .rst_n          (PRESETn),
  .psel           (PSEL),
  .penable        (PENABLE),
  .pready         (PREADY),
  .cnt_pready_wait(/* internal wire — inaccessible from here */),
  .pready_timeout (/* same problem */)
);
// ⚠️  Problem: helper outputs cannot be referenced by the assertion bind below
//     Use the wrapper pattern instead for formal.
```

> Helper outputs are internal wires that live in the helper instance.  
> The assertion module needs them as inputs.  
> **Wrapper pattern solves this cleanly** — both are instantiated in the same scope.

---

## Minimal Template for Any Package

Copy and fill in:

```systemverilog
// formal_top/<your_dut>_formal_top.sv
module <your_dut>_formal_top;

  logic clk, rst_n;

  // --- DUT signals (add yours here) ---
  // logic sig_a, sig_b;
  // logic [7:0] data;

  // --- DUT ---
  <your_dut> u_dut (.clk(clk), .rst_n(rst_n), /* ... */);

  // --- Helper outputs ---
  // (copy from *_helper.v port list)

  // --- Helper ---
  <pkg>_helper #(/* params */) u_hlp (
    .clk(clk), .rst_n(rst_n),
    /* DUT signals */,
    /* helper output wires */
  );

  // --- Assertions ---
  <pkg>_assert_fml #(/* params */) u_fml (
    .clk(clk), .rst_n(rst_n),
    /* DUT signals */,
    /* helper output wires */   // ← same wires as above
  );

endmodule
```

---

## Copilot Integration Tip

Tell Copilot Chat:

```
Generate the formal_top wrapper for [DUT name].
DUT module: <your_dut>, signals: <list>.
Package: packages/apb3/
```

Copilot will fill in the template using the package's port list.
