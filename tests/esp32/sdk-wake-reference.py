#!/usr/bin/env python3
"""Independent reachability oracle for the bounded, clock-free vendor wake hint."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import re
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
for name in ['compiler','work','report']:p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);rng=random.Random(0x42545741);cases=[]

def add(rows,current=0,target=1,kind=1):cases.append((rows,current,target,kind))
# Row: base priority, state, deadline, wait kind, mutex owner index, reserved.
def task(p=0,s=1,d=0,k=0,o=-1):return [p,s,d,k,o,0]
for current,waiter,kind,state,deadline in itertools.product([0,5,24],[0,5,24],[0,1,2,3,4,5],[1,2,3],[0,1,99,2**63-1]):
    add([task(current),task(waiter,state,deadline,kind)],kind=kind)
add([task(12),task(2,3,999,1),task(3,3,999,2,1),task(24,3,999,2,2)])
# A timed-out donation is still a possible hint; exact IRQ-tail selection uses time.
add([task(10),task(1,3,1,1),task(24,3,1,2,1)])
# Current inherited priority must not suppress a conservative request.
add([task(1),task(10,3,999,1),task(24,3,999,2,0)])
add([task(1),task(1,3,999,1),task(24,2,999,2,1)])
for _ in range(4000):
    n=rng.randrange(1,9);rows=[task(rng.randrange(25),rng.choice([1,2,3]),rng.choice([0,1,99,2**63-1]),rng.randrange(6),rng.randrange(-2,n)) for _ in range(n)]
    add(rows,rng.randrange(n),rng.randrange(n),rng.randrange(6))

def oracle(rows,current,target,kind):
    if kind not in (1,3,4) or target==current:return 0
    row=rows[target]
    if row[1]!=3 or row[3]!=kind:return 0
    # Independently walk each donor's wait-for path, rather than relaxing edges.
    maximum=row[0]
    for donor,r in enumerate(rows):
        seen=set();node=donor
        while node not in seen:
            seen.add(node);q=rows[node]
            if q[1]!=3 or q[3]!=2 or q[2]<=0:break
            node=q[4]
            if not 0<=node<len(rows) or rows[node][1]==2:break
            if node==target:maximum=max(maximum,r[0])
    return int(maximum>rows[current][0])
words=[len(cases)]
for rows,current,target,kind in cases:
    words.extend([len(rows),current,target,kind,oracle(rows,current,target,kind)])
    for row in rows:words.extend(row)
vectors=w/'vectors.bin';vectors.write_bytes(struct.pack('<'+'q'*len(words),*words))
module=ROOT/'lib/platform/esp32-sdk-task-select.flex';fixture=ROOT/'tests/esp32/sdk-wake-policy.flex';text=module.read_text();env=os.environ.copy();env.setdefault('TMPDIR',str(w))
def run(args):return subprocess.run([str(x) for x in args],cwd=ROOT,env=env,capture_output=True,timeout=45)
binary=w/'positive';q=run([a.compiler,fixture,'-o',binary]);assert q.returncode==0,q.stderr;q=run([binary,vectors]);assert q.returncode==0,(q.stdout,q.stderr);match=re.fullmatch(rb'Wake hint: (\d+) checks\n',q.stdout);assert match;print(q.stdout.decode().strip(),flush=True)
mutations=[('equal-priority','load64(task+632)>priority','load64(task+632)>=priority'),('wrong-object','load64(task+600)==object &&',''),('wrong-wait-kind','load64(task+592)==kind &&',''),('ready-or-deleted-woken','load64(task+544)==3 &&',''),('no-inheritance','esp_sdk_task_priorities(current,0,632);',''),('one-pass-inheritance','while changed && pass<count','while changed && pass<1'),('effective-state-corruption','esp_sdk_task_priorities(current,0,632);','esp_sdk_task_priorities(current,0,624);'),('current-inheritance-suppresses','let priority=load64(current+552);','let priority=load64(current+632);'),('expired-upper-bound-lost','esp_sdk_task_priorities(current,0,632);','esp_sdk_task_priorities(current,100,632);')]
results=[]
for label,before,after in mutations:
    assert before in text,label;d=w/label;d.mkdir(exist_ok=True);m=d/'policy.flex';m.write_text(text.replace(before,after,1));src=d/'test.flex';src.write_text(fixture.read_text().replace('"../../lib/platform/esp32-sdk-task-select.flex"',json.dumps(str(m))).replace('"../../scripts/lib/host.flex"',json.dumps(str(ROOT/'scripts/lib/host.flex'))));exe=d/'test';q=run([a.compiler,src,'-o',exe]);assert q.returncode==0,(label,q.stderr);q=run([exe,vectors]);assert q.returncode==1 and b'wake hint reference mismatch' in q.stderr,(label,q.returncode,q.stdout,q.stderr);results.append(dict(name=label,detected=True));print('Wake control:',label,'detected',flush=True)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
a.report.write_text(json.dumps(dict(pass_all=True,cases=len(cases),checks=int(match[1]),controls=results,source_sha256={str(x.relative_to(ROOT)):sha(x) for x in [module,fixture,Path(__file__)]},compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors),physical_hardware=False),indent=2)+'\n')
