#!/usr/bin/env python3
"""S5: timer contract, independent trap expectations, AM context, timed IRQs.

Reuse existing compiler/SoC helpers; keep all generated images/traces in m5-s5.
Run `make -C npc s5-test`, or this script after rebuilding RTL/reference.
"""
import json
import resource
import ctypes
import m5_s1_test as unit
import m5_s4_test as soc

OUT=soc.NPC/'build/m5-s5'
FIX=soc.NPC/'tests/soc-timer'

def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    OUT.mkdir(parents=True,exist_ok=True)
    unit.OUT=soc.OUT=OUT
    unit.sv('clint','ysyx_clint_tb',['vsrc/periph/ysyx_clint.sv','tests/ysyx_clint_tb.sv'])
    s=soc.simulate('timer-registers',soc.build('timer-registers',[FIX/'timer-registers.c']),
                   uart=b'',max_cycles=500000)
    assert s['interrupts']==s['diff_interrupts']==0,s
    elf=OUT/'trap.elf';binary=OUT/'trap.bin'
    soc.run('trap-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
        '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x20000000','-Wl,--build-id=none',
        '-Wl,--no-relax',FIX/'trap.S','-o',elf])
    soc.run('trap-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,binary])
    s=soc.simulate('trap',binary,trace=True,uart=b'',max_cycles=20000)
    assert s['interrupts']==s['diff_interrupts']==2 and s['exceptions']==1,s
    # Independently exercise the reference IRQ eligibility API. No DUT cause,
    # EPC or status is supplied to determine the expected entry state.
    ref=ctypes.CDLL(str(soc.REF));state=(ctypes.c_uint32*23)()
    ref.difftest_regcpy.argtypes=[ctypes.c_void_p,ctypes.c_bool]
    ref.difftest_regcpy.restype=None
    ref.difftest_soc_timer.argtypes=[ctypes.c_bool]
    ref.difftest_soc_timer.restype=None
    ref.difftest_soc_interrupt.argtypes=[]
    ref.difftest_soc_interrupt.restype=ctypes.c_int
    for mie in [0,128]:
        for pending in [0,1]:
            for global_enable in [0,8]:
                state[16]=0x20000100;state[17]=0x1800|global_enable
                state[18]=0x20000200;state[19]=0;state[20]=0;state[21]=mie
                ref.difftest_regcpy(state,True);ref.difftest_soc_timer(pending)
                rc=ref.difftest_soc_interrupt();ref.difftest_regcpy(state,False)
                enabled=bool(mie and pending and global_enable)
                assert rc==(0 if enabled else -1)
                if enabled:
                    assert list(state)[16:21]==[0x20000200,0x1880,0x20000200,0x20000100,0x80000007]
                else:assert state[16]==0x20000100 and state[19]==state[20]==0
    soc.RESULTS.append(dict(name='reference-irq-masks',status='PASS',negative=False))
    soc.run('irq-epc-negative',[soc.NPC/'build/ysyxsoc/VysyxSoCFull','--mrom',binary,
        '--diff',soc.REF,'--irq-inject-at',1,'--max-cycles',20000],expected='DiffTest mismatch IRQ state')
    for boot in ['mrom','flash-sram','flash-psram']:
        name='am-timer-'+boot
        image=soc.build(name,[FIX/'am-timer.c',FIX/'registers.S'],boot)
        s=soc.simulate(name,image,boot,uart=b'T\n',trace=True,max_cycles=2000000)
        assert s['interrupts']==s['diff_interrupts']==4,s
        if boot=='mrom':
            # Delete the trap epilogue's lw t0,20(sp): ordinary instruction
            # DiffTest still agrees, but the software sentinel must fail.
            blob=bytearray(image.read_bytes())
            restore=(0x01412283).to_bytes(4,'little')
            start=soc.IMAGES[name]['symbols']['__am_asm_trap']-0x20000000
            matches=[i for i in range(start,len(blob)-3,4) if blob[i:i+4]==restore]
            assert len(matches)==1,matches
            blob[matches[0]:matches[0]+4]=(0x13).to_bytes(4,'little')
            bad=OUT/'missing-t0-restore.bin';bad.write_bytes(blob)
            soc.simulate('context-negative',bad,expected='ebreak with nonzero a0',max_cycles=2000000)
    rtt=soc.ROOT/'rt-thread-am'
    soc.run('rtthread-bsp-check',['git','-C',rtt,'apply','--reverse','--check',FIX/'rtthread-bsp.patch'])
    sources=[FIX/'rtthread-tick.c',rtt/'bsp/abstract-machine/src/context.c',
             rtt/'bsp/abstract-machine/src/interrupt.c']
    sources += [rtt/f'src/{n}.c' for n in
                ['clock','idle','irq','kservice','mem','object','scheduler_up','thread','timer']]
    image=soc.build('rtthread-tick',sources,'flash-psram',
        f'INC_PATH += {rtt}/include {soc.NPC}/tests/b1-rtthread/include\nCFLAGS += -D__RTTHREAD__ -Wno-nonnull-compare')
    s=soc.simulate('rtthread-tick',image,'flash-psram',uart=b'RTT TICK PASS\n',
                   max_cycles=100000000,thread_stacks=True)
    assert s['interrupts']==s['diff_interrupts'] and s['interrupts']>=3,s
    exe=unit.cpp('latency-cpu','axi4_cpu_test_top',
        ['-F','filelist-soc.f','tests/axi4_cpu_test_top.sv'],'axi4_cpu_tb.cpp',flags=['--trace-fst'])
    img=unit.compile_image('latency',FIX/'latency.S')
    for seed in range(1,11):
        name=f'latency-{seed}'
        text=unit.run(name,[exe,img,OUT/f'{name}.trace',seed,3,
                           *([OUT/'latency-1.fst'] if seed==1 else [])])
        assert ' writes=200 data_reads=200 ' in text,text
        rows=[line.split() for line in (OUT/f'{name}.trace').read_text().splitlines()]
        stores=[r for r in rows if int(r[9],16) and int(r[10],16) and int(r[11],16)==0x80010000]
        assert len(stores)==200,(seed,len(stores))
    (OUT/'results.json').write_text(json.dumps(dict(results=unit.RESULTS+soc.RESULTS,
        images=soc.IMAGES),indent=2)+'\n')
    print(f'S5: PASS; evidence: {OUT}')

if __name__=='__main__':main()
