#!/usr/bin/env python3
"""Check M4 source closure and macro profiles; this is not a DC synthesis run."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/m4-s1/scope"
OUT.mkdir(parents=True, exist_ok=True)
FILELIST = "flow/filelists/core.f"
COMMON = ["verilator", "--sv", "--top-module", "ysyx_core_axi4lite", "-f", FILELIST]

# Exact file/signal waivers. All are unused data, not control/width/latch warnings.
# Opcode bits do not form an immediate; the others serve simulation assertions.
WAIVERS = {
    ("ysyx_gen_imm.sv", "inst"): "Opcode inst[6:0] is decoded upstream",
    ("ysyx_core.sv", "if_ctx_fire"): "Assertion-only handshake observation",
    ("ysyx_core.sv", "op_rs1_idx"): "Assertion-only operand observation",
    ("ysyx_core.sv", "op_rs2_idx"): "Assertion-only operand observation",
    ("ysyx_core.sv", "exu_commit_pc"): "Assertion-only commit observation",
    ("ysyx_core.sv", "commit_mem_wdata"): "Assertion-only store observation",
    ("ysyx_exu.sv", "op_pred_taken"): "Assertion-only prediction observation",
    ("ysyx_exu.sv", "op_pred_npc"): "Assertion-only prediction observation",
    ("ysyx_lsu_axi4lite_adapter.sv", "local_request_aligned"): "Assertion-only alignment observation",
}


def run(args):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(f"Command failed ({result.returncode}): {args}\n{result.stdout}{result.stderr}")
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


sources = [line.strip() for line in (ROOT / FILELIST).read_text().splitlines()
           if line.strip() and not line.lstrip().startswith("#")]
if len(sources) != len(set(sources)):
    raise SystemExit("Duplicate source in synthesis filelist")
inputs = [FILELIST, *sources, "vsrc/gnrl/ysyx_global.sv", "tests/synthesis_scope_check.py"]
manifest = {"top": "ysyx_core_axi4lite", "tool": run(["verilator", "--version"]).stdout.strip(),
            "input_sha256": {p: sha(ROOT / p) for p in inputs}, "profiles": {}}
manifest["scope"] = {"description": "Core + adapters + Arbiter, observation ports retained",
                     "parameter_overrides": {}, "core_defaults": {"PC_RST": "0x80000000", "IFQ_DEPTH": 2},
                     "gpr_entries": 32, "m_arithmetic": "retained", "dc_checked": False}
profiles = {"synthesis": ["SYNTHESIS"],
            "synthesis_overrides_dpi": ["SYNTHESIS", "NPC_SIM_DPI", "DIFF"],
            "simulation_no_dpi": [], "simulation_dpi": ["NPC_SIM_DPI", "DIFF"]}
for name, defines in profiles.items():
    flags = [f"-D{d}" for d in defines]
    preprocessed = run(COMMON + flags + ["-E"]).stdout
    (OUT / f"{name}.sv").write_text(preprocessed)
    # Strip comments before classifying constructs.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", preprocessed, flags=re.S)
    synthesis = "SYNTHESIS" in defines
    dpi = "NPC_SIM_DPI" in defines and not synthesis
    for callback in ("set_gpr_ptr", "set_csr_ptr"):
        if (callback in code) != dpi:
            raise SystemExit(f"{name}: wrong DPI visibility for {callback}")
    if synthesis and re.search(r'\b(initial|assert|property)\b|DPI-C', code):
        raise SystemExit(f"{name}: simulation construct leaked into implementation sources")
    if not synthesis and not re.search(r"\bassert\s+property\b", code):
        raise SystemExit(f"{name}: simulation assertions disappeared")
    lint = run(COMMON + flags + ["--lint-only", "--assert", "-Wall", "-Wno-fatal"])
    (OUT / f"{name}.lint.log").write_text(lint.stdout + lint.stderr)
    waived = []
    for line in lint.stderr.splitlines():
        if not line.startswith("%Warning"):
            continue
        if (not synthesis and re.fullmatch(
                r"%Warning-SYNCASYNCNET: vsrc/top/ysyx_core_axi4lite.sv:\d+:\d+: "
                r"Signal flopped as both synchronous and async: 'rst_n'", line)):
            waived.append({"diagnostic": line, "reason": "SVA samples the hardware asynchronous reset"})
            continue
        match = re.match(r"%Warning-UNUSEDSIGNAL: (.*?):\d+:\d+: .*?'([^']+)'", line)
        key = (Path(match[1]).name, match[2]) if match else None
        if key not in WAIVERS or (not synthesis and key != ("ysyx_gen_imm.sv", "inst")):
            raise SystemExit(f"Unreviewed lint warning in {name}: {line}")
        waived.append({"diagnostic": line, "reason": WAIVERS[key]})
    manifest["profiles"][name] = {"defines": defines, "waivers": waived, "result": "PASS"}
    print(f"{name}: PASS ({len(waived)} reviewed warnings)")
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Synthesis scope check: PASS; evidence: {OUT}")
