#!/usr/bin/env python3
"""
hw-formal-suite/scripts/plan.py

Stage 1: Generate a Copilot Chat prompt for creating a verification plan
         from a spec text file. No API key required.

Stage 2: Generate a Copilot Chat prompt for implementing a verification
         plan YAML into SVA assertions. No API key required.

Usage:
  # Stage 1 — spec → plan prompt
  python scripts/plan.py spec requirements/apb3_spec.txt --dut apb3_slave

  # Stage 2 — plan → assertion prompt
  python scripts/plan.py assert requirements/apb3_vplan.yaml

Output is printed to stdout — copy it into Copilot Chat (Ctrl+Shift+I).
"""

import argparse
import sys
from pathlib import Path


STAGE1_TEMPLATE = """\
#file:{spec_file}

This is the specification for `{dut}`.

Please create a formal verification plan from this document.

Rules:
- 5–10 items total, one per major chapter or feature group
- Every item must list coverage_goals (at least 2 COV_ names per item)
- Choose method: scoreboard for data-value correctness (write→read match)
- Choose method: assertion for protocol sequencing and timing
- Choose method: cover-only for reachability of optional features
- Output in the === FILE: {dut}_vplan.yaml === ... === END FILE === block format
  as defined in the copilot-instructions.md

Output only the YAML block. No explanation needed.
"""

STAGE2_TEMPLATE = """\
#file:{plan_file}

This is the verification plan for `{dut}`.

Please implement ALL items in this plan as a single SystemVerilog module
`{dut}_assert_fml.sv` following the single-module format in copilot-instructions.md:

- Helper logic (counters, ghost registers) at the top inside the module
- Each VP item in its own comment section:
    // [VP-001] <title>  priority: critical
- method: assertion  → property + AST_ assert + all COV_ coverage goals
- method: scoreboard → ghost register + AST_ mismatch + COV_ points
- method: cover-only → COV_ only, no AST_
- ENV_ assume properties for reset and environment constraints at the bottom
- End with: bind {dut} {dut}_assert_fml #(...) u_fml (.*);

Output the complete file using:
=== FILE: {dut}_assert_fml.sv ===
...
=== END FILE ===
"""


def cmd_spec(args):
    src = Path(args.spec_file)
    if not src.exists():
        sys.exit(f"Error: File not found: {src}")
    if src.suffix not in (".txt", ".md"):
        sys.exit("Error: spec file must be .txt or .md (run extract_text.py first for PDF/Word)")

    dut = args.dut or src.stem
    prompt = STAGE1_TEMPLATE.format(spec_file=src.name, dut=dut)

    print("=" * 60)
    print("COPY THIS INTO COPILOT CHAT (Ctrl+Shift+I):")
    print("=" * 60)
    print(prompt)

    if args.output:
        out = Path(args.output) / f"{dut}_plan_prompt.txt"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(prompt)
        print(f"\nAlso saved to: {out}")


def cmd_assert(args):
    src = Path(args.plan_file)
    if not src.exists():
        sys.exit(f"Error: File not found: {src}")
    if src.suffix not in (".yaml", ".yml"):
        sys.exit("Error: plan file must be .yaml")

    import yaml
    data = yaml.safe_load(src.read_text())
    dut = data.get("dut", src.stem.replace("_vplan", ""))

    prompt = STAGE2_TEMPLATE.format(plan_file=src.name, dut=dut)

    print("=" * 60)
    print("COPY THIS INTO COPILOT CHAT (Ctrl+Shift+I):")
    print("=" * 60)
    print(prompt)

    if args.output:
        out = Path(args.output) / f"{dut}_assert_prompt.txt"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(prompt)
        print(f"\nAlso saved to: {out}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate Copilot Chat prompts for 2-stage verification plan workflow"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # Stage 1
    p1 = sub.add_parser("spec", help="Stage 1: spec .txt → verification plan prompt")
    p1.add_argument("spec_file", help="Spec text file (.txt or .md)")
    p1.add_argument("--dut", help="DUT module name (default: filename stem)")
    p1.add_argument("--output", "-o", help="Also save prompt to this directory")

    # Stage 2
    p2 = sub.add_parser("assert", help="Stage 2: vplan .yaml → assertion prompt")
    p2.add_argument("plan_file", help="Verification plan YAML (*_vplan.yaml)")
    p2.add_argument("--output", "-o", help="Also save prompt to this directory")

    args = parser.parse_args()
    if args.command == "spec":
        cmd_spec(args)
    else:
        cmd_assert(args)


if __name__ == "__main__":
    main()
