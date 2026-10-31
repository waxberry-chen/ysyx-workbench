#!/usr/bin/env python3
"""Predictor/response-queue scoreboards. No SoC or software build required."""
import json
import os
import resource
from pathlib import Path
import subprocess

NPC=Path(__file__).resolve().parents[1]
OUT=NPC/'build/gshare-bpu/unit'
FLAGS=['verilator','--cc','--exe','--build','-j','2','--sv','--assert','-Wall','-Wno-fatal',
       '-Wno-SYNCASYNCNET','-Werror-WIDTH','-Werror-PINMISSING','-Werror-PINNOTFOUND','-Werror-LATCH','-Werror-UNOPTFLAT']

def main():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    OUT.mkdir(parents=True,exist_ok=True)
    # Cache is disposable, local to this run; no dependency on user cache paths.
    env=dict(os.environ,CCACHE_DIR=str(OUT/'ccache'),CCACHE_TEMPDIR=str(OUT/'ccache-tmp'))
    Path(env['CCACHE_TEMPDIR']).mkdir(exist_ok=True)
    results=[]
    def run(name,cmd,expected=None):
        p=subprocess.run(list(map(str,cmd)),cwd=NPC,env=env,capture_output=True,text=True,timeout=240)
        text=p.stdout+p.stderr;(OUT/(name+'.log')).write_text(text)
        assert (p.returncode!=0 and expected in text) if expected else p.returncode==0,(name,text[-4000:])
        results.append(dict(name=name,command=list(map(str,cmd)),expected_failure=expected,status='PASS'))
        print(name+': PASS',flush=True)
    for name,top,src,tb,flags in [
        ('predecode','ysyx_predecode',['vsrc/core/ysyx_predecode.sv'],'predecode.cpp',[]),
        ('gshare7','ysyx_gshare',['vsrc/core/ysyx_gshare.sv'],'predictor.cpp',[]),
        ('gshare3','ysyx_gshare',['vsrc/core/ysyx_gshare.sv'],'predictor.cpp',['-GINDEX_BITS=3','-CFLAGS','-DINDEX_BITS=3']),
        ('ifu','ysyx_ifu',['vsrc/core/ysyx_ifu.sv','vsrc/core/ysyx_predecode.sv','vsrc/core/ysyx_gshare.sv','vsrc/gnrl/ysyx_gnrl_primitive.sv'],'ifu.cpp',[])]:
        exe=OUT/name/f'V{top}'
        run(name+'-build',[*FLAGS,'--top-module',top,'--Mdir',exe.parent,*flags,*src,NPC/'tests/bpu'/tb])
        run(name,[exe])
        if name=='ifu':run('metadata-negative',[exe,'corrupt-metadata'],expected='IFU_SCOREBOARD: prediction metadata mismatch')
    exu_sources=['vsrc/gnrl/ysyx_gnrl_primitive.sv','vsrc/core/ysyx_alu.sv','vsrc/core/ysyx_branch.sv']
    for mutant in (False,True):
        name='recovery-negative' if mutant else 'recovery'
        source=NPC/'vsrc/core/ysyx_exu.sv'
        if mutant:
            text=source.read_text();assert 'commit_npc != op_pred_npc' in text
            source=OUT/'ysyx_exu_no_recovery.sv'
            source.write_text(text.replace('commit_npc != op_pred_npc', "1'b0"))
        exe=OUT/name/'Vysyx_exu_tb'
        run(name+'-build',['verilator','--binary','--timing','--sv','--assert','-Wall','-Wno-fatal',
            '-Werror-WIDTH','--top-module','ysyx_exu_tb','-GBPU_MODE=2','--Mdir',exe.parent,
            *exu_sources,source,'tests/ysyx_exu_tb.sv'])
        run(name,[exe],expected='EXU test failed:' if mutant else None)
    (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n')

if __name__=='__main__':main()
