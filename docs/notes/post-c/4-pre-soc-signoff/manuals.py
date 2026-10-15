#!/usr/bin/env python3
"""Build and query local DC/PT text caches; PDF page numbers are one-based."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

GUIDE_DIR = Path(__file__).resolve().parents[3] / "userguide"
CACHE = GUIDE_DIR / ".cache"
GUIDES = {
    "dc": ("Design Compiler User Guide Version P-2019.03, March 2019.pdf", "P-2019.03"),
    "pt": ("PrimeTime_User_Guide_2016.pdf", "L-2016.06"),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    CACHE.mkdir(parents=True, exist_ok=True)
    version = subprocess.run(["pdftotext", "-v"], capture_output=True, text=True, check=True)
    manifest = {"generator": (version.stdout + version.stderr).strip(), "guides": {}}
    for key, (filename, edition) in GUIDES.items():
        source = GUIDE_DIR / filename
        target = CACHE / f"{key}-{edition}.txt"
        info = subprocess.check_output(["pdfinfo", str(source)], text=True)
        count = int(re.search(r"^Pages:\s+(\d+)", info, re.MULTILINE)[1])
        command = ["pdftotext", "-layout", "-enc", "UTF-8", str(source), str(target)]
        subprocess.run(command, check=True)
        text = target.read_text(encoding="utf-8")
        if text.count("\f") != count or not text.endswith("\f"):
            raise ValueError(f"{key}: PDF pages and form-feed boundaries disagree")
        manifest["guides"][key] = {
            "pdf": filename, "version": edition, "pdf_pages": count,
            "pdf_sha256": digest(source), "text": target.name,
            "text_sha256": digest(target), "form_feeds": text.count("\f"),
            "pdftotext_options": ["-layout", "-enc", "UTF-8"],
        }
        print(f"{key}: {count} pages, {count} form feeds -> {target}")
    (CACHE / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def pages(key):
    manifest = json.loads((CACHE / "manifest.json").read_text(encoding="utf-8"))
    entry = manifest["guides"][key]
    source, target = GUIDE_DIR / entry["pdf"], CACHE / entry["text"]
    if digest(source) != entry["pdf_sha256"] or digest(target) != entry["text_sha256"]:
        raise ValueError("PDF/cache changed; run manuals.py build before querying")
    result = target.read_text(encoding="utf-8").split("\f")
    if result[-1] != "" or len(result) - 1 != entry["pdf_pages"]:
        raise ValueError("Invalid page boundaries; rebuild cache")
    return result[:-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build", help="Run pdftotext -layout and record source/cache hashes")
    commands.add_parser("check", help="Validate both caches against the PDFs")
    search = commands.add_parser("search", help="Literal, case-insensitive text search")
    search.add_argument("guide", choices=GUIDES)
    search.add_argument("pattern")
    search.add_argument("--limit", type=int, default=20)
    search.add_argument("--from-page", type=int, default=1)
    page = commands.add_parser("page", help="Read a short range of PDF pages")
    page.add_argument("guide", choices=GUIDES)
    page.add_argument("number", type=int)
    page.add_argument("--count", type=int, default=1)
    args = parser.parse_args()
    if args.command == "build":
        build()
        return
    if args.command == "check":
        for key in GUIDES:
            print(f"{key}: verified {len(pages(key))} pages and PDF/cache SHA-256")
        return
    content = pages(args.guide)
    if args.command == "page":
        if args.number < 1 or args.count < 1 or args.number + args.count - 1 > len(content):
            parser.error("Page range is outside the PDF")
        for index in range(args.number - 1, args.number + args.count - 1):
            print(f"=== {args.guide}: PDF page {index + 1} ===\n{content[index]}")
    else:
        if not args.pattern or args.limit < 1 or not 1 <= args.from_page <= len(content):
            parser.error("Use a nonempty pattern, positive limit and valid starting page")
        matches = 0
        for number in range(args.from_page, len(content) + 1):
            # Split only on newlines: splitlines() would also consume form feeds.
            for line, text in enumerate(content[number - 1].split("\n"), 1):
                if args.pattern.casefold() in text.casefold():
                    print(f"{args.guide}:PDF {number}:line {line}: {text.strip()}")
                    matches += 1
                    if matches >= args.limit:
                        print("Match limit reached; narrow the query or increase --limit.")
                        return
        if not matches:
            print("No literal matches; try a shorter phrase or another spelling.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Manual cache error: {error}", file=sys.stderr)
        sys.exit(1)
