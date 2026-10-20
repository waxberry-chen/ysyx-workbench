#!/usr/bin/env python3
"""M5 S1 verification; all compiler products/logs stay in npc/build/m5-s1.

Independent transaction scoreboards, existing architectural tests, and static
real-SoC elaboration have separate exits. This does not claim S2 system bring-up.
"""
import argparse
import csv
import json
from pathlib import Path
import re
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NPC = ROOT/'npc'
OUT = NPC/'build/m5-s1'
OUT.mkdir(parents=True, exist_ok=True)
RESULTS = []

def run(name, args, *, negative=None):
    result = subprocess.run(list(map(str,args)), cwd=NPC, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=240)
    text = result.stdout.decode(errors='replace')
    (OUT/f'{name}.log').write_text(text)
    if negative:
        assert result.returncode != 0 and negative in text, (name,text[-2500:])
    elif result.returncode:
        raise RuntimeError(f'{name}: exit {result.returncode}\n{text[-4000:]}')
    RESULTS.append(dict(name=name,status='PASS',negative=bool(negative)))
    print(f'{name}: PASS', flush=True)
    return text

FLAGS = ['verilator','--sv','--assert','-Wall','-Wno-fatal','-Wno-SYNCASYNCNET','-Wno-TIMESCALEMOD',
         '-Werror-WIDTH','-Werror-PINMISSING','-Werror-PINNOTFOUND','-Werror-LATCH','-Werror-UNOPTFLAT']
def cpp(name, top, sources, tb, flags=()):
    out=OUT/name
    run(name+'-build',[*FLAGS,'--cc','--exe','--build','-j','2','--top-module',top,
        '--Mdir',out,'-CFLAGS','-std=c++17',*flags,*sources,NPC/'tests'/tb])
    return out/f'V{top}'

def sv(name,top,sources):
    out=OUT/name
    run(name+'-build',[*FLAGS,'--binary','--timing','--top-module',top,'--Mdir',out,*sources])
    run(name,[out/f'V{top}'])

def protocol():
    for kind in ['ifu','lsu']:
        top=f'ysyx_{kind}_axi4_adapter_tb'
        sv(kind+'-adapter',top,[f'vsrc/bus/ysyx_{kind}_axi4_adapter.sv',f'tests/{top}.sv'])
    sv('ifu-integration','ysyx_ifu_axi4_adapter_integ_tb',[
       'vsrc/gnrl/ysyx_gnrl_primitive.sv','vsrc/core/ysyx_ifu.sv',
       'vsrc/bus/ysyx_ifu_axi4_adapter.sv','tests/ysyx_ifu_axi4_adapter_integ_tb.sv'])
    arb=cpp('arbiter','ysyx_axi4_arbiter',['vsrc/bus/ysyx_axi4_arbiter.sv'],'axi4_arbiter_tb.cpp')
    run('arbiter',[arb,OUT/'arbiter/coverage.csv'])
    fab=cpp('fabric','axi4_fabric_test_top',['vsrc/bus/ysyx_axi4_arbiter.sv',
       'vsrc/bus/ysyx_axi4_router.sv','vsrc/periph/ysyx_clint.sv','tests/axi4_fabric_test_top.sv'],'axi4_arbiter_tb.cpp',flags=['-CFLAGS','-DTEST_ROUTER'])
    run('fabric',[fab,OUT/'fabric/coverage.csv'])
    for exe,name in [(arb,'arbiter'),(fab,'fabric')]:
        for fault in ['rid','bid','rlast']:
            run(f'{name}-bad-{fault}',[exe,OUT/f'{name}/unused.csv',fault],negative='AXI4 protocol:')
    redirect=cpp('redirect','axi4_redirect_test_top',['vsrc/gnrl/ysyx_gnrl_primitive.sv',
       'vsrc/core/ysyx_ifu.sv','vsrc/bus/ysyx_ifu_axi4_adapter.sv','vsrc/bus/ysyx_axi4_arbiter.sv',
       'tests/axi4_redirect_test_top.sv'],'axi4_redirect_tb.cpp')
    run('redirect',[redirect,OUT/'redirect/coverage.csv'])
    sv('clint','ysyx_clint_tb',['vsrc/periph/ysyx_clint.sv','tests/ysyx_clint_tb.sv'])
    sv('router-local','ysyx_axi4_router_tb',['vsrc/bus/ysyx_axi4_router.sv',
       'vsrc/periph/ysyx_clint.sv','tests/ysyx_axi4_router_tb.sv'])
    sv('wrapper','ysyx_soc_wrapper_tb',['-F','filelist-soc.f','tests/ysyx_soc_wrapper_tb.sv'])
    for option,diagnostic in [('badirq','External IRQ is outside'),('badslave','ChipLink/slave request')]:
        run('wrapper-'+option,[OUT/'wrapper/Vysyx_soc_wrapper_tb','+'+option],negative=diagnostic)

def compile_image(name, source, defines=()):
    elf=OUT/f'{name}.elf';binary=OUT/f'{name}.bin'
    run(name+'-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
        '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x80000000','-Wl,--build-id=none',
        '-Wl,--no-relax',*defines,source,'-o',elf])
    run(name+'-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,binary])
    return binary

def cpu():
    exe=cpp('cpu','axi4_cpu_test_top',['-F','filelist-soc.f','tests/axi4_cpu_test_top.sv'],'axi4_cpu_tb.cpp',flags=['--trace-fst'])
    run('isa-contract',['python3','tests/isa_contract_test.py'])
    for kind,cause in [('fetch',1),('load',5),('store',7)]:
        binary=compile_image('fault-'+kind,'tests/access_fault.S',[f'-DFAULT_KIND={dict(fetch=1,load=2,store=3)[kind]}',f'-DFAULT_CAUSE={cause}'])
        for resp in (2,3):
            name=f'fault-{kind}-{resp}';trace=OUT/f'{name}.trace'
            run(name,[exe,binary,trace,17,resp])
            traps=[r.split() for r in trace.read_text().splitlines() if r.split()[5]=='1']
            assert len(traps)==1 and int(traps[0][6],16)==cause, name
    for kind,cause in [('load',4),('store',6)]:
        name='misaligned-'+kind
        binary=compile_image(name,'tests/address_misaligned.S',[f'-DFAULT_KIND={2 if kind=="load" else 3}',f'-DFAULT_CAUSE={cause}'])
        text=run(name,[exe,binary,OUT/f'{name}.trace',19])
        assert 'writes=0 data_reads=0 ' in text, text
    binary=compile_image('memory','tests/m5_s1_memory.S')
    for seed in range(1,11):
        name=f'memory-{seed}';text=run(name,[exe,binary,OUT/f'{name}.trace',seed,3,
            *([OUT/'memory-1.fst'] if seed==1 else [])])
        assert 'device_reads=1 device_writes=1' in text,text

def elaboration():
    run('cpu-lint',[*FLAGS,'--lint-only','--top-module','ysyx_00000000','-F','filelist-soc.f'])
    run('cpu-synthesis-lint',[*FLAGS,'--lint-only','-DSYNTHESIS','-DNPC_SIM_DPI',
        '--top-module','ysyx_00000000','-F','filelist-soc.f'])
    # Compare the actual handwritten wrapper with the S0 frozen independent table.
    text=(NPC/'vsrc/top/ysyx_00000000.sv').read_text().split(');',1)[0]
    actual={n:(d,int(w)+1 if w else 1) for d,w,n in re.findall(r'\b(input|output)\s+(?:\[(\d+):0\]\s+)?(\w+)',text)}
    with (ROOT/'docs/notes/post-c/5-ysyx-soc-integration/s0-validation/cpu-ports.csv').open() as f:
        expected={r['name']:(r['direction_at_cpu'],int(r['width'])) for r in csv.DictReader(f)}
    assert actual==expected, (actual,expected)
    soc=ROOT/'ysyxSoC'
    run('soc-elaboration',[*FLAGS,'--lint-only','--timing','--top-module','ysyxSoCFull',
        '--Mdir',OUT/'soc-elaboration','-F','filelist-soc.f',
        f'-I{soc}/perip/uart16550/rtl',f'-I{soc}/perip/spi/rtl',soc/'build/ysyxSoCFull.v',
        *sorted((soc/'perip').rglob('*.v'))])

if __name__=='__main__':
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    parser=argparse.ArgumentParser();parser.add_argument('--part',choices=['all','protocol','cpu','elaboration'],default='all')
    args=parser.parse_args()
    for name,fn in [('protocol',protocol),('cpu',cpu),('elaboration',elaboration)]:
        if args.part in ('all',name):fn()
    (OUT/f'results-{args.part}.json').write_text(json.dumps(RESULTS,indent=2)+'\n')
    print(f'S1 {args.part}: PASS; evidence: {OUT}')
