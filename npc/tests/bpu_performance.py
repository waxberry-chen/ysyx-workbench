#!/usr/bin/env python3
"""Same six frozen M5 images, same RTL/harness, OFF/JAL_ONLY/GSHARE comparison."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
NPC=ROOT/'npc'
OUT=NPC/'build/gshare-bpu/performance'
INPUT=ROOT/'docs/notes/post-c/5-ysyx-soc-integration/s8-validation/comparison-inputs.json'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def architectural_trace(p):
    # Strip only event time; PC/inst/a0/exception/memory observations must agree.
    return [line.partition(',')[2] for line in p.read_text().splitlines()]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,CCACHE_DIR=str(OUT/'ccache'),CCACHE_TEMPDIR=str(OUT/'ccache-tmp'))
    Path(env['CCACHE_TEMPDIR']).mkdir(exist_ok=True)
    spec=json.loads(INPUT.read_text());results={};commands=[]
    def run(name,cmd):
        cmd=list(map(str,cmd));commands.append(cmd)
        with (OUT/(name+'.log')).open('w') as log:
            subprocess.run(cmd,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
    for mode in range(3):
        binaries={}
        for boot in ['mrom','flash']:
            build=NPC/('build/ysyxsoc'+('-flash' if boot=='flash' else '')) if mode==2 else NPC/f'build/gshare-bpu/mode{mode}-{boot}'
            if args.build:run(f'build-{mode}-{boot}',['make','-C',NPC,'soc-build',f'SOC_BOOT={boot}',f'BPU_MODE={mode}',f'SOC_BUILD={build}'])
            binaries[boot]=build/'VysyxSoCFull'
        for name,p in spec['programs'].items():
            key=f'{mode}-{name}';boot='mrom' if p['profile']=='mrom' else 'flash'
            image=ROOT/p['binary'];assert sha(image)==p['binary_sha256']
            ref=ROOT/'nemu/build/ysyxsoc/nemu-ref.so'
            run(key,[binaries[boot],'--'+boot,image,'--diff',ref,'--max-cycles','300000000',
                     '--summary',OUT/(key+'.json'),'--uart-log',OUT/(key+'.uart'),'--commit-trace',OUT/(key+'.csv')])
            s=json.loads((OUT/(key+'.json')).read_text());b=s['bpu']
            assert s['pass'] and s['commits']==s['diff_steps']==p['commits'] and s['diff_sram_checks']==s['diff_psram_checks']==1
            assert b['mode']==mode and b['covered']==(b['branches'] if mode==2 else 0)
            assert b['trained']==b['covered']
            # Count instructions independently of the DUT's op_is_branch flag;
            # a missed decode must not silently shrink the accuracy denominator.
            with (OUT/(key+'.csv')).open() as trace:
                branches=sum((int(r[2],16)&127)==0x63 and not (int(r[4],16)&1)
                             for r in csv.reader(trace))
            assert b['branches']==branches==sum(b['directions'])
            assert b['direction_wrong']==b['directions'][1]+b['directions'][2]
            assert b['redirects'][7]==0
            if mode==0:
                assert s['cycles']==p['cycles'],(key,'legacy cycle mismatch',s['cycles'],p['cycles'])
                legacy=NPC/'build/gshare-bpu/legacy'/(name+'.csv')
                if legacy.exists():assert architectural_trace(legacy)==architectural_trace(OUT/(key+'.csv'))
            else: assert architectural_trace(OUT/('0-'+name+'.csv'))==architectural_trace(OUT/(key+'.csv')),(key,'commit sequence mismatch')
            results[key]=dict(summary=s,image_sha256=sha(image),executable_sha256=sha(binaries[boot]),reference_sha256=sha(ref),trace_sha256=sha(OUT/(key+'.csv')))
            print(f'{key}: PASS cycles={s["cycles"]} branch={b["branches"]} wrong={b["direction_wrong"]}',flush=True)
    sources={str(p.relative_to(ROOT)):sha(p) for folder in ('npc/vsrc','npc/csrc/soc','npc/sim') for p in (ROOT/folder).rglob('*') if p.is_file()}
    (OUT/'results.json').write_text(json.dumps(dict(results=results,commands=commands,source_sha256=sources,input_sha256=sha(INPUT)),indent=2)+'\n')
if __name__=='__main__':main()
