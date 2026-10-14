#!/usr/bin/env python3
"""Verify SRAM configuration rejection independently of Xbar's parameter guard."""
import csv
import pathlib
import resource
import signal
import subprocess
import sys

npc = pathlib.Path(__file__).resolve().parents[1]
out = pathlib.Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
cases = [("minimum", 4, True), ("non_power_of_two", 12288, True),
         ("zero", 0, False), ("misaligned", 6, False),
         ("overlap", 0x2000004c, False), ("overflow", 0x80000004, False)]
rtl = [npc / "vsrc/bus/ysyx_axi4lite_slave_frontend.sv"]
rtl += [npc / f"vsrc/periph/ysyx_axi4lite_{name}.sv" for name in ("sram", "uart", "clint")]
rtl += [npc / "tests/axi4lite_slaves_test_top.sv", npc / "tests/axi4lite_slaves_config_tb.cpp"]
with (out / "results.csv").open("w") as f:
    writer = csv.writer(f)
    writer.writerow(["case", "SRAM_BYTES", "expected_valid", "exit_code", "result"])
    for name, capacity, valid in cases:
        mdir = out / name
        cmd = ["verilator", "--cc", "--exe", "--build", "--assert", "--sv", "-Wall",
               "-Wno-SYNCASYNCNET", "--top-module", "axi4lite_slaves_test_top",
               f"-GSRAM_BYTES=32'h{capacity:08x}", "--Mdir", str(mdir)] + [str(p) for p in rtl]
        with (out / f"{name}-build.log").open("w") as log:
            subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True)
        result = subprocess.run([str(mdir / "Vaxi4lite_slaves_test_top")],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (out / f"{name}-run.log").write_text(result.stdout)
        ok = (result.returncode == 0 if valid else result.returncode == -signal.SIGABRT
              and "invalid SRAM_BYTES" in result.stdout)
        writer.writerow([name, capacity, valid, result.returncode, "PASS" if ok else "FAIL"])
        f.flush()
        if not ok:
            raise RuntimeError(f"unexpected parameter result: {name}: {result.stdout}")
        print(f"config {name} SRAM_BYTES={capacity} expected_valid={valid} PASS", flush=True)
