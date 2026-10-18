#!/usr/bin/env python3
"""S2.5 independent expected traps + legal Zicsr execution on legacy and B1.

The program checks cause/EPC/state itself; the runner checks exact trap sites and
memory request counts. DiffTest is additional state checking, not the oracle for
whether an instruction should trap. Sources/images/traces stay under build/.
"""
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'npc/build/isa-contract-test'
OUT.mkdir(parents=True, exist_ok=True)
REF = ROOT / 'nemu/build/riscv32-nemu-interpreter-so'


def command(name, args, **kwargs):
    result = subprocess.run(list(map(str, args)), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180, **kwargs)
    (OUT / f'{name}.log').write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{name}: exit {result.returncode}\n{result.stdout.decode(errors="replace")[-3000:]}')
    return result.stdout.decode(errors='replace')


def insn(op, f=0, hi=0, rd=10, rs1=11, rs2=12):
    return (hi << 25) | (rs2 << 20) | (rs1 << 15) | (f << 12) | (rd << 7) | op


cases = []
for f, name in enumerate(('mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu')):
    for rd in (0, 10, 12):
        cases.append((f'{name}-rd{rd}', insn(0x33, f, 1, rd)))
# Invalid widths, shift encodings, JALR and reserved branch/R-format variants.
for op, fs, hi in [(3, (3,6,7),0), (0x23,(3,4,5,6,7),0),
                   (0x63,(2,3),0), (0x67,(1,2,3,4,5,6,7),0),
                   (0x33,(1,2,3,4,6,7),0x20), (0x13,(1,5),1), (0x13,(1,),0x20)]:
    for f in fs: cases.append((f'invalid-{op:02x}-{f}-{hi}',insn(op,f,hi)))
for name, word in [('zero',0),('all-ones',0xffffffff),('compressed',1),('fence-i',0x100f),
                   ('ecall-rd',0xf3),('ebreak-rs1',0x108073),('mret-rd',0x302000f3),
                   ('wfi',0x10500073),('system-f3-4',0x4073)]:
    cases.append((name,word))
for addr in (0x301,0x340,0xc00,0xfff):
    for f in (1,2,3,5,6,7):
        # Includes unsupported read-only addresses, also zero-operand reads.
        cases.append((f'csr-{addr:03x}-{f}',(addr<<20)|(f<<12)|(10<<7)|0x73))
for name, word in [('rd16',insn(0x33,rd=16)),('rd26-alias',insn(0x13,rd=26)),
                   ('rs1-27',insn(0x33,rs1=27)),('rs2-28',insn(0x33,rs2=28)),
                   ('load-rd26',insn(3,2,rd=26)),('load-rs1-27',insn(3,2,rs1=27)),
                   ('store-rs1-27',insn(0x23,2,rs1=27)),('store-rs2-28',insn(0x23,2,rs2=28)),
                   ('branch-rs1-27',insn(0x63,rs1=27)),('branch-rs2-28',insn(0x63,rs2=28)),
                   ('jal-rd26',insn(0x6f,rd=26)),('lui-rd26',insn(0x37,rd=26)),
                   ('csr-rs1-31',0x342f9073),('csr-rd31',0x34202ff3)]:
    cases.append((name,word))

source = ['''    .section .text
    .globl _start
    .option norvc
    .option norelax
_start:
    la t0, handler
    csrw mtvec, t0
    li s1, 0
    la a1, scratch
    li a2, 0x33
    sw a2, 0(a1)
    li a0, 0x55
    li a3, 0
''']
for index,(name,word) in enumerate(cases):
    source.append(f'''    # {name}: exception and architectural side effects have independent expectations.
    li t0, 0x1808
    csrw mstatus, t0
    la s0, fault_{index}
fault_{index}:
    .word 0x{word:08x}
    li t0, {index+1}
    bne s1, t0, bad
    li t0, 0x55
    bne a0, t0, bad
    li t0, 0x33
    bne a2, t0, bad
    lw t1, 0(a1)
    bne t1, t0, bad
    csrr t0, mstatus
    li t1, 0x1888
    bne t0, t1, bad
''')
source.append('''    # Wrong-path illegal words must be killed before execution.
    j after_killed
    .word 0xffffffff
    .word 0x02c58533
after_killed:
    li a0, 0
    ebreak
handler:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, bad
    csrr t0, mepc
    bne t0, s0, bad
    csrr t1, mstatus
    li t2, 0x1880
    bne t1, t2, bad
    addi s1, s1, 1
    addi t0, t0, 4
    csrw mepc, t0
    mret
bad:
    li a0, 1
    ebreak
    .align 2
scratch:
    .word 0
''')

# Legal data-path checks do not rely solely on comparison with modified NEMU.
legal = '''    .section .text
    .globl _start
    .option norvc
    .option norelax
_start:
    la t0, bad
    csrw mtvec, t0
    li t0, 0x55
    csrrw t1, mcause, t0
    bnez t1, bad
    csrrs t1, mcause, zero
    li t2, 0x55
    bne t1, t2, bad
    csrrc t1, mcause, zero
    bne t1, t2, bad
    li a3, 0
    csrrs t1, mcause, a3
    bne t1, t2, bad
    csrrc t1, mcause, a3
    bne t1, t2, bad
    li t0, 0x0f
    csrrs t1, mcause, t0
    bne t1, t2, bad
    csrrc t1, mcause, t0
    li t2, 0x5f
    bne t1, t2, bad
    csrr t1, mcause
    li t2, 0x50
    bne t1, t2, bad
    csrrwi t1, mcause, 31
    bne t1, t2, bad
    csrrsi t1, mcause, 0
    li t2, 31
    bne t1, t2, bad
    csrrci t1, mcause, 0
    bne t1, t2, bad
    csrrci t1, mcause, 16
    bne t1, t2, bad
    csrrsi t1, mcause, 16
    li t2, 15
    bne t1, t2, bad
    csrrw zero, mcause, zero
    csrr t1, mcause
    bnez t1, bad
    csrrwi zero, mcause, 0
    # rd=rs1 must read the old source before writing the result.
    li t0, 0x25
    csrrw t0, mcause, t0
    bnez t0, bad
    csrr t1, mcause
    li t2, 0x25
    bne t1, t2, bad
    li t0, -1
    csrw mstatus, t0
    csrr t1, mstatus
    li t2, 0x1888
    bne t1, t2, bad
    csrw mepc, t0
    csrr t1, mepc
    li t2, -4
    bne t1, t2, bad
    la t0, bad
    ori t0, t0, 3
    csrw mtvec, t0
    csrr t1, mtvec
    la t2, bad
    bne t1, t2, bad
    # Legal immediate bits in rs2/rs1-shaped fields are not GPR operands.
    li t0, -1
    slli t1, t0, 31
    li t2, 0x80000000
    bne t1, t2, bad
    srli t1, t0, 31
    li t2, 1
    bne t1, t2, bad
    srai t1, t0, 31
    bne t1, t0, bad
    addi t1, zero, -16
    sub t2, zero, t1
    li a5, 16
    bne t2, a5, bad
    add t2, t1, t2
    bnez t2, bad
    lui t1, 0xfffff
    li t2, -4096
    bne t1, t2, bad
    fence
    # FENCE ignores reserved rd/rs1/fm fields in this serialized execution model.
    .word 0xffff8f8f
    li a0, 0
    ebreak
bad:
    li a0, 1
    ebreak
'''

results=[]
for name,text in [('illegal',''.join(source)),('legal',legal)]:
    asm=OUT/f'{name}.S'; elf=OUT/f'{name}.elf'; binary=OUT/f'{name}.bin'
    asm.write_text(text)
    command(name+'-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
            '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x80000000','-Wl,--build-id=none',
            '-Wl,--no-relax',asm,'-o',elf])
    command(name+'-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,binary])
    symbols=command(name+'-symbols',['riscv64-linux-gnu-nm','-n',elf])
    addresses={fields[2]:int(fields[0],16) for line in symbols.splitlines() if len(fields:=line.split())==3}
    expected=[(addresses[f'fault_{i}'],word) for i,(_,word) in enumerate(cases)] if name=='illegal' else []
    for platform,exe in [('legacy','npc/build/Vysyx_core'),('b1','npc/build/b1-1048576-1000000/Vysyx_b1_top')]:
        tag=f'{platform}-{name}'; trace=OUT/f'{tag}.trace'
        env=dict(os.environ,NPC_MAX_CYCLES='1000000')
        log=command(tag,[ROOT/exe,'-b','-d',REF,f'--commit-trace={trace}',binary],env=env)
        assert 'HIT GOOD TRAP' in log and 'Differential testing:' in log, tag
        rows=[line.split() for line in trace.read_text().splitlines() if not line.startswith('#')]
        traps=[r for r in rows if r[5]=='1']
        assert [(int(r[1],16),int(r[2],16)) for r in traps]==expected, (tag,'trap sites')
        assert all(int(r[6],16)==2 and r[9]=='0' for r in traps), (tag,'trap metadata')
        # Only one scratch initialization store and one check load per fault.
        loads=len(cases) if name=='illegal' else 0; stores=int(name=='illegal')
        if platform=='legacy':
            assert f'D-RAM transactions: requests = {loads+stores} (loads = {loads}, stores = {stores})' in log, tag
        else:
            assert f'B1 master LSU ar={loads} aw={stores} w={stores} completed={loads+stores}' in log, tag
        results.append(dict(name=tag,status='PASS',commits=len(rows),expected_traps=len(expected),loads=loads,stores=stores))
        print(f'{tag}: PASS ({len(expected)} independently expected traps)',flush=True)
(OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print(f'ISA contract: PASS; evidence: {OUT}')
