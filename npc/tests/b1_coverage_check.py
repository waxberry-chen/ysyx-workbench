#!/usr/bin/env python3
"""Assert required legal bins. Missing stimulation is a failure, never an N/A."""
from pathlib import Path
import csv,json,itertools
R=Path(__file__).resolve().parents[2]; B=R/'npc/build'; out=B/'b1-closure';out.mkdir(exist_ok=True)
fabric={r['bin']:int(r['hits']) for r in csv.DictReader((B/'b1-fabric-test/coverage.csv').open())}
required={}
def need(group,bins):
 required[group]=list(bins)
 missing=[b for b in required[group] if fabric.get(b,0)<=0]
 assert not missing,(group,missing)
need('C01',[f'channel_delay/{p}/{n}' for p in range(5) for n in [0,1,7,64,129]]+
 [f'hold/{wr}/{n}' for wr in range(2) for n in [0,1,7,64,129]])
need('C02',[f'rr/{o}/{w}' for o in range(2) for w in range(2)])
need('C03',[f'order/{side}/{order}' for side in ['up','down'] for order in [-1,0,1]]+
 [f'publish/{order}/{gap}' for order in [-1,1] for gap in [1,7,64,129]]+['publish/0/0']+
 [f'gap/up/{gap}' for gap in [0,1,7,64,129]])
need('C04',[f'transition/{prev}/{w}/{o}' for prev in range(2) for o in range(2) for w in range(o+1)])
cross=[]
for owner in range(2):
 for wr in range(owner+1):
  for route in range(4):
   responses=[3] if route==3 else [2] if route==1 and not wr or route==2 and (wr or owner==0) else [0,2]
   for resp in responses:cross.append(f'cross/{owner}/{wr}/{route}/{resp}')
need('C05+C06',cross)
need('C07',[f'mask/{e}/{s}' for e in range(2) for s in range(16)])
need('C08',['reset/idle']+[f'reset/{r}/{p}' for r in range(4) for p in range(12)]+
 [f'reset_ifu/{r}/{p}' for r in range(4) for p in [0,1,6,9,10]])
need('C09',[f'uart/1/1/{s}/{0 if s in (0,1) else 2}' for s in range(16)])
need('C10',['rollover/retry']+[f'clint/{o}/0/{half}/{0 if o else 2}' for o in range(2) for half in [0,4]])
need('T13 seeds',[f'seed/{s}' for s in range(1,11)])
assert all(fabric[f'seed/{s}']>=1000 for s in range(1,11))
redirect=list(csv.DictReader((B/'b1-redirect-test/coverage.csv').open()))
assert {(int(r['phase']),int(r['rresp']),int(r['competitor'])) for r in redirect if int(r['hits'])>0}==set(itertools.product(range(3),[0,2,3],range(2)))
system=list(csv.DictReader((B/'b1-system-test-1048576-1000000/results.csv').open()))
closure=list(csv.DictReader((out/'results.csv').open()))
assert len(system)==53 and all(r['status']=='PASS' for r in system)
assert sum(int(r['exceptions'])==1 for r in system)==14
assert len(closure)==23 and all(r['status']=='PASS' for r in closure)
assert next(int(r['exceptions']) for r in system if r['name']=='yield-os')==201
assert all(int(r['exceptions'])>=201 for r in closure if r['name'].startswith('rtthread-'))
for prog in ['add','bubble-sort']:
 ref=next(r['architecture_sha256'] for r in system if r['name']==prog)
 rows=[r for r in closure if r['name'].startswith(prog+'-seed')]
 assert {int(r['seed']) for r in rows}==set(range(1,11)) and all(r['architecture_sha256']==ref for r in rows)
(out/'required-bins.json').write_text(json.dumps(required,indent=2)+'\n')
with (out/'coverage-summary.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['group','required_bins','hit_bins','status'])
 for k,v in required.items():w.writerow([k,len(v),len(v),'PASS'])
 w.writerow(['C11 precise faults',14,14,'PASS']);w.writerow(['C12 redirect',18,18,'PASS']);w.writerow(['C13 S4 system programs',53,53,'PASS']);w.writerow(['C13 S5 system programs',23,23,'PASS'])
with (out/'coverage-exclusions.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['bin','status','reason'])
 for name,reason in [('IFU write','IFU interface has no AW/W/B'),('EXOKAY production','AXI4-Lite devices produce OKAY/SLVERR/DECERR only'),('UART read OKAY','UART is write-only'),('CLINT write OKAY','mtime registers are read-only'),('IFU MMIO OKAY','instruction-tagged MMIO reads are rejected'),('default OKAY/SLVERR','unmapped region always returns DECERR')]:w.writerow([name,'N/A',reason])
print('Required coverage PASS; C01-C13 legal bins checked; exclusions explicit')
