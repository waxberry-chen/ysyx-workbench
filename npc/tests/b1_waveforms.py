#!/usr/bin/env python3
"""Render three engineering timing diagrams from actual VCD transitions."""
from pathlib import Path
from html import escape
import hashlib,json,sys
src=Path(sys.argv[1]);dest=Path(sys.argv[2]);dest.mkdir(parents=True,exist_ok=True)
scope=[];names={};hist={};time=0
for line in src.read_text().splitlines():
 a=line.split()
 if not a:continue
 if a[0]=='$scope':scope.append(a[2])
 elif a[0]=='$upscope':scope.pop()
 elif a[0]=='$var':names['.'.join(scope+[a[4]])]=(a[3],int(a[2]));hist.setdefault(a[3],[])
 elif line.startswith('#'):time=int(line[1:])/2
 elif line.startswith('b'):
  value,code=line[1:].split()
  if set(value)<=set('01'):hist[code].append((time,int(value,2)))
 elif line[0] in '01':hist[line[1:]].append((time,int(line[0])))
cases=[('competition','IFU / LSU competition',7,24,['ifu_axi_arvalid','ifu_axi_arready','lsu_axi_wvalid','lsu_axi_wready','ifu_axi_rvalid','ifu_axi_rready']),
 ('w-first','W-first write, then B backpressure',21,50,['lsu_axi_wvalid','lsu_axi_wready','lsu_axi_awvalid','lsu_axi_awready','lsu_axi_bvalid','lsu_axi_bready']),
 ('decerr','Unmapped fetch returns DECERR',57,74,['ifu_axi_arvalid','ifu_axi_araddr','monitor_ar','monitor_r','ifu_axi_rvalid','ifu_axi_rready','ifu_axi_rresp'])]
index=[]
for name,title,start,end,signals in cases:
 height=105+40*len(signals);x=lambda t:235+(t-start)*830/(end-start)
 svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="{height}" viewBox="0 0 1100 {height}">',
 '<rect width="100%" height="100%" fill="white"/>',f'<text x="20" y="26" font-family="sans-serif" font-size="19" fill="#152c48">{escape(title)}</text>',
 '<text x="20" y="48" font-family="sans-serif" font-size="12">Source: representative.vcd; cycles are simulation clock periods, not measured physical time.</text>']
 for t in range(start,end+1):
  if (t-start)%2:continue
  svg += [f'<path d="M{x(t):.2f} 65 V{height-32}" stroke="#e0e6ee"/>',f'<text x="{x(t):.2f}" y="{height-12}" text-anchor="middle" font-family="monospace" font-size="11">{t}</text>']
 for row,n in enumerate(signals):
  code,width=names['TOP.'+n];changes=hist[code];y=78+40*row
  v=next((v for t,v in reversed(changes) if t<=start),0)
  points=[(start,v)]+[(t,v) for t,v in changes if start<t<end]+[(end,None)]
  svg.append(f'<text x="20" y="{y+7}" font-family="monospace" font-size="14">{n}</text>')
  prev_y=None
  for (t,v),(next_t,_) in zip(points,points[1:]):
   left,right=x(t),x(next_t)
   if width==1:
    level=y-9 if v else y+9
    path=f'M{left:.2f} {level} H{right:.2f}'
    if prev_y is not None:path+=f' M{left:.2f} {prev_y} V{level}'
    svg.append(f'<path d="{path}" fill="none" stroke="#0967a0" stroke-width="2"/>');prev_y=level
   else:
    svg.append(f'<rect x="{left:.2f}" y="{y-12}" width="{right-left:.2f}" height="24" fill="#edf7ff" stroke="#0967a0"/>')
    if right-left>26:svg.append(f'<text x="{(left+right)/2:.2f}" y="{y+5}" text-anchor="middle" font-family="monospace" font-size="12">0x{v:x}</text>')
 svg.append('</svg>');(dest/f'{name}.svg').write_text('\n'.join(svg)+'\n')
 index.append(dict(file=f'{name}.svg',start_cycle=start,end_cycle=end,signals=signals))
(dest/'index.json').write_text(json.dumps(dict(source=str(src),source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),timescale='2 VCD ticks per clock; display uses cycles',views=index),indent=2)+'\n')
print('Rendered 3 VCD timing diagrams')
