#!/usr/bin/env python3
"""Targeted wrong-path effects and applicable M5 system suites on fresh BPU RTL.

All M5 helper outputs are redirected to this run; old archived evidence stays
intact. --full expects make s6-build BPU_MODE=2 (four current system binaries).
"""
import argparse
import csv
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import m5_s4_test as soc

NPC=soc.NPC;OUT=NPC/'build/gshare-bpu/system'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--full',action='store_true');args=p.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE,(0,0));OUT.mkdir(parents=True,exist_ok=True)
    os.environ['CCACHE_DIR']=str(OUT/'ccache');os.environ['CCACHE_TEMPDIR']=str(OUT/'ccache-tmp')
    Path(os.environ['CCACHE_TEMPDIR']).mkdir(exist_ok=True)
    commands=[]
    def run(name,cmd):
        cmd=list(map(str,cmd));commands.append(cmd)
        with (OUT/(name+'.log')).open('w') as log:subprocess.run(cmd,cwd=NPC,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1800)
    for kind in range(5):
        elf=OUT/f'wrong-{kind}.elf';binary=elf.with_suffix('.bin')
        run(f'build-{kind}',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie','-march=rv32e_zicsr','-mabi=ilp32e',
            '-Wl,-Ttext=0x20000000','-Wl,--build-id=none','-Wl,--no-relax',f'-DWRONG_KIND={kind}',NPC/'tests/bpu/wrong-path.S','-o',elf])
        run(f'objcopy-{kind}',['riscv64-linux-gnu-objcopy','-O','binary',elf,binary])
        for mode in (0,2):
            name=f'wrong-{kind}-mode{mode}'
            exe=NPC/('build/ysyxsoc/VysyxSoCFull' if mode==2 else 'build/gshare-bpu/mode0-mrom/VysyxSoCFull')
            summary=OUT/(name+'.json')
            bus=OUT/(name+'.bus.csv')
            run(name,[exe,'--mrom',binary,'--diff',soc.REF,'--max-cycles',50000,'--summary',summary,
                      '--commit-trace',OUT/(name+'.csv'),'--bus-trace',bus])
            s=json.loads(summary.read_text());b=s['bpu']
            assert s['exceptions']==0 and s['diff_steps']==s['commits'] and s['diff_sram_checks']==1
            # Exactly 40 loop branches + victim + two software checks commit.
            assert b['branches']==43 and b['trained']==(43 if mode==2 else 0),b
            assert b['mode']==mode
            if mode==2:
                assert b['directions']==[2,8,2,31],b
                # Prove the victim's actual wrong target was requested; aggregate
                # direction counts alone could accidentally cover another PC.
                target=0x20001000 if kind==4 else 0x20000230
                active=None;requests=0;responses=[]
                for row in csv.reader(bus.open()):
                    flags=int(row[1])
                    if flags&1:
                        active=int(row[2],16);requests+=active==target
                    if flags&8:
                        if active==target:responses.append(int(row[9],16))
                        active=None
                assert requests==1 and len(responses)==1,(name,requests,responses)
                assert responses[0] in (2,3) if kind==4 else responses[0]==0
                assert s['aw']==s['w']==s['b']==1, 'wrong-path store side effect'
            print(name+': PASS',flush=True)
    # OFF must preserve precise IRQ/exception behavior as well as six-program
    # throughput. Reuse the independent software cause/EPC/mask expectations.
    elf=OUT/'irq.elf';binary=elf.with_suffix('.bin')
    run('irq-build',['riscv64-linux-gnu-gcc','-nostdlib','-static','-fno-pic','-no-pie',
        '-march=rv32e_zicsr','-mabi=ilp32e','-Wl,-Ttext=0x20000000','-Wl,--build-id=none',
        '-Wl,--no-relax',NPC/'tests/soc-timer/trap.S','-o',elf])
    run('irq-objcopy',['riscv64-linux-gnu-objcopy','-O','binary',elf,binary])
    for mode in (0,2):
        name=f'irq-mode{mode}'
        exe=NPC/('build/ysyxsoc/VysyxSoCFull' if mode==2 else 'build/gshare-bpu/mode0-mrom/VysyxSoCFull')
        run(name,[exe,'--mrom',binary,'--diff',soc.REF,'--max-cycles',20000,'--summary',OUT/(name+'.json')])
        s=json.loads((OUT/(name+'.json')).read_text());b=s['bpu']
        assert s['interrupts']==s['diff_interrupts']==2 and s['exceptions']==1
        assert b['mode']==mode and b['trained']==(b['branches'] if mode==2 else 0)
        print(name+': PASS',flush=True)
    (OUT/'targeted-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    if args.full:
        import m5_s3_test as s3
        import m5_s5_test as s5
        import m5_s6_test as s6
        # Each existing runner still performs its own assertions and negative cases.
        # S6 repeats applicable S1/ISA protocol; S3/4 cover boot/AM/poison explicitly.
        for name,module in [('s3',s3),('s4',soc),('s5',s5),('s6',s6)]:
            destination=OUT/name;destination.mkdir(exist_ok=True)
            # Helpers share modules in this process: do not carry old stage
            # result/image lists into the next stage's evidence manifest.
            import m5_s1_test as unit
            for helper in (s3,soc,unit,s6):
                for key in ('RESULTS','IMAGES','CPU_MATRIX','COMMANDS','WORKLOADS'):
                    value=getattr(helper,key,None)
                    if isinstance(value,(dict,list)):value.clear()
            module.OUT=destination
            print(name+': starting',flush=True)
            sys.argv=[module.__file__]
            module.main()
        print('BPU_SYSTEM full PASS',flush=True)
if __name__=='__main__':main()
