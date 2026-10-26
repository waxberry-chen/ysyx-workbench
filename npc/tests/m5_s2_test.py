#!/usr/bin/env python3
"""S2: actual SoC execution plus independent SoC guard protocol tests.

Invoke through `make -C npc s2-test` so Scala RTL and the simulator are rebuilt.
All generated programs, binaries, logs and waveforms stay in npc/build/m5-s2.
"""
import csv
import json
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NPC = ROOT / 'npc'
OUT = NPC / 'build/m5-s2'
EXE = NPC / 'build/ysyxsoc/VysyxSoCFull'
RESULTS = []


def run(name, args, negative=None):
    result = subprocess.run(list(map(str, args)), cwd=NPC, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=240)
    text = result.stdout.decode(errors='replace')
    (OUT / f'{name}.log').write_text(text)
    if negative:
        assert result.returncode != 0 and negative in text, (name, text[-3000:])
    else:
        assert result.returncode == 0, (name, result.returncode, text[-4000:])
    RESULTS.append(dict(name=name, status='PASS', negative=bool(negative)))
    print(f'{name}: PASS', flush=True)
    return text


def compile_image(name, source):
    elf = OUT / f'{name}.elf'
    image = OUT / f'{name}.bin'
    run(name+'-build', ['riscv64-linux-gnu-gcc', '-nostdlib', '-static',
        '-fno-pic', '-no-pie', '-march=rv32e_zicsr', '-mabi=ilp32e',
        '-Wl,-Ttext=0x20000000', '-Wl,--build-id=none', '-Wl,--no-relax',
        source, '-o', elf])
    run(name+'-objcopy', ['riscv64-linux-gnu-objcopy', '-O', 'binary', elf, image])
    assert 0 < image.stat().st_size <= 4096
    return image


def rows(name, suffix):
    with (OUT / f'{name}.{suffix}.csv').open() as f:
        return list(csv.reader(f))


def simulate(name, image):
    run(name, [EXE, '--mrom', image, '--max-cycles', 30000,
        '--summary', OUT/f'{name}.json', '--trace', OUT/f'{name}.fst',
        '--commit-trace', OUT/f'{name}.commit.csv',
        '--bus-trace', OUT/f'{name}.bus.csv',
        '--uart-events', OUT/f'{name}.uart.csv', '--uart-log', OUT/f'{name}.tx'])
    summary = json.loads((OUT/f'{name}.json').read_text())
    assert summary['pass'] and summary['cpu_release_ps'] == 305000, summary
    assert summary['first_ar_ps'] > summary['cpu_release_ps']
    assert summary['first_commit_ps'] > summary['first_ar_ps']
    assert summary['flash_dpi_calls'] == 0
    first = rows(name, 'commit')[0]
    assert int(first[1], 16) == 0x20000000
    assert int(first[2], 16) == int.from_bytes(image.read_bytes()[:4], 'little')
    return summary


def guard():
    directory = OUT/'guard'
    run('guard-build', ['verilator', '--cc', '--exe', '--build', '-j', 2,
        '--assert', '-Wall', '-Wno-fatal', '-Wno-SYNCASYNCNET',
        '-Werror-WIDTH', '-Werror-LATCH', '-Werror-UNOPTFLAT',
        '--top-module', 'npc_axi4_guard', '--Mdir', directory,
        ROOT/'ysyxSoC/perip/amba/npc_axi4_guard.v', NPC/'tests/soc/guard_tb.cpp'])
    text = run('guard', [directory/'Vnpc_axi4_guard'])
    assert 'completed=1351 reset_aborted=7 cases=38 random_seed=27 random=1000 downstream_errors=2 reset_recovery=7' in text


def smoke():
    for name in ('ebreak', 'uart', 'memory'):
        summary = simulate(name, compile_image(name, NPC/f'tests/soc/{name}.S'))
        assert summary['exceptions'] == 0
        if name == 'ebreak':
            assert summary['commits'] == summary['ar'] == summary['r'] == 1
            assert summary['aw'] == summary['w'] == summary['b'] == 0
        if name == 'uart':
            assert summary['uart_thr_writes'] == summary['uart_serial_bytes'] == 1
            assert (OUT/'uart.tx').read_bytes() == b'A'
            events = rows(name, 'uart')
            writes = [(int(r[2]), int(r[3])) for r in events if r[1] == '1']
            assert writes == [(3, 128), (0, 1), (1, 0), (3, 3), (2, 7), (7, 90), (0, 65)]
            assert any(r[1:] == ['0', '7', '90'] for r in events)
            assert any(r[1] == '0' and r[2] == '5' for r in events)
            # Every actual CPU device access preserves its byte address/size.
            accesses = [r for r in rows(name, 'commit') if int(r[4], 16) & 2]
            assert accesses and all(int(r[4], 16) & 8 for r in accesses)
            for r in rows(name, 'bus'):
                flags = int(r[1])
                if flags & 1 and 0x10000000 <= int(r[2], 16) < 0x10001000:
                    assert int(r[6], 16) == 0
                if flags & 2:
                    assert int(r[7], 16) == 0
        else:
            assert summary['uart_thr_writes'] == summary['uart_serial_bytes'] == 0


def faults():
    # Explicit oracle: expected response is data, not inferred from DUT routing.
    cases = []
    for addr in (0, 0x0f002000, 0x10003000, 0x20001000, 0x40000000, 0x80400000, 0xc0000000, 0xffffffff):
        for write in (False, True):
            cases.append((addr, write, 0, 3))
    for addr in (0x10002000, 0x10011000, 0x21000000, 0x31000000, 0xa0000000):
        for write in (False, True):
            cases.append((addr, write, 0, 2))
    cases += [(0x30000000, True, 2, 2), (0x20000000, True, 2, 2), (0x10000000, False, 2, 2),
              (0x10000000, True, 2, 2), (0x10001000, False, 0, 2),
              (0x10001000, True, 0, 2)]
    lines = ['.section .text', '.globl _start', '.option norvc', '_start:',
             'la t0,handler', 'csrw mtvec,t0', 'li a3,0',
             'li a1,0x0f000000', 'li t0,0x87654321', 'sw t0,0(a1)']
    expected = []
    for i, (addr, write, size, resp) in enumerate(cases):
        label = f'fault_{i}'
        lines += [f'li a1,0x{addr:08x}', f'la s0,{label}',
                  f'li s1,{7 if write else 5}', f'la a2,resume_{i}', f'{label}:',
                  f'{("sw" if size == 2 else "sb") if write else ("lw" if size == 2 else "lbu")} t0,0(a1)',
                  'j bad', f'resume_{i}:']
        expected.append(dict(label=label, cause=7 if write else 5, addr=addr, resp=resp, write=write))
    # Fetch fault goes through IFU; no CPU-side memory whitelist can satisfy it.
    lines += ['li s0,0x20001000', 'li s1,1', 'la a2,fetch_resume',
              'jr s0', 'j bad', 'fetch_resume:', f'li t0,{len(cases)+1}',
              'bne a3,t0,bad', 'li a1,0x0f000000', 'lw t0,0(a1)',
              'li t1,0x87654321', 'bne t0,t1,bad', 'li a0,0', 'ebreak',
              '.align 2', 'handler:', 'csrr t0,mcause', 'bne t0,s1,bad',
              'csrr t0,mepc', 'bne t0,s0,bad', 'addi a3,a3,1',
              'csrw mepc,a2', 'mret', 'bad:', 'li a0,1', 'ebreak']
    source = OUT/'faults.S'
    source.write_text('\n'.join(lines)+'\n')
    image = compile_image('faults', source)
    symbols = run('faults-symbols', ['riscv64-linux-gnu-nm', OUT/'faults.elf'])
    addresses = {p[2]: int(p[0], 16) for line in symbols.splitlines()
                 if len(p := line.split()) == 3}
    summary = simulate('faults', image)
    assert summary['exceptions'] == len(cases)+1
    assert not summary['uart_thr_writes'] and not rows('faults', 'uart')
    traps = [r for r in rows('faults', 'commit') if int(r[4], 16) & 1]
    assert [(int(r[1], 16), int(r[5], 16)) for r in traps] == [
        (addresses[e['label']], e['cause']) for e in expected] + [(0x20001000, 1)]
    for r, e in zip(traps, expected):
        assert int(r[6], 16) == e['addr']
        if e['addr'] == 0xa0000000:  # Future SDRAM must not be globally skipped.
            assert not int(r[4], 16) & 8
    read_addr = write_addr = None
    actual_errors = []
    for r in rows('faults', 'bus'):
        flags = int(r[1])
        if flags & 1:
            read_addr = int(r[2], 16)
        if flags & 2:
            write_addr = int(r[3], 16)
        if flags & 8 and int(r[9], 16):
            actual_errors.append((read_addr, False, int(r[9], 16)))
        if flags & 16 and int(r[10], 16):
            actual_errors.append((write_addr, True, int(r[10], 16)))
    assert actual_errors[:len(cases)] == [(a, w, r) for a, w, _, r in cases]
    # IFU can prefetch PC+4 before the first fetch error commits. That request
    # still receives DECERR, but redirect must discard it: only one cause=1 above.
    assert actual_errors[len(cases):] in (
        [(0x20001000, False, 3)],
        [(0x20001000, False, 3), (0x20001004, False, 3)])
    (OUT/'faults-expected.json').write_text(json.dumps(expected, indent=2)+'\n')


def negative():
    for name, data, diagnostic in [
        ('empty', b'', 'Empty/oversized image'),
        ('oversized', bytes(4097), 'Empty/oversized image'),
        ('timeout', bytes.fromhex('6f000000'), 'Simulation timeout'),
        ('bad-exit', bytes.fromhex('1305100073001000'), 'ebreak with nonzero a0'),
    ]:
        image = OUT/f'{name}.bin'
        image.write_bytes(data)
        run(name, [EXE, '--mrom', image, '--max-cycles', 1000], negative=diagnostic)
    run('missing-image', [EXE, '--mrom', OUT/'does-not-exist/image.bin'],
        negative='Cannot open image')


if __name__ == '__main__':
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    guard()
    smoke()
    faults()
    negative()
    (OUT/'results.json').write_text(json.dumps(RESULTS, indent=2)+'\n')
    print(f'S2: PASS; evidence: {OUT}')
