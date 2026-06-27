#!/usr/bin/env python3
"""
hw-formal-suite/scripts/generate.py

Generate SystemVerilog assertions from YAML requirement files using Claude API.

Usage:
  python scripts/generate.py requirements/apb3_slave.yaml
  python scripts/generate.py requirements/*.yaml --parallel 4
  python scripts/generate.py requirements/axi4_master.yaml --output generated/ --verbose
"""

import argparse
import os
import re
import sys
import yaml
import anthropic
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

SUITE_ROOT = Path(__file__).parent.parent
INSTRUCTIONS_PATH = SUITE_ROOT / ".github" / "copilot-instructions.md"

# Output file block markers (model is instructed to use these)
FILE_PATTERN = re.compile(
    r'=== FILE: (.+?) ===\n(.*?)=== END FILE ===',
    re.DOTALL
)

# Fallback: fenced code block with filename comment
FENCE_PATTERN = re.compile(
    r'(?:^|\n)//\s*([\w/]+\.(?:sv|v|tcl))\s*\n```(?:systemverilog|verilog|tcl)?\n(.*?)```',
    re.DOTALL
)


def load_instructions() -> str:
    text = INSTRUCTIONS_PATH.read_text()
    # Append output format instruction for programmatic use
    text += """

---

## Programmatic Output Format (API mode)

When generating files, output EACH file using this exact format:

=== FILE: <filename> ===
<complete file content>
=== END FILE ===

Use the filename only (no directory prefix). Examples:
  apb3_assert_fml.sv
  apb3_formal_top.sv

**Single-file rule:** Helper logic (counters, flags, shift registers) must be defined
as internal registers and always blocks INSIDE the assertion module — NOT in a separate
*_helper.v file. One module = helper logic + assertions + cover + assume.

Always generate ALL required files for the requested environment:
- Formal: *_assert_fml.sv  (single module with helpers inside) + *_formal_top.sv (optional wrapper)
- Simulator: *_assert_sim.sv (single module with helpers inside)
"""
    return text


def build_prompt(req: dict) -> str:
    mode = req.get("mode", "formal")
    mode_label = "Formal Verification" if mode == "formal" else "Simulator"

    signals = req.get("signals", {})
    params  = req.get("parameters", {})
    reqs    = req.get("requirements", [])
    pkg     = req.get("package", "")
    dut     = req.get("dut_module", "unknown")
    wrapper = req.get("output", {}).get("wrapper", True)

    lines = [f"[{mode_label}]", ""]
    lines.append(f"DUT module: {dut}")

    if pkg:
        lines.append(f"Reference package: packages/{pkg}/")

    if signals:
        lines.append("\nSignals (assertion_port: dut_signal):")
        for k, v in signals.items():
            lines.append(f"  {k}: {v}")

    if params:
        lines.append("\nParameters:")
        for k, v in params.items():
            lines.append(f"  {k}: {v}")

    if reqs:
        lines.append("\nRequirements to verify:")
        for r in reqs:
            lines.append(f"  - {r}")

    if mode == "formal" and wrapper:
        lines.append("\nAlso generate the formal_top wrapper (formal_top.sv).")

    lines.append("\nIMPORTANT: All helper logic (counters, flags, shift registers) must be")
    lines.append("defined as internal variables inside the assertion module — do NOT generate")
    lines.append("a separate *_helper.v file.")

    lines.append("\nOutput every file using the === FILE / === END FILE === format.")

    return "\n".join(lines)


def parse_files(text: str) -> dict[str, str]:
    files = {}

    for m in FILE_PATTERN.finditer(text):
        name    = m.group(1).strip()
        content = m.group(2).strip()
        files[name] = content

    if not files:
        for m in FENCE_PATTERN.finditer(text):
            name    = m.group(1).strip()
            content = m.group(2).strip()
            files[name] = content

    return files


def generate_one(
    req_path: Path,
    instructions: str,
    client: anthropic.Anthropic,
    model: str,
    verbose: bool,
) -> tuple[Path, dict, dict[str, str], str | None]:
    try:
        req = yaml.safe_load(req_path.read_text())
        prompt = build_prompt(req)

        if verbose:
            print(f"  [{req_path.name}] → Claude API ({model})")

        message = client.messages.create(
            model=model,
            max_tokens=8192,
            system=instructions,
            messages=[{"role": "user", "content": prompt}],
        )

        raw = message.content[0].text
        files = parse_files(raw)

        if not files:
            debug = SUITE_ROOT / f".debug_{req_path.stem}.txt"
            debug.write_text(raw)
            if verbose:
                print(f"  [{req_path.name}] Warning: no file blocks found — raw response → {debug}")

        return req_path, req, files, None

    except Exception as exc:
        return req_path, {}, {}, str(exc)


def save_files(files: dict[str, str], out_dir: Path, verbose: bool) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        dest = out_dir / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content + "\n")
        if verbose:
            print(f"    Saved: {dest}")


def handle_result(
    req_path: Path,
    req: dict,
    files: dict[str, str],
    error: str | None,
    output_root: Path,
    verbose: bool,
) -> bool:
    if error:
        print(f"  ✗  {req_path.name}: {error}")
        return False

    dut = req.get("dut_module", req_path.stem)
    out_dir = output_root / dut

    if files:
        save_files(files, out_dir, verbose)
        print(f"  ✓  {req_path.name}  →  {out_dir}/  ({len(files)} files)")
        for f in files:
            print(f"       {f}")
    else:
        print(f"  △  {req_path.name}: response received but no file blocks detected")
        print(f"       Check .debug_{req_path.stem}.txt for the raw response")

    return bool(files)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate SVA assertion files from YAML requirements via Claude API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/generate.py requirements/apb3_slave.yaml
  python scripts/generate.py requirements/*.yaml --parallel 4
  python scripts/generate.py requirements/cache.yaml --output generated/ -v
        """,
    )
    parser.add_argument("requirements", nargs="+", metavar="REQ_FILE",
                        help="YAML requirement file(s)")
    parser.add_argument("--output", "-o", default="generated",
                        help="Root output directory (default: generated/)")
    parser.add_argument("--parallel", "-j", type=int, default=1,
                        help="Number of parallel Claude API calls (default: 1)")
    parser.add_argument("--model", default="claude-sonnet-4-6",
                        help="Claude model ID (default: claude-sonnet-4-6)")
    parser.add_argument("--api-key",
                        help="Anthropic API key (or set ANTHROPIC_API_KEY env var)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show detailed progress")
    args = parser.parse_args()

    # API key
    api_key = args.api_key or os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY not set.", file=sys.stderr)
        print("  export ANTHROPIC_API_KEY=sk-ant-...", file=sys.stderr)
        sys.exit(1)

    client       = anthropic.Anthropic(api_key=api_key)
    instructions = load_instructions()
    output_root  = Path(args.output)

    req_paths = [Path(p) for p in args.requirements]
    missing   = [p for p in req_paths if not p.exists()]
    if missing:
        for p in missing:
            print(f"Error: {p} not found", file=sys.stderr)
        sys.exit(1)

    print(f"hw-formal-suite generate — {len(req_paths)} file(s), model: {args.model}")
    print(f"Output root: {output_root}/")
    print()

    success = 0

    if args.parallel > 1 and len(req_paths) > 1:
        with ThreadPoolExecutor(max_workers=args.parallel) as pool:
            futures = {
                pool.submit(generate_one, p, instructions, client, args.model, args.verbose): p
                for p in req_paths
            }
            for fut in as_completed(futures):
                req_path, req, files, error = fut.result()
                if handle_result(req_path, req, files, error, output_root, args.verbose):
                    success += 1
    else:
        for req_path in req_paths:
            result = generate_one(req_path, instructions, client, args.model, args.verbose)
            if handle_result(*result, output_root, args.verbose):
                success += 1

    print()
    print(f"Completed: {success}/{len(req_paths)} succeeded")
    sys.exit(0 if success == len(req_paths) else 1)


if __name__ == "__main__":
    main()
