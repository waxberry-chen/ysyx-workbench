#!/usr/bin/env python3
"""M3 S4 fixed-timing system regression; fail on exit, trap, UART or trace mismatch."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--binary', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--sram-bytes', type=int, default=1048576)
p.add_argument('--mtime-hz', type=int, default=1000000)
p.add_argument('--focused', action='store_true', help='AM lanes/uptime/yield only')
a = p.parse_args()
a.binary = a.binary.resolve(); a.out = a.out.resolve(); a.out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, AM_HOME=str(ROOT/'abstract-machine'), NEMU_HOME=str(ROOT/'nemu'), NPC_HOME=str(ROOT/'npc'))
suffix = f'riscv32e-npc-b1-{a.sram_bytes}-{a.mtime_hz}'
flags = ['ARCH=riscv32e-npc', 'NPC_PLATFORM=b1', f'SRAM_BYTES={a.sram_bytes}', f'MTIME_HZ={a.mtime_hz}']
commands, results = [], []

def command(name, argv, cwd=ROOT, extra=None, stdin=None):
    e = dict(env); e.update(extra or {})
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=e, input=stdin,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (a.out/f'{name}.log').write_bytes(result.stdout)
    commands.append(dict(name=name, argv=list(map(str, argv)), cwd=str(cwd), exit=result.returncode))
    (a.out/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
    return result.returncode, result.stdout.decode(errors='replace')

def checked(name, argv, **kwargs):
    rc, log = command(name, argv, **kwargs)
    assert rc == 0, f'{name}: exit {rc}; see {a.out/name}.log\n{log[-1500:]}'
    return log

def run(name, image, uart=b'', cause=None, route=None, misaligned=False):
    trace, uart_path = a.out/f'{name}.trace', a.out/f'{name}.uart'
    log = checked(name, [a.binary, '-b', '-d', ROOT/'nemu/build/riscv32-nemu-interpreter-so',
                  f'--commit-trace={trace}', image], extra={'NPC_UART_LOG':str(uart_path), 'NPC_MAX_CYCLES':'50000000'})
    assert 'HIT GOOD TRAP' in log and 'Differential testing:' in log, name
    assert uart_path.read_bytes() == uart, f'{name}: UART mismatch'
    rows = [s.split() for s in trace.read_text().splitlines() if not s.startswith('#')]
    faults = [r for r in rows if r[5] == '1']
    if cause is not None:
        assert len(faults) == 1 and int(faults[0][6],16) == cause, (name,faults)
        if cause in (5,7): assert faults[0][12] == '1', name
    elif name == 'yield-os':
        assert len(faults) == 201 and all(int(r[6],16)==11 for r in faults), name
    else: assert not faults, (name,faults)
    if route:
        m = re.search(r'B1 route='+route+r' .*?rerr=(\d+) berr=(\d+)',log)
        assert m and sum(map(int,m.groups())) > 0, name
    if misaligned: assert 'B1 master LSU ar=0 aw=0 w=0 completed=0' in log, name
    cycles = int(re.search(r'cycles\s+= (\d+)',log).group(1))
    digest = hashlib.sha256((''.join(' '.join(r[:5])+'\n' for r in rows)).encode()).hexdigest()
    results.append(dict(name=name,status='PASS',instructions=len(rows),cycles=cycles,exceptions=len(faults),
                        image=str(image),image_sha256=hashlib.sha256(Path(image).read_bytes()).hexdigest(),architecture_sha256=digest))
    with (a.out/'results.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=results[0].keys());writer.writeheader();writer.writerows(results)
    print(f'{name}: PASS commits={len(rows)} cycles={cycles}',flush=True)

def am_image(name, directory, makefile=None, args=()):
    cmd=['make','-C',directory]
    if makefile: cmd+=['-f',makefile]
    checked(name+'-build', cmd+flags+list(args)+['insert-arg'])
    return directory/'build'/f'{name}-{suffix}.bin'

if not a.focused:
    directory=ROOT/'am-kernels/tests/cpu-tests'
    for source in sorted((directory/'tests').glob('*.c')):
        if source.stem == 'unalign': continue
        mf=a.out/f'{source.stem}.mk'
        mf.write_text(f'NAME={source.stem}\nSRCS=tests/{source.name}\ninclude $(AM_HOME)/Makefile\n')
        image=am_image(source.stem,directory,mf)
        run(source.stem,image)
    image=am_image('hello',ROOT/'am-kernels/kernels/hello',args=['mainargs=I-love-ysyx'])
    run('hello',image,uart=b"Hello, AbstractMachine!\nmainargs = 'I-love-ysyx'.\n")

for name,expected in [('lanes',b'lanes PASS\n'),('uptime',b'uptime PASS\n'),
                       ('yield-os',b'AB'*100+b'\nyield-os PASS\n')]:
    image=am_image(name,ROOT/'npc/tests/b1-am',args=[f'TEST={name}'])
    run(name,image,uart=expected)

if not a.focused:
    cases=[]
    for origin,addr in [('unmapped',0),('sram-end',0x80000000+a.sram_bytes)]:
        for kind,cause in [(1,1),(2,5),(3,7)]: cases.append((f'{origin}-{kind}',kind,cause,addr,'default'))
    cases += [('uart-fetch',1,1,0xa00003f8,'uart'),('clint-fetch',1,1,0xa0000048,'clint'),
              ('uart-read',2,5,0xa00003f8,'uart'),('clint-write',3,7,0xa0000048,'clint'),
              ('uart-reserved',3,7,0xa00003fc,'uart'),('uart-word',3,7,0xa00003f8,'uart'),
              ('misaligned-load',2,4,0x80000001,None),('misaligned-store',3,6,0x80000001,None)]
    for name,kind,cause,addr,route in cases:
        elf=a.out/f'{name}.elf'; image=elf.with_suffix('.bin')
        checked(name+'-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie','-march=rv32e_zicsr','-mabi=ilp32e',
                '-Wl,-Ttext=0x80000000','-Wl,--build-id=none',f'-DFAULT_KIND={kind}',f'-DFAULT_CAUSE={cause}',
                f'-DFAULT_ADDR={addr}',ROOT/'npc/tests/b1_fault.S','-o',elf])
        checked(name+'-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,image])
        run(name,image,cause=cause,route=route,misaligned=cause in (4,6))
    elf=a.out/'redirect.elf'; image=elf.with_suffix('.bin')
    checked('redirect-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie','-march=rv32e_zicsr','-mabi=ilp32e',
            '-Wl,-Ttext=0x80000000','-Wl,--build-id=none',f'-DSRAM_BYTES={a.sram_bytes}',
            ROOT/'npc/tests/b1_redirect.S','-o',elf])
    checked('redirect-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,image])
    run('redirect',image,route='default')

# Debugger must observe the post-execution RTL array, not the preload buffer.
image=ROOT/'npc/tests/b1-am/build'/f'lanes-{suffix}.bin'
log=checked('debugger',[a.binary,'-d',ROOT/'nemu/build/riscv32-nemu-interpreter-so',image],
            stdin=f'c\nx 1 {hex(0x80000000+a.sram_bytes-4)}\nq\n'.encode())
assert '0x13579bdf' in log and 'HIT GOOD TRAP' in log
oversized=a.out/'oversized.bin'
with oversized.open('wb') as f: f.truncate(a.sram_bytes+1)
rc,log=command('oversized',[a.binary,'-b',oversized])
assert rc != 0 and 'exceeds capacity' in log
rc,log=command('legacy-timing-rejected',[a.binary,'-b','--ram-seed=1',image])
assert rc != 0 and 'timing options are unavailable in B1' in log
rc,log=command('cycle-limit',[a.binary,'-b','-d',ROOT/'nemu/build/riscv32-nemu-interpreter-so',image],
               extra={'NPC_MAX_CYCLES':'10'})
assert rc != 0 and 'cycle limit reached' in log
(a.out/'guards.json').write_text(json.dumps(dict(debugger='PASS',oversized_loader='PASS',
   legacy_timing_rejected='PASS',cycle_limit='PASS'),indent=2)+'\n')
print(f'B1 system regression: {len(results)} PASS',flush=True)
