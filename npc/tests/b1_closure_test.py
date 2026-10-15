#!/usr/bin/env python3
"""S5 finite RT-Thread + 20 reproducible random-timing Core runs."""
from pathlib import Path
import csv,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'npc/build/b1-closure';OUT.mkdir(parents=True,exist_ok=True)
base=ROOT/'npc/build/b1-1048576-1000000/Vysyx_b1_top'
shim=ROOT/'npc/build/b1-1048576-1000000-shim/Vysyx_b1_top'
ref=ROOT/'nemu/build/riscv32-nemu-interpreter-so'
commands=[];results=[]
def execute(name,argv,extra=None):
 env=dict(os.environ,AM_HOME=str(ROOT/'abstract-machine'),NPC_HOME=str(ROOT/'npc'),NEMU_HOME=str(ROOT/'nemu'))
 env.update(extra or {});start=time.monotonic()
 p=subprocess.run(list(map(str,argv)),cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 elapsed=time.monotonic()-start;(OUT/f'{name}.log').write_bytes(p.stdout)
 commands.append(dict(name=name,argv=list(map(str,argv)),environment=extra or {},exit=p.returncode,wall_seconds=elapsed))
 (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 assert p.returncode==0,(name,p.returncode,p.stdout[-1500:].decode(errors='replace'))
 return p.stdout.decode(errors='replace'),elapsed
baseline={r['name']:r for r in csv.DictReader((ROOT/'npc/build/b1-system-test-1048576-1000000/results.csv').open())}
def run(name,binary,image,seed=0,uart=b'',architecture=None,rtthread=False):
 trace=OUT/f'{name}.trace';uartfile=OUT/f'{name}.uart'
 log,elapsed=execute(name,[binary,'-b','-d',ref,f'--commit-trace={trace}',image],
  {'NPC_SHIM_SEED':str(seed),'NPC_UART_LOG':str(uartfile),'NPC_MAX_CYCLES':'50000000'})
 assert 'HIT GOOD TRAP' in log and 'Differential testing:' in log,name
 assert uartfile.read_bytes()==uart,name+' UART'
 rows=[l.split() for l in trace.read_text().splitlines() if not l.startswith('#')]
 faults=[r for r in rows if r[5]=='1']
 assert (len(faults)>=201 and all(int(r[6],16)==11 for r in faults)) if rtthread else not faults,name
 digest=hashlib.sha256(''.join(' '.join(r[:5])+'\n' for r in rows).encode()).hexdigest()
 if architecture: assert digest==architecture,(name,'architecture hash')
 cycles=int(re.search(r'cycles\s+= (\d+)',log).group(1))
 results.append(dict(name=name,seed=seed,commits=len(rows),cycles=cycles,exceptions=len(faults),wall_seconds=elapsed,
  image=str(image),image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(),architecture_sha256=digest,status='PASS'))
 with (OUT/'results.csv').open('w') as f:
  w=csv.DictWriter(f,fieldnames=results[0]);w.writeheader();w.writerows(results)
 print(f'{name} PASS commits={len(rows)} cycles={cycles}',flush=True)
for name in ['add','bubble-sort']:
 image=Path(baseline[name]['image'])
 for seed in range(1,11):run(f'{name}-seed{seed}',shim,image,seed,architecture=baseline[name]['architecture_sha256'])
args=['ARCH=riscv32e-npc','NPC_PLATFORM=b1','SRAM_BYTES=1048576','MTIME_HZ=1000000']
execute('rtthread-build',['make','-C',ROOT/'npc/tests/b1-rtthread',*args,'insert-arg'])
image=ROOT/'npc/tests/b1-rtthread/build/b1-rtthread-riscv32e-npc-b1-1048576-1000000.bin'
expected=b'RTTHREAD BEGIN cooperative\n'+b'AB'*100+b'\nRTTHREAD PASS iterations=100,100 heap_restored=1\n'
run('rtthread-fixed',base,image,uart=expected,rtthread=True)
run('rtthread-shim-seed42',shim,image,42,uart=expected,rtthread=True,architecture=results[-1]['architecture_sha256'])
# Save an immutable copy, then restore the primary hello image to S4 arguments.
execute('hello-empty-build',['make','-C',ROOT/'am-kernels/kernels/hello',*args,'mainargs=','insert-arg'])
image=OUT/'hello-empty.bin';image.write_bytes((ROOT/'am-kernels/kernels/hello/build/hello-riscv32e-npc-b1-1048576-1000000.bin').read_bytes())
run('hello-empty',base,image,uart=b"Hello, AbstractMachine!\nmainargs = ''.\n")
execute('hello-restore',['make','-C',ROOT/'am-kernels/kernels/hello',*args,'mainargs=I-love-ysyx','insert-arg'])
print('S5 system closure: 23 PASS',flush=True)
