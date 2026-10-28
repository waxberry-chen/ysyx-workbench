#!/usr/bin/env python3
"""S6 system acceptance; focused groups keep slow serial boot runs reviewable.

All images boot through actual MROM/Flash. The --only groups produce separate
manifests; none silently promote a partial run to complete S6 acceptance.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import resource
import subprocess
import time
import m5_s4_test as soc

ROOT, NPC = soc.ROOT, soc.NPC
OUT = NPC / 'build/m5-s6'
FIX = NPC / 'tests/soc-system'
COMMANDS, WORKLOADS = [], {}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(name, args, cwd=NPC, expected=None):
    args = list(map(str, args))
    print(f'{name}: running', flush=True)
    start = time.monotonic()
    record = dict(name=name, command=args, cwd=str(cwd), expected_failure=expected)
    if Path(args[0]).is_file():
        record['executable_sha256'] = digest(args[0])
    record['input_sha256'] = {str(path):digest(path) for value in args
                             if Path(value).suffix in ('.elf','.bin','.so')
                             and (path := Path(value) if Path(value).is_absolute() else cwd/Path(value)).is_file()}
    COMMANDS.append(record)
    with (OUT / f'{name}.log').open('w') as log:
        try:
            p = subprocess.run(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        except subprocess.TimeoutExpired:
            record.update(status='TIMEOUT', wall_seconds=time.monotonic()-start)
            raise
    text = (OUT / f'{name}.log').read_text(errors='replace')
    ok = p.returncode != 0 and expected in text if expected else p.returncode == 0
    record.update(status='PASS' if ok else 'FAIL', returncode=p.returncode,
                  wall_seconds=round(time.monotonic()-start, 3))
    assert ok, (name, p.returncode, text[-4000:])
    return text


def simulate(name, image, boot='mrom', delay=None, uart=None, extra=(), cycles=20000000, expected=None):
    folder = 'ysyxsoc' + ('-flash' if boot != 'mrom' else '') + ('-delay' if delay else '')
    exe = NPC / 'build' / folder / 'VysyxSoCFull'
    args = [exe, '--mrom' if boot == 'mrom' else '--flash', image, '--diff', soc.REF,
            '--max-cycles', cycles, '--summary', OUT/f'{name}.json', '--uart-log', OUT/f'{name}.tx']
    if delay:
        seed, maximum, fixed = delay
        args += [f'+npc_delay_seed={seed}', f'+npc_delay_max={maximum}', f'+npc_delay_fixed={int(fixed)}']
    text = run(name, [*args, *extra], expected=expected)
    if expected:
        return
    s = json.loads((OUT/f'{name}.json').read_text())
    assert s['pass'] and s['commits'] == s['diff_steps'] and s['interrupts'] == s['diff_interrupts'], s
    assert s['diff_sram_checks'] == s['diff_psram_checks'] == 1, s
    assert s['aw'] == s['w'] == s['b'] and s['ar']-s['r'] in (0, 1), s
    if uart is not None:
        assert (OUT/f'{name}.tx').read_bytes() == uart, name
    if delay:
        channels = re.findall(r'NPC_DELAY channel=(\d+) accepted=(\d+) delivered=(\d+) input_waits=(\d+) output_waits=(\d+)', text)
        assert len(channels) == 5, text[-2000:]
        s['delay_channels'] = [dict(zip(['channel','accepted','delivered','input_waits','output_waits'], map(int, row))) for row in channels]
        for c in s['delay_channels']:
            assert c['accepted'] >= c['delivered'] and c['accepted']-c['delivered'] <= 1
            assert c['input_waits'] > 0 and c['output_waits'] > 0, c
    WORKLOADS[name] = dict(summary=s, boot=boot, delay=delay, image=str(image.relative_to(ROOT)),
                         image_sha256=digest(image), executable_sha256=digest(exe))
    print(f'{name}: PASS commits={s["commits"]} IRQs={s["interrupts"]} cycles={s["cycles"]}', flush=True)
    return s


def rtthread():
    rtt = ROOT/'rt-thread-am'
    run('rtt-bsp-check', ['git', '-C', rtt, 'apply', '--reverse', '--check', NPC/'tests/soc-timer/rtthread-bsp.patch'])
    sources = [FIX/'rtthread-system.c', FIX/'preempt.S', rtt/'bsp/abstract-machine/src/context.c',
               rtt/'bsp/abstract-machine/src/interrupt.c']
    sources += [rtt/f'src/{n}.c' for n in ['clock','idle','irq','kservice','mem','object','scheduler_up','thread','timer']]
    image = soc.build('rtthread-system', sources, 'flash-psram',
                      f'INC_PATH += {rtt}/include {FIX}/include\nCFLAGS += -D__RTTHREAD__ -Wno-nonnull-compare')
    symbols = soc.IMAGES['rtthread-system']['symbols']
    regions = [('main', symbols['_stack_bottom'], symbols['_stack_top']),
               ('worker0', symbols['worker_stacks'], symbols['worker_stacks']+8192),
               ('worker1', symbols['worker_stacks']+8192, symbols['worker_stacks']+16384),
               ('idle', symbols['idle_thread_stack'], symbols['idle_thread_stack']+4096)]
    for name, delay in [('rtthread-normal', None), ('rtthread-delayed', (29, 7, False))]:
        extra = ['--irq-trace', OUT/f'{name}.irq.csv']
        for label, lo, hi in regions:
            extra += ['--stack-region', f'{label}:{lo:#x}:{hi:#x}']
        s = simulate(name, image, 'flash-psram', delay, extra=extra, cycles=150000000)
        tx = (OUT/f'{name}.tx').read_text()
        assert tx.endswith('RTT SYSTEM PASS\n'), tx
        preempt = re.search(r'PREEMPT progress=(\d+),(\d+) switches=(\d+),(\d+) irq_switches=(\d+)', tx)
        wake = re.search(r'WAKE elapsed=(\d+),(\d+) idle_runs=(\d+)', tx)
        heap = re.search(r'HEAP total=(\d+) before=(\d+) used=(\d+) peak=(\d+)', tx)
        assert preempt and wake and heap, tx
        p, w, h = [list(map(int, m.groups())) for m in (preempt, wake, heap)]
        assert p[:2] == [6,6] and min(p[2:4]) >= 3 and p[4] >= 8
        assert w[0] >= 4 and w[1] >= 6 and w[2] > 0
        assert h[1] == h[2] < h[3] < h[0]
        assert len(s['stacks']) == 4
        for stack in s['stacks']:
            assert stack['samples'] > 0 and stack['used'] > 0 and stack['remaining'] >= 128, stack
        WORKLOADS[name]['rtthread'] = dict(preempt=p, wake=w, heap=h)


def uart():
    image = soc.build('uart-long', [FIX/'uart-long.c'])
    expected = b'0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz!\n'*8
    for name, delay in [('uart-normal',None), ('uart-fixed',(1,3,True)), ('uart-random',(19,7,False))]:
        s = simulate(name, image, delay=delay, uart=expected,
                     extra=['--uart-bit-cycles',128, '--uart-events',OUT/f'{name}.uart.csv',
                            '--uart-serial-trace',OUT/f'{name}.serial.csv'])
        events = [list(map(int,row)) for row in csv.reader((OUT/f'{name}.uart.csv').open())]
        writes = [(r[2],r[3]) for r in events if r[1]]
        assert writes[:10] == [(3,128),(0,1),(1,0),(3,3),(1,0),(3,128),(0,8),(1,0),(3,3),(1,0)], writes[:10]
        busy = sum(not r[1] and r[2]==5 and not (r[3]&32) for r in events)
        assert busy>0 and s['uart_thr_writes'] == s['uart_serial_bytes'] == len(expected)
        frames = [list(map(int,row)) for row in csv.reader((OUT/f'{name}.serial.csv').open())]
        assert bytes(r[2] for r in frames) == expected
        assert all(end-start==128*10000*19//2 for start,end,_ in frames)
        assert all(b[0]>a[1] for a,b in zip(frames,frames[1:]))
        WORKLOADS[name]['uart'] = dict(bytes=len(expected), busy_polls=busy, divisor=8, bit_cycles=128)
    simulate('uart-wrong-baud', image, extra=['--uart-bit-cycles',16], expected='UART')


def random_system():
    hello = soc.build('hello', [NPC/'tests/soc-runtime/hello.c'])
    memory = soc.build('memory', [NPC/'tests/soc-runtime/memory.c'])
    for kind, image, uart in [('hello',hello,b'Hello, ysyxSoC!\n'),('memory',memory,b'M\n')]:
        simulate(kind+'-fixed', image, delay=(1,3,True), uart=uart)
        for seed in range(1,11):
            simulate(f'{kind}-seed-{seed}', image, delay=(seed,7,False), uart=uart)
    # Misdeclare a deliberately undersized main stack: the observer must
    # detect SP leaving it, independently of a DUT/REF instruction mismatch.
    top = soc.IMAGES['hello']['symbols']['_stack_top']
    simulate('stack-bound-negative', hello,
             extra=['--stack-region',f'main:{top-16:#x}:{top:#x}'],
             expected='SP outside declared stack regions')


def regression():
    # Reuse existing independent protocol/error and system fixtures; keep their
    # artifacts under S6 so the previous milestones' evidence is not overwritten.
    import m5_s1_test as unit
    import m5_s2_test as s2
    unit.OUT = s2.OUT = OUT
    def unit_run(name, args, negative=None):
        return run(name, args, expected=negative)
    unit.run = s2.run = unit_run
    unit.protocol(); unit.cpu(); s2.guard()
    soc.cpu_tests()
    bench = ROOT/'am-kernels/benchmarks/microbench'
    for kind in ('sieve','fib'):
        image = soc.build('micro-'+kind, [NPC/'tests/soc-runtime/microbench.c',bench/f'src/{kind}/{kind}.c'],
                          extra=f'INC_PATH += {bench}/include\nCFLAGS += '+('-DSMOKE_FIB' if kind=='fib' else ''))
        simulate('micro-'+kind, image, uart=b'')
    # Actual SoC default errors are separate from responder-injected SLVERR/DECERR.
    soc.smoke()
    s = simulate('storage-faults-delayed', OUT/'storage-faults.bin', delay=(17,7,False), uart=b'')
    assert s['exceptions'] == 8 and s['flash_dpi_calls'] == s['psram_read_bytes'] == s['psram_write_bytes'] == 0


def provenance():
    def git(path, *args):
        return subprocess.check_output(['git','-C',str(path),*args], text=True).strip()
    repos = {}
    for name in ('.','ysyxSoC','ysyxSoC/rocket-chip','rt-thread-am'):
        path = ROOT/name
        repos[name] = dict(head=git(path,'rev-parse','HEAD'), status=git(path,'status','--short'),
                          diff_sha256=hashlib.sha256(subprocess.check_output(['git','-C',str(path),'diff','HEAD','--binary'])).hexdigest())
    files = []
    for root in ('npc/vsrc','npc/csrc/soc','npc/sim','npc/scripts','npc/tests','abstract-machine/am',
                 'abstract-machine/scripts','nemu/src','nemu/include','nemu/scripts','ysyxSoC/perip',
                 'rt-thread-am/bsp/abstract-machine/src','rt-thread-am/src','rt-thread-am/include'):
        files += [p for p in (ROOT/root).rglob('*') if p.is_file() and p.suffix in ('.c','.h','.cpp','.sv','.v','.S','.py','.mk','.ld')]
    hashes = {str(p.relative_to(ROOT)):digest(p) for p in sorted(set(files)) if '__pycache__' not in p.parts}
    for name in ['npc/Makefile','npc/filelist-soc.f','abstract-machine/Makefile','nemu/.config',
                 'ysyxSoC/build/ysyxSoCFull.v','ysyxSoC/build.sc']:
        hashes[name] = digest(ROOT/name)
    tools = {tool:subprocess.check_output([tool,'--version'],text=True).splitlines()[0]
             for tool in ('verilator','riscv64-linux-gnu-gcc','python3')}
    return dict(repositories=repos, source_sha256=hashes, tools=tools, reference_sha256=digest(soc.REF))


def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only',choices=['rtthread','uart','random','regression'])
    args = parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    soc.OUT=OUT; soc.run=run
    manifest=provenance(); status='FAIL'
    suffix='-'+args.only if args.only else ''
    try:
        for name,fn in [('rtthread',rtthread),('uart',uart),('random',random_system),('regression',regression)]:
            if not args.only or args.only==name: fn()
        status='PASS'
    finally:
        # Older stage helpers retain their own validation; collect their raw
        # summaries here without counting build commands as workloads.
        for command in COMMANDS:
            argv = command['command']
            if '--summary' in argv and not command['expected_failure'] and command['status']=='PASS':
                name = command['name']
                if name not in WORKLOADS:
                    path = Path(argv[argv.index('--summary')+1])
                    WORKLOADS[name] = dict(summary=json.loads(path.read_text()),
                                          executable_sha256=command['executable_sha256'])
        manifest.update(status=status, group=args.only or 'all', commands=COMMANDS)
        (OUT/f'manifest{suffix}.json').write_text(json.dumps(manifest,indent=2)+'\n')
        (OUT/f'workloads{suffix}.json').write_text(json.dumps(WORKLOADS,indent=2)+'\n')
        (OUT/f'images{suffix}.json').write_text(json.dumps(soc.IMAGES,indent=2)+'\n')
    print(f'S6 {args.only or "all"}: PASS; evidence: {OUT}')


if __name__=='__main__':
    main()
