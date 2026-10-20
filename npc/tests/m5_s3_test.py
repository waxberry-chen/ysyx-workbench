#!/usr/bin/env python3
"""AM + real SRAM + per-commit DiffTest. Run with make -C npc s3-test.

Build all CPU test images for capacity accounting; run a fixed S3 subset.
Negative tests must fail for the intended reason. Generated evidence stays in
npc/build/m5-s3; no modification of NEMU .config or SRAM image preloading.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NPC = ROOT / "npc"
OUT = NPC / "build/m5-s3"
EXE = NPC / "build/ysyxsoc/VysyxSoCFull"
REF = ROOT / "nemu/build/ysyxsoc/nemu-ref.so"
FIX = NPC / "tests/soc-runtime"
CPU = ROOT / "am-kernels/tests/cpu-tests"
BENCH = ROOT / "am-kernels/benchmarks/microbench"
RESULTS, IMAGES, CPU_MATRIX = [], {}, []
SELECTED = set("""dummy add add-longlong sub-longlong mul-longlong bit shift
mov-c movsx load-store max min3 if-else switch sum fib recursion
bubble-sort select-sort quick-sort string to-lower-case leap-year div""".split())


def run(name, args, cwd=NPC, expected=None, allow_fail=False):
    result = subprocess.run(list(map(str, args)), cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=240)
    text = result.stdout.decode(errors="replace")
    (OUT / f"{name}.log").write_text(text)
    if expected:
        assert result.returncode != 0 and expected in text, (name, text[-3000:])
    elif not allow_fail:
        assert result.returncode == 0, (name, result.returncode, text[-4000:])
    if not allow_fail or result.returncode == 0:
        RESULTS.append(dict(name=name, status="PASS", negative=bool(expected)))
    return result.returncode, text


def symbols(elf):
    text = subprocess.check_output(["riscv64-linux-gnu-nm", str(elf)], text=True)
    return {p[2]: int(p[0], 16) for line in text.splitlines()
            if len(p := line.split()) == 3}


def build(name, sources, defines="", allow_capacity=False):
    folder = OUT / "programs" / name
    folder.mkdir(parents=True, exist_ok=True)
    links = []
    for i, source in enumerate(sources):
        link = folder / f"source{i}{source.suffix}"
        if not link.exists():
            link.symlink_to(source)
        assert link.resolve() == source.resolve()
        links.append(link.name)
    (folder / "Makefile").write_text(
        f"NAME = {name}\nSRCS = {' '.join(links)}\n"
        f"INC_PATH += {CPU / 'include'} {BENCH / 'include'}\n"
        f"CFLAGS += {defines}\ninclude {ROOT / 'abstract-machine/Makefile'}\n")
    rc, text = run(name+"-build", ["make", "ARCH=riscv32e-ysyxsoc", "insert-arg"],
                   cwd=folder, allow_fail=allow_capacity)
    if rc:
        assert allow_capacity and any(s in text for s in
            ["MROM image exceeds", "SRAM data/bss overlaps", "will not fit in region"]), text[-4000:]
        return None
    base = folder / "build" / f"{name}-riscv32e-ysyxsoc"
    image, elf = base.with_suffix(".bin"), base.with_suffix(".elf")
    syms = symbols(elf)
    assert 0 < image.stat().st_size <= 4096
    assert syms["_heap_start"] <= syms["_heap_end"] == 0x0f001800
    assert syms["_stack_top"] == 0x0f002000
    assert syms["_data_load"] >= 0x20000000
    assert syms["_data_start"] == 0x0f000000
    IMAGES[name] = dict(binary_bytes=image.stat().st_size,
        sha256=hashlib.sha256(image.read_bytes()).hexdigest(),
        data_bytes=syms["_data_end"]-syms["_data_start"],
        bss_bytes=syms["_bss_end"]-syms["_bss_start"],
        heap_bytes=syms["_heap_end"]-syms["_heap_start"],
        stack_reserved=2048, symbols=syms)
    return image


def simulate(name, image, trace=False, expected_uart=None):
    args = [EXE, "--mrom", image, "--diff", REF, "--max-cycles", 20000000,
            "--summary", OUT/f"{name}.json", "--uart-log", OUT/f"{name}.tx"]
    if trace:
        args += ["--commit-trace", OUT/f"{name}.commit.csv",
                 "--bus-trace", OUT/f"{name}.bus.csv"]
    run(name, args)
    summary = json.loads((OUT/f"{name}.json").read_text())
    assert summary["pass"] and summary["diff_steps"] == summary["commits"]
    assert summary["diff_sram_checks"] == 1 and summary["flash_dpi_calls"] == 0
    if name in IMAGES:
        assert summary["min_sram_sp"] >= IMAGES[name]["symbols"]["_stack_bottom"]
        IMAGES[name]["stack_used"] = 0x0f002000-summary["min_sram_sp"]
    if expected_uart is not None:
        assert (OUT/f"{name}.tx").read_bytes() == expected_uart
    print(f"{name}: PASS ({summary['commits']} commits)", flush=True)
    return summary


def rows(name, kind):
    with (OUT/f"{name}.{kind}.csv").open() as f:
        return list(csv.reader(f))


def startup_evidence():
    # Check the first 2048 accepted AW/W pairs really poison every SRAM word,
    # then account for the data copy and bss clear by their instruction PCs.
    writes, addr, data = [], None, None
    for row in rows("memory", "bus"):
        flags = int(row[1])
        if flags & 2:
            addr = int(row[3], 16)
            if len(writes)<2048:
                assert int(row[7], 16) == 2
        if flags & 4:
            data = int(row[4], 16)
            strobe = int(row[8], 16)
        if flags & 16:
            writes.append((addr, data, strobe, int(row[10], 16)))
    assert writes[:2048] == [(0x0f000000+4*i, 0xa5a5a5a5, 15, 0) for i in range(2048)]
    sym = IMAGES["memory"]["symbols"]
    commits = rows("memory", "commit")
    stores = [r for r in commits if int(r[4], 16) & 6 == 6]
    copy = [r for r in stores if sym["__am_data_copy"] <= int(r[1], 16) < sym["__am_bss_clear"]]
    zero = [r for r in stores if sym["__am_bss_clear"] <= int(r[1], 16) < sym["__am_runtime_ready"]]
    assert [int(r[6],16) for r in copy] == list(range(sym["_data_start"],sym["_data_end"],4))
    assert [int(r[6],16) for r in zero] == list(range(sym["_bss_start"],sym["_bss_end"],4))
    (OUT/"startup.json").write_text(json.dumps(dict(
        poison_words=2048, pattern="a5a5a5a5", data_words=len(copy), bss_words=len(zero),
        cpu_stores=True, harness_sram_preload=False), indent=2)+"\n")


def negatives(hello, memory):
    # Commit 5 is addi t0,t0,-12, completing the SRAM base address.
    # Flip its destination x5 only in the comparator snapshot.
    run("diff-negative", [EXE, "--mrom", hello, "--diff", REF, "--diff-inject-at", 5],
        expected="DiffTest mismatch GPR[5]")
    sym=IMAGES["memory"]["symbols"]
    for name, start, end in [
        ("missing-data-copy","__am_data_copy","__am_bss_clear"),
        ("missing-bss-clear","__am_bss_clear","__am_runtime_ready"),
    ]:
        data=bytearray(memory.read_bytes())
        count=0
        for pc in range(sym[start],sym[end],4):
            offset=pc-0x20000000
            ins=int.from_bytes(data[offset:offset+4],"little")
            if ins&127 == 0x23:
                data[offset:offset+4]=(0x13).to_bytes(4,"little")  # replace store with NOP
                count+=1
        assert count==1
        image=OUT/f"{name}.bin"; image.write_bytes(data)
        run(name,[EXE,"--mrom",image,"--diff",REF],expected="ebreak with nonzero a0")
    for name, section, size, message in [
        ("rom-overflow", ".rodata", 4096, "MROM image exceeds"),
        ("ram-overflow", ".bss", 8192, "SRAM data/bss overlaps"),
    ]:
        src=OUT/f"{name}.S"
        src.write_text(f".section {section}\n.globl main\nmain:\n.space {size}\n")
        folder=OUT/"programs"/name
        assert build(name,[src],allow_capacity=True) is None
        assert message in (OUT/f"{name}-build.log").read_text()
        RESULTS.append(dict(name=name,status="PASS",negative=True))


def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    OUT.mkdir(parents=True,exist_ok=True)
    config = ROOT/"nemu/.config"
    original = config.read_bytes()
    hello=build("hello",[FIX/"hello.c"])
    simulate("hello",hello,expected_uart=b"Hello, ysyxSoC!\n")
    memory=build("memory",[FIX/"memory.c"])
    simulate("memory",memory,True,b"M\n")
    startup_evidence()
    s=simulate("traps",build("traps",[FIX/"traps.S"]),True,b"")
    assert s["exceptions"]==8
    sym=IMAGES["traps"]["symbols"]
    traps=[(int(r[1],16),int(r[5],16)) for r in rows("traps","commit") if int(r[4],16)&1]
    assert traps==[(sym[k],v) for k,v in
        [("mis_lh",4),("mis_lw",4),("mis_sh",6),("mis_sw",6),
         ("oob_load",5),("oob_store",7),("rom_store",7),("do_ecall",11)]]
    s=simulate("timer",build("timer",[FIX/"timer.c"]),True,b"")
    commits=rows("timer","commit")
    assert sum(int(r[6],16) in (0x0200bff8,0x0200bffc) and bool(int(r[4],16)&2) for r in commits)==6
    for bench in ("sieve","fib"):
        image=build("micro-"+bench,[FIX/"microbench.c",BENCH/f"src/{bench}/{bench}.c"],
                    "-DSMOKE_FIB" if bench=="fib" else "")
        simulate("micro-"+bench,image,expected_uart=b"")
    for source in sorted((CPU/"tests").glob("*.c")):
        name=source.stem
        image=build("cpu-"+name,[source],allow_capacity=True)
        if image is None:
            status,reason="EXCLUDED","4 KiB MROM / 8 KiB SRAM linker capacity"
        elif name in SELECTED:
            simulate("cpu-"+name,image)
            status,reason="PASS","fixed S3 subset"
        else:
            status,reason="NOT_RUN","outside fixed S3 workload subset; defer to S4/S6"
        CPU_MATRIX.append(dict(name=name,status=status,reason=reason))
    # Keep the S2 endpoint/lane fixture and add differential + whole-SRAM checks.
    from m5_s2_test import compile_image
    import m5_s2_test
    m5_s2_test.OUT=OUT
    simulate("endpoints",compile_image("endpoints",NPC/"tests/soc/memory.S"))
    negatives(hello,memory)
    assert config.read_bytes()==original
    (OUT/"images.json").write_text(json.dumps(IMAGES,indent=2)+"\n")
    (OUT/"cpu-tests.json").write_text(json.dumps(CPU_MATRIX,indent=2)+"\n")
    (OUT/"results.json").write_text(json.dumps(RESULTS,indent=2)+"\n")
    print(f"S3: PASS; evidence: {OUT}")


if __name__=="__main__":
    main()
