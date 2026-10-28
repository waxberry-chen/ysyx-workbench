#!/usr/bin/env python3
"""S4 real serial storage + boot. Build with make -C npc s4-test.

--only smoke/boot/cpu/capacity permits focused reruns; default runs every group.
Images live in Flash/MROM only. RAM is modified by CPU or serial pin traffic.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import resource
import subprocess

ROOT=Path(__file__).resolve().parents[2]
NPC=ROOT/'npc'
OUT=NPC/'build/m5-s4'
REF=ROOT/'nemu/build/ysyxsoc/nemu-ref.so'
FIX=NPC/'tests/soc-boot'
CPU=ROOT/'am-kernels/tests/cpu-tests'
RESULTS=[]
IMAGES={}

def run(name,args,cwd=NPC,expected=None):
    p=subprocess.run(list(map(str,args)),cwd=cwd,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,timeout=600)
    text=p.stdout.decode(errors='replace');(OUT/f'{name}.log').write_text(text)
    if expected: assert p.returncode!=0 and expected in text,(name,text[-4000:])
    else: assert p.returncode==0,(name,p.returncode,text[-4000:])
    RESULTS.append(dict(name=name,status='PASS',negative=bool(expected)))
    return text

def symbols(elf):
    text=subprocess.check_output(['riscv64-linux-gnu-nm',str(elf)],text=True)
    return {p[2]:int(p[0],16) for line in text.splitlines() if len(p:=line.split())==3}

def build(name,sources,boot='mrom',extra=''):
    folder=OUT/'programs'/name;folder.mkdir(parents=True,exist_ok=True)
    (folder/'Makefile').write_text(f'NAME = {name}\nSRCS = '+ ' '.join(map(str,sources))+
        f'\nINC_PATH += {CPU / "include"}\n{extra}\ninclude {ROOT}/abstract-machine/Makefile\n')
    run(name+'-build',['make','ARCH=riscv32e-ysyxsoc',f'SOC_BOOT={boot}','insert-arg'],folder)
    suffix='' if boot=='mrom' else '-'+boot
    base=folder/'build'/f'{name}-riscv32e-ysyxsoc{suffix}'
    img=base.with_suffix('.bin');sym=symbols(base.with_suffix('.elf'))
    IMAGES[name]=dict(profile=boot,binary_bytes=img.stat().st_size,
        sha256=hashlib.sha256(img.read_bytes()).hexdigest(),symbols=sym,
        static_ram_bytes=sym['_bss_end']-sym.get('_text_start',sym['_data_start']),
        heap_bytes=sym['_heap_end']-sym['_heap_start'],
        stack_reserved=sym['_stack_top']-sym['_stack_bottom'])
    return img

def simulate(name,image,boot='mrom',flash=None,uart=None,trace=False,expected=None,
             max_cycles=300000000,thread_stacks=False):
    exe=NPC/f'build/ysyxsoc{"-flash" if boot!="mrom" else ""}/VysyxSoCFull'
    args=[exe,'--mrom' if boot=='mrom' else '--flash',image,'--diff',REF,
          '--max-cycles',max_cycles,'--summary',OUT/f'{name}.json','--uart-log',OUT/f'{name}.tx']
    if flash: args+=['--flash',flash]
    if trace: args+=['--commit-trace',OUT/f'{name}.commit.csv','--bus-trace',OUT/f'{name}.bus.csv',
                    '--irq-trace',OUT/f'{name}.irq.csv']
    run(name,args,expected=expected)
    if expected:return
    s=json.loads((OUT/f'{name}.json').read_text())
    assert s['pass'] and s['commits']==s['diff_steps'] and s['diff_sram_checks']==s['diff_psram_checks']==1,s
    if uart is not None: assert (OUT/f'{name}.tx').read_bytes()==uart
    if name in IMAGES:
        syms=IMAGES[name]['symbols']
        low=s['min_psram_sp'] if boot=='flash-psram' else s['min_sram_sp']
        if thread_stacks:
            # Minimum SP may belong to a thread's bss stack, not the main stack.
            IMAGES[name]['lowest_observed_sp']=low
        else:
            assert low>=syms['_stack_bottom']
            IMAGES[name]['stack_used']=syms['_stack_top']-low
    print(f'{name}: PASS ({s["commits"]} commits, {s["cycles"]} cycles)',flush=True)
    return s

def smoke():
    pattern=bytearray([255])*0x12348
    pattern[0x12340:]=bytes.fromhex('1234567889abcdef')
    flash=OUT/'pattern.bin';flash.write_bytes(pattern)
    s=simulate('spi',build('spi',[FIX/'spi.c']),flash=flash,uart=b'F\n')
    assert s['flash_dpi_calls']>=9 and s['psram_write_bytes']==0
    s=simulate('psram',build('psram',[FIX/'psram.c']),uart=b'P\n')
    assert s['psram_read_bytes']>1024 and s['psram_write_bytes']>1024
    src=OUT/'xip.S'
    src.write_text('.section .text\n.globl _start\n_start:\nli a0,0\nebreak\n')
    elf=OUT/'xip.elf';image=OUT/'xip.bin'
    run('xip-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
        '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x30000000','-Wl,--build-id=none',src,'-o',elf])
    run('xip-image',['riscv64-linux-gnu-objcopy','-O','binary',elf,image])
    s=simulate('xip',image,'flash',uart=b'',trace=True)
    assert s['reset_pc']==0x30000000 and s['flash_dpi_calls']>=2 and s['mrom_dpi_calls']==0
    # The REF independently rejects access faults; no device-input token is
    # allowed to disguise an out-of-capacity Flash/PSRAM access.
    cases=[(0x30000000,'sw',7),(0x31000000,'lw',5),
           (0x80400000,'lw',5),(0x80400000,'sw',7),
           (0x80000001,'lw',4),(0x80000001,'sw',6),
           (0x1000101c,'lw',5),(0x10001020,'sw',7)]
    lines=['.section .text','.globl _start','_start:',
           'la t0,handler','csrw mtvec,t0','li a3,0']
    for i,(addr,op,cause) in enumerate(cases):
        lines += [f'li a1,0x{addr:x}',f'li s1,{cause}',f'la s0,fault{i}',
                  f'fault{i}:',f'{op} t1,0(a1)','j bad',f'resume{i}:']
    lines += [f'li t0,{len(cases)}','bne a3,t0,bad','li a0,0','ebreak',
              'handler:','csrr t0,mcause','bne t0,s1,bad','csrr t0,mepc',
              'bne t0,s0,bad','addi t0,t0,8','csrw mepc,t0','addi a3,a3,1',
              'mret','bad:','li a0,1','ebreak']
    src=OUT/'storage-faults.S';src.write_text('\n'.join(lines)+'\n')
    elf=OUT/'storage-faults.elf';image=OUT/'storage-faults.bin'
    run('storage-faults-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
        '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x20000000','-Wl,--build-id=none',
        '-Wl,--no-relax',src,'-o',elf])
    run('storage-faults-image',['riscv64-linux-gnu-objcopy','-O','binary',elf,image])
    s=simulate('storage-faults',image,trace=True)
    assert s['exceptions']==len(cases) and s['flash_dpi_calls']==s['psram_read_bytes']==s['psram_write_bytes']==0

def boot_tests():
    for profile in ('flash-sram','flash-psram'):
        name='boot-'+profile
        image=build(name,[FIX/'runtime.c'],profile)
        s=simulate(name,image,profile,uart=b'B\n',trace=True)
        assert s['flash_dpi_calls']>0 and s['mrom_dpi_calls']==0
        syms=IMAGES[name]['symbols']
        with (OUT/f'{name}.commit.csv').open() as f: rows=list(csv.reader(f))
        assert any(int(r[1],16)==syms['_trm_init'] for r in rows)
        stores=[r for r in rows if int(r[4],16)&6==6]
        regions=[('__am_ram_poison','__am_text_copy','_text_start','_bss_end'),
                 ('__am_text_copy','__am_data_copy','_text_start','_text_end'),
                 ('__am_data_copy','__am_bss_clear','_data_start','_data_end'),
                 ('__am_bss_clear','__am_runtime_ready','_bss_start','_bss_end')]
        counts={}
        for begin,end,lo,hi in regions:
            selected=[r for r in stores if syms[begin]<=int(r[1],16)<syms[end]]
            assert [int(r[6],16) for r in selected]==list(range(syms[lo],syms[hi],4))
            counts[begin]=len(selected)
        (OUT/f'{name}-startup.json').write_text(json.dumps(counts,indent=2)+'\n')
        for begin,end,_,_ in regions[2:]:
            data=bytearray(image.read_bytes());changed=0
            for pc in range(syms[begin],syms[end],4):
                off=pc-0x30000000;ins=int.from_bytes(data[off:off+4],'little')
                if ins&127==0x23:data[off:off+4]=(0x13).to_bytes(4,'little');changed+=1
            assert changed==1
            neg=OUT/f'{name}-{begin}.bin';neg.write_bytes(data)
            simulate(name+'-missing-'+begin,neg,profile,expected='ebreak with nonzero a0')
    # Host-side image bounds and linker-side RAM bounds are separate gates.
    flash_exe=NPC/'build/ysyxsoc-flash/VysyxSoCFull'
    for name,size in [('flash-empty',0),('flash-oversized',16*1024*1024+1)]:
        image=OUT/f'{name}.bin'
        with image.open('wb') as f:f.truncate(size)
        run(name,[flash_exe,'--flash',image],expected='Empty/oversized image')
    for profile,size in [('flash-sram',8192),('flash-psram',4*1024*1024)]:
        name='overflow-'+profile;folder=OUT/'programs'/name;folder.mkdir(parents=True,exist_ok=True)
        (folder/'overflow.c').write_text(f'volatile char large[{size}]; int main(void) {{return large[0];}}\n')
        (folder/'Makefile').write_text(f'NAME={name}\nSRCS=overflow.c\ninclude {ROOT}/abstract-machine/Makefile\n')
        run(name,['make','ARCH=riscv32e-ysyxsoc',f'SOC_BOOT={profile}','image'],folder,
            expected='RAM static sections overlap reserved stack')
    folder=OUT/'programs/overflow-flash';folder.mkdir(parents=True,exist_ok=True)
    (folder/'padding.S').write_text('.section entry,"ax"\n.space 16777216\n')
    (folder/'main.c').write_text('int main(void) {return 0;}\n')
    (folder/'Makefile').write_text(f'NAME=overflow-flash\nSRCS=main.c padding.S\ninclude {ROOT}/abstract-machine/Makefile\n')
    run('overflow-flash',['make','ARCH=riscv32e-ysyxsoc','SOC_BOOT=flash-sram','image'],folder,
        expected='Flash image exceeds 16 MiB')

def cpu_tests():
    matrix=[]
    for source in sorted((CPU/'tests').glob('*.c')):
        name=source.stem
        if name=='unalign':
            matrix.append(dict(name=name,status='EXCLUDED',reason='RV32E policy traps misaligned data accesses'));continue
        tag='cpu-'+name;img=build(tag,[source],'flash-psram')
        simulate(tag,img,'flash-psram')
        matrix.append(dict(name=name,status='PASS'))
    (OUT/'cpu-tests.json').write_text(json.dumps(matrix,indent=2)+'\n')

def capacity():
    rtt=ROOT/'rt-thread-am'
    sources=[NPC/'tests/b1-rtthread/workload.c',rtt/'bsp/abstract-machine/src/context.c']
    sources += [rtt/f'src/{name}.c' for name in
                ['clock','idle','irq','kservice','mem','object','scheduler_up','thread','timer']]
    image=build('rtthread-capacity',sources,'flash-psram',
                f'INC_PATH += {rtt}/include {NPC}/tests/b1-rtthread/include\nCFLAGS += -D__RTTHREAD__ -Wno-nonnull-compare')
    expected=b'RTTHREAD BEGIN cooperative\n'+b'AB'*100+b'\nRTTHREAD PASS iterations=100,100 heap_restored=1\n'
    s=simulate('rtthread-capacity',image,'flash-psram',uart=expected,thread_stacks=True)
    assert s['exceptions']>=200 and IMAGES['rtthread-capacity']['static_ram_bytes']>8192
    # Thread stacks live in bss: the global minimum SP is not main-stack usage.
    IMAGES['rtthread-capacity']['thread_stack_reservation']=2*8192

def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0));OUT.mkdir(parents=True,exist_ok=True)
    parser=argparse.ArgumentParser();parser.add_argument('--only',choices=['smoke','boot','cpu','capacity'])
    args=parser.parse_args()
    for name,fn in [('smoke',smoke),('boot',boot_tests),('cpu',cpu_tests),('capacity',capacity)]:
        if not args.only or args.only==name:fn()
    suffix='-'+args.only if args.only else ''
    (OUT/f'images{suffix}.json').write_text(json.dumps(IMAGES,indent=2)+'\n')
    (OUT/f'results{suffix}.json').write_text(json.dumps(RESULTS,indent=2)+'\n')
    print('S4 selected groups: PASS')
if __name__=='__main__':main()
