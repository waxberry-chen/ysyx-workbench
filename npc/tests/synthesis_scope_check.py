#!/usr/bin/env python3
"""Check M5 S7 source closure and macro profiles; this is not a DC synthesis run."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "flow/build/s7-scope-check"
OUT.mkdir(parents=True, exist_ok=True)
FILELIST = "flow/00_indata/filelists/soc_cpu.f"
COMMON = ["verilator", "--sv", "--top-module", "ysyx_25030087", "-f", FILELIST]

# Exact file/signal waivers for unused data; disabled wrapper interfaces and
# intentionally open observation ports are separately enumerated below.
# Width/latch/missing-module warnings never receive a category-wide waiver.
WAIVERS = {
    ("ysyx_gen_imm.sv", "inst"): "Opcode inst[6:0] is decoded upstream",
    ("ysyx_core.sv", "if_ctx_fire"): "Assertion-only handshake observation",
    ("ysyx_core.sv", "op_rs1_idx"): "Assertion-only operand observation",
    ("ysyx_core.sv", "op_rs2_idx"): "Assertion-only operand observation",
    ("ysyx_core.sv", "exu_commit_pc"): "Assertion-only commit observation",
    ("ysyx_core.sv", "commit_mem_wdata"): "Assertion-only store observation",
    ("ysyx_exu.sv", "op_pred_taken"): "Assertion-only prediction observation",
    ("ysyx_gshare.sv", "query_pc"): "Index uses word PC low INDEX_BITS only",
    ("ysyx_lsu_axi4_adapter.sv", "local_request_aligned"): "Assertion-only alignment observation",
}


OBSERVATION_PORTS = set("commit_pc commit_inst commit_valid commit_is_mmio commit_exception commit_exception_cause commit_redirect_valid commit_redirect_reason commit_mem_valid commit_mem_write commit_mem_addr commit_mem_error monitor_bus".split())
INACTIVE_INPUTS = set("io_interrupt io_slave_awvalid io_slave_awaddr io_slave_awid io_slave_awlen io_slave_awsize io_slave_awburst io_slave_wvalid io_slave_wdata io_slave_wstrb io_slave_wlast io_slave_bready io_slave_arvalid io_slave_araddr io_slave_arid io_slave_arlen io_slave_arsize io_slave_arburst io_slave_rready".split())


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
if len(sources) != 22 or any(not p.startswith("./vsrc/") for p in sources):
    raise SystemExit("M5 source-only scope changed; review before updating the contract")
inputs = [FILELIST, "flow/00_indata/configs/npc_soc_cpu.tcl", "flow/00_indata/constraints/soc_cpu.sdc", *sources, "vsrc/gnrl/ysyx_global.sv", "tests/synthesis_scope_check.py"]
manifest = {"top": "ysyx_25030087", "tool": run(["verilator", "--version"]).stdout.strip(),
            "commands": [],
            "input_sha256": {p: sha(ROOT / p) for p in inputs}, "profiles": {}}
manifest["scope"] = {"description": "M5 CPU wrapper + core + AXI adapters/arbiter/router + CLINT; observation outputs unconnected",
                     "parameter_overrides": {}, "effective_parameters": {"PC_RST": "0x30000000", "IFQ_DEPTH": 2, "BPU_MODE": "per profile", "BPU_INDEX_BITS": 7},
                     "gpr_entries": 16, "m_arithmetic": "removed", "dc_checked": False}
base_profiles = {"synthesis": ["SYNTHESIS"],
            "synthesis_overrides_dpi": ["SYNTHESIS", "NPC_SIM_DPI", "DIFF"],
            "simulation_no_dpi": [], "simulation_dpi": ["NPC_SIM_DPI", "DIFF"]}
profiles = {f"{name}-bpu{mode}": [*defines, f"NPC_BPU_MODE={mode}"]
            for mode in range(3) for name, defines in base_profiles.items()}
for name, defines in profiles.items():
    mode = int(defines[-1].split("=")[1])
    defines = [*defines, "NPC_FLASH_BOOT"]
    flags = [f"-D{d}" for d in defines]
    preprocessed = run(COMMON + flags + ["-E"]).stdout
    (OUT / f"{name}.sv").write_text(preprocessed)
    # Strip comments before classifying constructs.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", preprocessed, flags=re.S)
    if not re.search(r"module ysyx_25030087\s*#\(\s*parameter PC_RST = 32'h30000000", code):
        raise SystemExit(f"{name}: Flash reset PC not selected")
    synthesis = "SYNTHESIS" in defines
    dpi = "NPC_SIM_DPI" in defines and not synthesis
    for callback in ("set_gpr_ptr", "set_csr_ptr"):
        if (callback in code) != dpi:
            raise SystemExit(f"{name}: wrong DPI visibility for {callback}")
    if synthesis and re.search(r'\b(initial|assert|property)\b|DPI-C', code):
        raise SystemExit(f"{name}: simulation construct leaked into implementation sources")
    if not synthesis and not re.search(r"\bassert\s+property\b", code):
        raise SystemExit(f"{name}: simulation assertions disappeared")
    lint_command = COMMON + flags + ["--lint-only", "--assert", "-Wall", "-Wno-fatal"]
    lint = run(lint_command)
    manifest["commands"].append(lint_command)
    (OUT / f"{name}.lint.log").write_text(lint.stdout + lint.stderr)
    waived = []
    for line in lint.stderr.splitlines():
        if not line.startswith("%Warning"):
            continue
        if (not synthesis and re.fullmatch(
                r"%Warning-SYNCASYNCNET: vsrc/top/ysyx_soc_cpu.sv:\d+:\d+: "
                r"Signal flopped as both synchronous and async: 'ysyx_25030087.__Vcellinp__subsystem__rst_n'", line)):
            waived.append({"diagnostic": line, "reason": "SVA samples the hardware asynchronous reset"})
            continue
        match = re.match(r"%Warning-PINCONNECTEMPTY: vsrc/top/ysyx_25030087.sv:\d+:\d+: .*?'([^']+)'", line)
        if match and match[1] in OBSERVATION_PORTS:
            waived.append({"diagnostic": line, "reason": "Actual SoC wrapper leaves this observation output unconnected"})
            continue
        match = re.match(r"%Warning-UNUSEDSIGNAL: (.*?):\d+:\d+: .*?'([^']+)'", line)
        key = (Path(match[1]).name, match[2]) if match else None
        if key and key[0] == "ysyx_25030087.sv" and key[1] in INACTIVE_INPUTS:
            waived.append({"diagnostic": line, "reason": "Disabled external IRQ/ChipLink input; no functional consumer"})
            continue
        if mode != 2 and key and key[0] == "ysyx_ifu.sv" and key[1] in (
                "bpu_train_valid", "bpu_train_index", "bpu_train_taken"):
            waived.append({"diagnostic": line, "reason": "OFF/JAL_ONLY generates no PHT; training input deliberately unused"})
            continue
        if key not in WAIVERS or (not synthesis and key not in (("ysyx_gen_imm.sv", "inst"), ("ysyx_gshare.sv", "query_pc"))):
            raise SystemExit(f"Unreviewed lint warning in {name}: {line}")
        waived.append({"diagnostic": line, "reason": WAIVERS[key]})
    manifest["profiles"][name] = {"defines": defines, "bpu_mode": mode, "waivers": waived, "result": "PASS",
                                   "preprocessed_sha256": sha(OUT / f"{name}.sv"),
                                   "lint_sha256": sha(OUT / f"{name}.lint.log")}
    print(f"{name}: PASS ({len(waived)} reviewed warnings)")
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Synthesis scope check: PASS; evidence: {OUT}")
