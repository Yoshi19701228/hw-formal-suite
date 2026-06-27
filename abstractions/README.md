# Formal Verification Abstraction Models

This directory contains Verilog-2001 "stub" modules that replace hard-to-converge
sub-components during formal verification.  They preserve the interface and key
behavioral properties of the original module while drastically reducing the
state space the solver must explore.

---

## When to Use Abstractions

Formal property checking explores all reachable states of a design.  The number
of states grows exponentially with the number of state bits (state-space
explosion).  Common offenders:

| Component         | State bits   | Reachable states |
|-------------------|-------------|-----------------|
| 32-bit counter    | 32          | ~4 billion       |
| 1 KB SRAM         | 8192        | 2^8192           |
| 16-deep FIFO      | 16 × DATA_W | astronomical     |
| 8-stage pipeline  | 8 × DATA_W  | very large       |

When a property proof does not converge (tool runs out of time or memory),
replace the problematic sub-component with the corresponding abstract model
from this directory.  The abstract model has far fewer state bits and converges
quickly while remaining sound for the property under test.

---

## Soundness vs. Completeness

Abstract models are **over-approximations**: they allow more behaviors than the
real component.

- If a property **passes** on the abstract model, it is *not* guaranteed to pass
  on the real design.  The abstract model may allow impossible behaviors that
  happen to satisfy the property vacuously.
- If a property **fails** on the abstract model, a real counterexample exists
  (or the abstraction is too coarse — refine it).

In practice: use abstract models to **find bugs fast** during the initial proof
campaign.  Once no counterexample is found, switch to the real model for the
final soundness proof (or prove the abstraction is a refinement of the
concrete model).

### The $anyconst / $anyseq Semantics

- **`$anyconst`**: the formal tool selects one fixed, arbitrary value for the
  entire proof.  Think of it as universal quantification over a free variable
  that does not change with time.  Useful for: symbolic initial states,
  "chosen address" in a memory, pipeline depth.
- **`$anyseq`**: the formal tool may choose a *different* value at every time
  step.  Think of it as existential quantification at each cycle.  Useful for:
  abstract data payloads that are irrelevant to the property under test.

Both are JasperGold / Questa Formal extensions.  Some tools (SymbiYosys) use
the `assume` keyword or `$any` instead; consult your tool's reference manual.

---

## Models

### `mem_abstract.v` — Abstract Memory

**Replaces**: SRAM / ROM arrays with deep address spaces.

**State bits**: `DATA_W + 1 + ADDR_W` (shadow register + valid flag + chosen
address) instead of `2^ADDR_W × DATA_W`.

**Preserved**:
- Read/write protocol (req / we / ack / rdata / wdata).
- Exact data value for one `$anyconst`-chosen address (`chosen_addr`).

**Abstracted away**:
- All other addresses return `$anyseq`; their values are unconstrained.

**Soundness**:
Properties that depend on a single address (e.g., "the value written to address
X is the value read back from address X") are exactly preserved.  Properties
that reason across multiple addresses simultaneously require a more detailed
model.

---

### `fifo_abstract.v` — Abstract FIFO

**Replaces**: synchronous FIFOs with large depth or wide data.

**State bits**: `log2(DEPTH)+1` (count register) instead of `DEPTH × DATA_W`.

**Preserved**:
- Occupancy count, `full`, `empty`, `almost_full`, `almost_empty`.
- Handshake: overflow and underflow are asserted as violations.
- `rdata` stability: output does not change unless a pop occurs.

**Abstracted away**:
- Per-entry data content (`rdata` is `$anyseq`).
- FIFO ordering (first-in / first-out is not enforced).

**Soundness**:
Valid for flow-control proofs (back-pressure, credit counters, buffer-full
avoidance).  Not valid for data-ordering proofs.

---

### `counter_abstract.v` — Abstract Wide Counter

**Replaces**: free-running counters wider than ~10 bits.

**State bits**: `WIDTH + 1` (count + initialized flag) but the formal tool
treats `init_val` as a free variable, so the effective search space is O(1)
per proof step rather than O(2^WIDTH).

**Preserved**:
- Increment-by-1 behavior when `en=1`, `clr=0`.
- Synchronous clear.
- Overflow detection at `count == all-ones`.

**Abstracted away**:
- The specific starting count; instead `$anyconst` makes the proof
  hold for any starting value simultaneously.

**Soundness**:
Invariants proven with this model hold for every reachable count value in the
real counter.

---

### `pipeline_abstract.v` — Abstract Pipeline

**Replaces**: multi-stage registered pipelines where depth causes explosion.

**State bits**: one shadow token (`DATA_W` bits) + age (`log2(MAX_DEPTH)` bits)
+ `latency` (`$anyconst`).

**Preserved**:
- Valid/ready handshake.
- Data integrity for one in-flight token.
- Latency behavior for any depth in `[1, MAX_DEPTH]` (proved simultaneously
  via `$anyconst`).
- Back-pressure: output token waits for `out_ready`.

**Abstracted away**:
- Multiple simultaneous in-flight tokens (throughput behavior).
- Per-stage intermediate values.

**Soundness**:
Valid for correctness proofs that reason about one token's journey through the
pipeline.  For throughput or ordering proofs (multiple tokens), use a larger
model or the real pipeline.

---

### `arith_abstract.v` — Abstract Arithmetic Unit

**Replaces**: multipliers, dividers, or MAC units with large internal state.

**State bits**: none beyond the 1-cycle registered path (`2 × DATA_W` for the
result register).

**Preserved**:
- 1-cycle latency (real latency is abstracted away; combine with
  `pipeline_abstract.v` if latency matters).
- Algebraic corner cases: 0-operand rules, identity rules.
- Valid/ready protocol.

**Abstracted away**:
- The arithmetic value for non-corner inputs (`$anyseq`).

**Soundness**:
Valid for proofs about protocol correctness and structural invariants.  Not
valid for proofs that require knowing the exact arithmetic result for arbitrary
inputs.  The corner-case constraints prevent vacuous proofs.

---

### `clkdiv_abstract.v` — Abstract Clock Divider

**Replaces**: clock-divider circuits that generate a second clock domain.

**State bits**: `log2(DIV_MAX)` (cycle counter) + 1 (phase toggle).

**Preserved**:
- A `clk_en` pulse fires exactly once every `period` source-clock cycles.
- `period` is `$anyconst` in `[DIV_MIN, DIV_MAX]`.
- `period` is stable after reset (ratio programmed once).

**Abstracted away**:
- The actual clock waveform (`clk_out`); most formal tools cannot use a
  derived register as a formal clock edge.

**Soundness**:
Downstream logic that uses `posedge clk` gated by `clk_en` behaves identically
to logic that uses `posedge clk_divided` at the same ratio.  All timing
properties (edge-to-edge skew, duty cycle) are abstracted away.

---

## Quick Substitution Pattern

There are two common ways to swap in an abstract model without modifying the
DUT source.

### Option A: Conditional instantiation (`ifdef`)

```verilog
// In the testbench or top-level wrapper:
`ifdef FORMAL_ABSTRACT
  mem_abstract #(.ADDR_W(20), .DATA_W(32)) u_mem (
    .clk    (clk),
    .rst_n  (rst_n),
    .req    (mem_req),
    .we     (mem_we),
    .addr   (mem_addr),
    .wdata  (mem_wdata),
    .rdata  (mem_rdata),
    .ack    (mem_ack)
  );
`else
  sram_1r1w #(.ADDR_W(20), .DATA_W(32)) u_mem (
    // ... real SRAM ports ...
  );
`endif
```

Compile with `-define FORMAL_ABSTRACT` in the formal flow and without it in
simulation.

### Option B: `bind` statement (SystemVerilog wrapper)

```systemverilog
// fv_bindings.sv — included only in the formal compile list
bind sram_1r1w mem_abstract #(
  .ADDR_W (ADDR_W),
  .DATA_W (DATA_W)
) u_mem_abs (
  .clk    (clk),
  .rst_n  (rst_n),
  .req    (req),
  .we     (we),
  .addr   (addr),
  .wdata  (wdata),
  .rdata  (rdata),
  .ack    (ack)
);
```

The `bind` approach requires no DUT modifications and is preferred for
production flows where the RTL is locked.

### Option C: Blackbox + abstract model

Some tools (JasperGold) support blackboxing a module and replacing it with a
model automatically:

```tcl
# In the JasperGold script:
formal compile -d top -f filelist.f \
  -blackbox sram_1r1w
formal compile -d top -f filelist.f \
  -f abstract_filelist.f    ;# includes mem_abstract.v with the same module name
```

Rename `mem_abstract` to `sram_1r1w` (or use `define_abstract`) for this
approach.

---

## Assertion Wrapper Template

Each abstract model exposes assertions guarded by `` `ifdef FORMAL ``.  A
typical assertion wrapper looks like this:

```systemverilog
// fv_fifo_check.sv
module fv_fifo_check;

  // Bind assumptions for the environment
  ENV_FIFO_NO_PUSH_FULL: assume property (
    @(posedge clk) disable iff (!rst_n)
    !(push && full)
  );

  ENV_FIFO_NO_POP_EMPTY: assume property (
    @(posedge clk) disable iff (!rst_n)
    !(pop && empty)
  );

  // The assertions inside fifo_abstract.v fire automatically
  // because FORMAL is defined during the formal compile step.

endmodule

bind fifo_abstract fv_fifo_check fv_check_inst ();
```

---

## Tool Compatibility Notes

| Feature        | JasperGold | Questa Formal | SymbiYosys |
|----------------|-----------|---------------|------------|
| `$anyconst`    | Yes        | Yes           | `$anyconst` (Yosys extension) |
| `$anyseq`      | Yes        | Yes           | `$anyseq`  |
| `(* anyconst *)` attribute | Yes | Yes | Yes (preferred) |
| `bind`         | Yes (SV)   | Yes (SV)      | Limited    |
| Multi-clock    | Limited    | Limited       | No         |

For SymbiYosys, replace `(* anyconst *) reg` with a plain `input` wire driven
by an unconstrained free variable in the `[cells]` section of the `.sby` file.
