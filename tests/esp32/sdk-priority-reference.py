#!/usr/bin/env python3
"""Independent graph-based scheduling oracle; runs canonical firmware policy natively."""
import argparse, hashlib, itertools, json, os, random, re, struct, subprocess
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','work','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
randomizer=random.Random(0x32534B44);cases=[];forever=0x7fffffffffffffff
def task(priority=0,state=1,deadline=0,kind=0,word=0,tokens=0,count=0,bits=0,all_bits=0,present=1):
    return [priority,state,deadline,kind,word,tokens,count,bits,all_bits,present]
def add(rows,current=0,now=100):cases.append((rows,current,now))
for priorities in itertools.product((0,1,12,24),repeat=3):
    for current in range(3):add([task(x) for x in priorities],current)
for kind in range(1,6):
    for deadline in (99,100,101,forever):
        for present in (0,1):
            for word,tokens,count,bits,all_bits in itertools.product((0,1,3),(0,1),(0,1,3),(1,3),(0,1)):
                add([task(24,3,deadline,kind,word,tokens,count,bits,all_bits,present),task(1)])
# Three-hop priority donation, release, deleted owner/waiter and cyclic waits.
add([task(1),task(2,3,forever,2,0),task(3,3,forever,2,1),task(24,3,forever,2,2),task(12)])
add([task(1),task(24,3,forever,2,-1),task(12)])
add([task(1,2),task(24,3,forever,2,0),task(12)])
add([task(1),task(24,2,forever,2,0),task(12)])
add([task(1,3,forever,2,1),task(24,3,forever,2,0),task(12)])
for _ in range(1800):
    count=randomizer.randrange(1,9);rows=[]
    for i in range(count):
        rows.append(task(randomizer.randrange(25),randomizer.choice((1,1,2,3,3)),randomizer.choice((0,99,100,101,forever)),randomizer.randrange(6),randomizer.randrange(-1,count+1),randomizer.randrange(3),randomizer.randrange(4),randomizer.randrange(1,8),randomizer.randrange(2),randomizer.randrange(2)))
    add(rows,randomizer.randrange(count))

def expected(rows,current,now):
    def ready(row):
        priority,state,deadline,kind,word,tokens,count,bits,all_bits,present=row
        if state==1:return int(deadline<=now)
        if state!=3:return 0
        if deadline<=now:return 1
        if not present:return 0
        return int({1:tokens>0,2:word<0,3:count>0,4:count<word,5:(word&bits)==bits if all_bits else bool(word&bits)}.get(kind,False))
    # A donor reaches an owner through the wait-for graph. Compute reachability
    # independently of the firmware's bounded relaxation passes.
    effective=[row[0] for row in rows]
    for donor,row in enumerate(rows):
        seen=set();node=donor
        while node not in seen:
            seen.add(node);r=rows[node]
            if not (r[1]==3 and r[3]==2 and r[2]>now and r[9]):break
            owner=r[4]
            if owner<0 or owner>=len(rows) or rows[owner][1]==2:break
            effective[owner]=max(effective[owner],row[0]);node=owner
    eligible=[i for i in [(current+1+j)%len(rows) for j in range(len(rows))] if ready(rows[i])]
    chosen=max(eligible,key=lambda i:effective[i]) if eligible else -1
    return chosen,effective,[ready(row) for row in rows]

words=[len(cases)]
for rows,current,now in cases:
    chosen,effective,ready=expected(rows,current,now);words.extend((len(rows),current,now,chosen))
    for i,row in enumerate(rows):words.extend((*row,effective[i],ready[i]))
vectors=work/'reference.bin';vectors.write_bytes(struct.pack('<'+'q'*len(words),*words));compiler=a.compiler.resolve();fixture=root/'tests/esp32/sdk-priority-policy.flex';binary=work/'policy'
def run(cmd):return subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,timeout=90)
q=run([compiler,fixture,'-o',binary]);assert q.returncode==0,q.stderr.decode();q=run([binary,vectors]);assert q.returncode==0,(q.stdout,q.stderr)
print(q.stdout.decode().strip(),flush=True);match=re.fullmatch(rb'Priority policy: (\d+) checks across (\d+) independent cases\n',q.stdout);assert match and int(match[2])==len(cases)
module=root/'lib/platform/esp32-sdk-task-select.flex';original=module.read_text()
mutations=[
 ('priority-ignored','load64(t+624)>priority','!best'),
 ('lower-priority-first','load64(t+624)>priority','(!best || load64(t+624)<priority)'),
 ('peer-rotation-lost','t=load64(current+536);','t=current;'),
 ('delayed-ready','return deadline<=now;','return 1;'),
 ('deleted-task-ready','if state!=3 {return 0;}','if state!=3 {return 1;}'),
 ('deadline-boundary','if deadline<=now {return 1;}','if deadline<now {return 1;}'),
 ('event-all-ignored','return match==bits;','return match!=0;'),
 ('send-full-ready','return load64(object+24)<load64(object);','return 1;'),
 ('inheritance-disabled','while changed && pass<count','while 0'),
 ('chained-inheritance-disabled','while changed && pass<count','while changed && pass<1'),
 ('deleted-waiter-donates','load64(t+544)==3 &&','load64(t+544)!=1 &&'),
 ('inheritance-never-drops','store64(t+slot,load64(t+552));','if !load64(t+slot) {store64(t+slot,load64(t+552));}'),
]
controls=[]
for label,before,after in mutations:
    assert before in original,label;dest=work/label;dest.mkdir(exist_ok=True);changed=dest/'policy.flex';changed.write_text(original.replace(before,after,1));source=dest/'test.flex'
    text=fixture.read_text().replace('"../../lib/platform/esp32-sdk-task-select.flex"',json.dumps(str(changed))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));source.write_text(text);exe=dest/'test'
    q=run([compiler,source,'-o',exe]);assert q.returncode==0,(label,q.stderr)
    q=run([exe,vectors]);assert q.returncode==1 and b'Priority policy case ' in q.stderr,(label,q.returncode,q.stdout,q.stderr)
    controls.append({'name':label,'detected':True,'diagnostic':q.stderr.decode().strip()});print('Priority control:',label,'detected',flush=True)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
a.report.write_text(json.dumps({'pass':True,'cases':len(cases),'checks':int(match[1]),'controls':controls,'compiler_sha256':sha(compiler),'vectors_sha256':sha(vectors),'source_sha256':{str(x.relative_to(root)):sha(x) for x in [module,fixture,Path(__file__)]},'physical_hardware':False,'limits':'Native selection-policy oracle. Actual context switching, blocking/IRQ wakeups and synchronization integration require the separate emitted-firmware suite. This native test does not execute timer-driven preemption; the separate emitted-firmware suite covers it.'},indent=2)+'\n')
