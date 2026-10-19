#!/usr/bin/env python3
"""Audit the frozen M5 S0 CPU ABI and lint the generated SoC with an inert CPU.

This checks elaboration/connectivity only. The generated stub is NOT an NPC
implementation, and empty upstream device models do not become functional by
passing this check. Outputs stay in npc/build/m5-s0/contract-check.
"""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOC = ROOT / "ysyxSoC"
OUT = ROOT / "npc/build/m5-s0/contract-check"


def run(args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=True).stdout


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strip_comments(text):
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def declarations(header):
    ports = {}
    direction, width = None, 1
    for field in header.split(","):
        m = re.fullmatch(r"\s*(?:(input|output|inout)\s+)?(?:\[(\d+):0\]\s*)?(\w+)\s*", field)
        if not m:
            raise ValueError(f"Unsupported generated declaration: {field!r}")
        if m[1]:
            direction, width = m[1], int(m[2]) + 1 if m[2] else 1
        ports[m[3]] = (direction, width)
    return ports


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    generated = SOC / "build/ysyxSoCFull.v"
    code = strip_comments(generated.read_text())
    cpu = re.search(r"module CPU\((.*?)\);(.*?)endmodule", code, re.S)
    if not cpu:
        raise ValueError("Generated CPU module absent")
    signals = declarations(cpu[1])
    instance = re.search(r"ysyx_00000000\s+cpu\s*\((.*?)\);", cpu[2], re.S)
    connections = dict(re.findall(r"\.(\w+)\s*\((.*?)\)", instance[1]))

    # Independent ABI expectation: the upstream human-readable CPU spec.
    expected = {"clock": ("input", 1), "reset": ("input", 1), "io_interrupt": ("input", 1)}
    for line in (SOC / "spec/cpu-interface.md").read_text().splitlines():
        fields = [f.strip().replace("`", "") for f in line.strip("|").split("|")]
        if len(fields) != 6 or fields[0] not in ("input", "output"):
            continue
        for offset in (0, 3):
            direction, bits, name = fields[offset:offset + 3]
            expected[name] = (direction, int(bits[1:].split(":")[0]) + 1 if bits else 1)
    if set(expected) != set(connections):
        raise ValueError(f"CPU port name mismatch: {set(expected) ^ set(connections)}")

    rows = []
    for name, (direction, width) in expected.items():
        expr = connections[name].strip()
        if name.startswith("io_master_") or name in ("clock", "reset"):
            assert signals[expr] == (direction, width), (name, signals[expr], direction, width)
        elif direction == "input":
            assert re.fullmatch(fr"{width}'h0", expr), (name, expr)
        else:
            assert expr == "", (name, expr)
        rows.append([name, direction, width, expr or "unconnected output"])
    with (OUT / "cpu-ports.csv").open("w") as f:
        writer = csv.writer(f)
        writer.writerow(["name", "direction_at_cpu", "width", "generated_connection"])
        writer.writerows(rows)

    patch = SOC / "patch/rocket-chip.patch"
    delta = run(["git", "diff", "--no-ext-diff"], SOC / "rocket-chip")
    normalize = lambda s: "\n".join(l for l in s.splitlines() if not l.startswith("index "))
    assert normalize(delta) == normalize(patch.read_text()), "Unexpected Rocket Chip dirty diff"
    run(["git", "apply", "--reverse", "--check", "../patch/rocket-chip.patch"], SOC / "rocket-chip")

    # Stub outputs are constant: no instructions, AXI traffic or functional proof.
    stub = OUT / "cpu_abi_stub.sv"
    ports = [f"  {d} {'[' + str(w-1) + ':0] ' if w > 1 else ''}{n}"
             for n, (d, w) in expected.items()]
    assigns = [f"  assign {n} = '0;" for n, (d, _) in expected.items() if d == "output"]
    stub.write_text("module ysyx_00000000(\n" + ",\n".join(ports) + "\n);\n"
                    + "\n".join(assigns) + "\nendmodule\n")
    sources = [generated, stub, *sorted((SOC / "perip").rglob("*.v"))]
    args = ["verilator", "--lint-only", "--sv", "--timing", "--assert", "-Wall", "-Wno-fatal",
            "--top-module", "ysyxSoCFull", "--Mdir", str(OUT / "obj_dir"),
            f"-I{SOC / 'perip/uart16550/rtl'}", f"-I{SOC / 'perip/spi/rtl'}", *map(str, sources)]
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr
    (OUT / "lint.log").write_text(log)
    (OUT / "lint-command.json").write_text(json.dumps(args, indent=2) + "\n")
    # -Wno-fatal retains upstream lint diagnostics; interface mismatches still fail.
    abi_warnings = re.findall(r"^%Warning-(PINMISSING|PINNOTFOUND|WIDTH[^:]*):.*cpu_abi_stub.*$", log, re.M)
    manifest = {
        "scope": "S0 ABI/static elaboration; inert CPU; no functional simulation",
        "soc_commit": run(["git", "rev-parse", "HEAD"], SOC).strip(),
        "submodules": run(["git", "submodule", "status", "--recursive"], SOC).splitlines(),
        "rocket_patch_exact_match": True,
        "cpu_port_count": len(rows), "cpu_abi": "PASS",
        "verilator": run(["verilator", "--version"]).strip(),
        "lint_exit_code": result.returncode,
        "warnings": {k: len(re.findall(fr"^%Warning-{k}:", log, re.M))
                     for k in sorted(set(re.findall(r"^%Warning-([^:]+):", log, re.M)))},
        "abi_stub_warnings": abi_warnings,
        "input_sha256": {str(p.relative_to(ROOT)): sha(p) for p in sources + [patch, Path(__file__)]},
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({k: manifest[k] for k in ("cpu_port_count", "cpu_abi", "lint_exit_code", "warnings")}, indent=2))
    if result.returncode or abi_warnings:
        raise SystemExit(f"S0 elaboration failed; inspect {OUT / 'lint.log'}")
    print(f"S0 interface/elaboration check passed; evidence: {OUT}")


if __name__ == "__main__":
    main()
