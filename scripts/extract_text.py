#!/usr/bin/env python3
"""
hw-formal-suite/scripts/extract_text.py

Extract text from PDF or Word documents and save as .txt.
No API key required — runs entirely with local Python libraries.

Usage:
  python scripts/extract_text.py spec.pdf
  python scripts/extract_text.py spec.docx
  python scripts/extract_text.py spec.pdf --output requirements/

After extraction, open the .txt file in VS Code and use Copilot Chat:
  #file:spec.txt  Generate formal assertions from this specification.
"""

import argparse
import sys
from pathlib import Path


def extract_pdf(path: Path) -> str:
    try:
        import pdfplumber
    except ImportError:
        sys.exit("Error: pdfplumber not installed. Run: pip install pdfplumber")

    pages = []
    with pdfplumber.open(path) as pdf:
        for i, page in enumerate(pdf.pages, 1):
            text = page.extract_text()
            if text:
                pages.append(f"[Page {i}]\n{text}")
    return "\n\n".join(pages)


def extract_docx(path: Path) -> str:
    try:
        from docx import Document
    except ImportError:
        sys.exit("Error: python-docx not installed. Run: pip install python-docx")

    doc = Document(path)
    lines = []
    for para in doc.paragraphs:
        if para.text.strip():
            lines.append(para.text)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Extract text from PDF or Word file")
    parser.add_argument("input", help="Input file (.pdf or .docx)")
    parser.add_argument("--output", "-o", help="Output directory (default: same as input)")
    args = parser.parse_args()

    src = Path(args.input)
    if not src.exists():
        sys.exit(f"Error: File not found: {src}")

    suffix = src.suffix.lower()
    if suffix == ".pdf":
        print(f"Extracting PDF: {src}")
        text = extract_pdf(src)
    elif suffix in (".docx", ".doc"):
        print(f"Extracting Word: {src}")
        text = extract_docx(src)
    else:
        sys.exit(f"Error: Unsupported format '{suffix}'. Use .pdf or .docx")

    out_dir = Path(args.output) if args.output else src.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / src.with_suffix(".txt").name
    out.write_text(text, encoding="utf-8")

    print(f"Saved: {out}")
    print()
    print("Next step — open Copilot Chat (Ctrl+Shift+I) and type:")
    print(f"  #file:{out.name}  Generate formal assertions from this specification.")


if __name__ == "__main__":
    main()
