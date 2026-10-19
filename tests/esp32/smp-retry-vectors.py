#!/usr/bin/env python3
"""Independent SMP repeated-attempt admission and reboot checkpoint peer.

Normative source: Bluetooth Core 5.4, Vol3 PartH 2.3.6. The numeric bounds,
doubling/halving policy, leases and checkpoint format are local API contracts.
Only logical protocol milliseconds are modeled, with no emulator implementation.
"""
import argparse,copy,hashlib,json,random,struct
from pathlib import Path
MAX=2**63-1
def q(*x):return struct.pack('<'+'q'*len(x),*x)
def ident(n):return bytes([0,n,2,3,4,5,6])
def static(n):return bytes([1,n,2,3,4,5,0xc6])
def valid_id(v):return len(v)==7 and (v[0]==0 or (v[0]==1 and v[6]&192==192))
BUCKET=bytes([2,0,0,0,0,0,0])
def valid_key(v):return valid_id(v) or v==BUCKET
class Peer:
 def __init__(self):self.floor=0;self.now=0;self.initialized=False;self.entries=0;self.minimum=0;self.maximum=0;self.period=0;self.slots=[None]*4;self.codec=bytes([165])*224;self.raw=bytes([165])*384
 def clock(self,t):return 0<=self.now<=t<=MAX-self.maximum-self.period
 def age(self,r):
  if not r['interval'] or self.now<r['decay']:return
  periods=(self.now-r['decay'])//self.period+1
  for _ in range(min(64,periods)):
   r['interval']=0 if r['interval']<=self.minimum else max(self.minimum,r['interval']//2)
  r['decay']=self.now+self.period-(self.now-r['decay'])%self.period if r['interval'] else 0
 def left(self,r):return max(0,r['until']-self.now)
 def find(self,id):return next((r for r in self.slots[:self.entries] if r and r['id']==id),None)
 def grow(self,v):return min(self.maximum,v*2) if v else self.minimum
 def init(self,a,b,c,d,t,capacity=384):
  if self.initialized:return -16
  if not (1<=a<=4 and capacity>=128+a*64 and 1<=b<=3600000 and b<=c<=86400000 and 1<=d<=604800000 and 0<=t<=MAX-c-d):return -22
  self.initialized=True;self.entries=a;self.minimum=b;self.maximum=c;self.period=d;self.now=t;self.slots=[None]*4;self.raw=bytes(128+a*64)+self.raw[128+a*64:];return 0
 def command(self,op,a=0,b=0,c=0,d=0,t=0,data=b''):
  if op==1:return self.init(a,b,c,d,t)
  if op==7:
   floor=self.floor if data==b'keep' else 0;codec=self.codec;self.__init__();self.floor=floor;self.codec=codec;return self.init(a,b,c,d,t)
  if op==9:self.floor=a;return 0
  if op==11:v=bytearray(self.codec);v[a]=b;self.codec=bytes(v);return 0
  if op==8 and not self.initialized:return 0
  if not self.initialized:return -19
  if op in (2,3):
   if not valid_key(data) or not self.clock(t):return -22
   if op==3 and self.floor==MAX:return -75
   self.now=t;r=self.find(data)
   if r:
    self.age(r)
    if r['lease']:return -16
    if self.left(r):return self.left(r) if op==2 else -11
   if op==2:return 0
   if r is None:
    for i in range(self.entries):
     item=self.slots[i]
     if item:self.age(item)
     if item is None or (not item['lease'] and not item['interval'] and not self.left(item)):
      r=dict(id=data,interval=0,until=0,decay=0,lease=0);self.slots[i]=r;break
    else:return -105
   self.floor+=1;r['lease']=self.floor;return self.floor
  if op==4:
   if a<=0 or b not in (0,1) or not self.clock(t):return -22
   r=next((r for r in self.slots[:self.entries] if r and r['lease']==a),None)
   if r is None:return -116
   self.now=t;self.age(r)
   if b:r['interval']=self.grow(r['interval']);r['until']=t+r['interval'];r['decay']=t+self.period
   r['lease']=0;return 0
  if op==5:
   size=64+40*self.entries
   if a<size or not self.clock(t):return -22
   self.now=t;records=[]
   for r in self.slots[:self.entries]:
    if r:
     self.age(r)
     if r['interval'] or self.left(r) or r['lease']:records.append(r['id']+b'\0'+q(r['interval'],self.left(r),r['decay']-t if r['interval'] else 0,int(bool(r['lease']))))
   self.codec=b'SMPTRY01'+q(self.entries,self.minimum,self.maximum,self.period,self.floor,len(records),0)+b''.join(records)+bytes((self.entries-len(records))*40)+self.codec[size:];return size
  if op==6:
   blob=data if data else self.codec[:a]
   if a!=64+40*self.entries or len(blob)!=a or not self.clock(t):return -22
   if any(self.slots[:self.entries]):return -16
   e,lo,hi,period,floor,count,reserved=struct.unpack('<7q',blob[8:64])
   if blob[:8]!=b'SMPTRY01' or (e,lo,hi,period)!=(self.entries,self.minimum,self.maximum,self.period) or floor<0 or not 0<=count<=e or reserved:return -22
   if floor<self.floor:return -116
   records=[];seen=set()
   for i in range(count):
    r=blob[64+i*40:104+i*40];id=r[:7];delay,wait,decay,live=struct.unpack('<4q',r[8:])
    if not valid_key(id) or r[7] or not (delay==0 or self.minimum<=delay<=self.maximum) or not 0<=wait<=self.maximum or not 0<=decay<=self.period or bool(delay)!=bool(decay) or live not in (0,1) or (live and (wait or not floor)) or not (delay or wait or live) or id in seen:return -22
    seen.add(id);records.append(dict(id=id,interval=delay,until=t+wait,decay=t+decay if delay else 0,lease=0))
    if live:records[-1].update(interval=self.grow(delay),until=t+self.grow(delay),decay=t+self.period)
   if any(blob[64+count*40:]):return -22
   self.floor=floor;self.now=t;self.slots=records+[None]*(4-count);return 0
  if op==13:
   if len(data)!=14 or not valid_key(data[:7]) or not valid_key(data[7:]) or not self.clock(t):return -22
   source,target=data[:7],data[7:];origin=self.find(source);dest=self.find(target)
   if (origin and origin['lease']) or (dest and dest['lease']):return -16
   self.now=t
   if origin:self.age(origin)
   if dest is not None and dest is not origin:self.age(dest)
   if origin is None or origin is dest or not (origin['interval'] or self.left(origin)):return 0
   if dest is None:
    for i in range(self.entries):
     item=self.slots[i]
     if item:self.age(item)
     if item is None or (not item['lease'] and not item['interval'] and not self.left(item)):
      dest=dict(id=target,interval=0,until=0,decay=0,lease=0);self.slots[i]=dest;break
    else:return -105
   dest.update(interval=max(dest['interval'],origin['interval']),until=max(dest['until'],origin['until']),decay=max(dest['decay'],origin['decay']))
   if not dest['interval']:dest['decay']=0
   return 0
  if op==8:
   if not self.clock(t):return -22
   self.now=t
   for r in self.slots[:self.entries]:
    if r:
     self.age(r)
     if r['lease'] or r['interval'] or self.left(r):return -16
   self.raw=bytes(128+self.entries*64)+self.raw[128+self.entries*64:];self.slots=[None]*4;self.initialized=False;self.entries=0;self.minimum=0;self.maximum=0;self.period=0;self.now=0;return 0
  if op==10:return -22
  return -1000
 def observe(self,result):
  raw=self.raw
  if self.initialized:
   records=[]
   for r in self.slots[:self.entries]:records.append(q(1,r['interval'],r['until'],r['decay'],r['lease'])+r['id']+bytes(17) if r else bytes(64))
   size=128+64*self.entries;raw=bytes(128)+b''.join(records)+raw[size:]
  return q(result,int(self.initialized),self.entries,self.minimum,self.maximum,self.period,self.now,self.floor,0)+raw+self.codec+q(1)
class Case:
 def __init__(self,label):self.label=label;self.peer=Peer();self.commands=[];self.returns=[]
 def call(self,op,a=0,b=0,c=0,d=0,t=0,data=b''):
  result=self.peer.command(op,a,b,c,d,t,data);obs=self.peer.observe(result);assert len(obs)==688
  self.commands.append(q(op,a,b,c,d,t,len(data),0)+data+obs);self.returns.append(result);return result
 def boot(self,base=1000,cap=7000,decay=60000,t=0):self.call(1,4,base,cap,decay,t);return self
 def reboot(self,t=0,keep=False):self.call(7,4,self.peer.minimum,self.peer.maximum,self.peer.period,t,b'keep' if keep else b'')
 def encode(self):payload=b''.join(self.commands);return q(len(payload)+16,len(self.commands))+payload
def generate():
 cases=[]
 def case(label):c=Case(label);cases.append(c);return c
 c=case('exponential-capped-and-decreasing').boot();now=0
 for i in range(12):
  lease=c.call(3,t=now,data=ident(1));c.call(3,t=now,data=ident(1));c.call(4,lease,1,t=now);delay=c.call(2,t=now,data=ident(1));c.call(3,t=now+delay-1,data=ident(1));c.call(2,t=now+delay-1,data=ident(1));now+=delay;c.call(2,t=now,data=ident(1))
 for i in range(8):now+=60000;c.call(2,t=now,data=ident(1));c.call(5,224,t=now)
 c.call(8,t=now);c.call(1,4,1000,7000,60000,now);c.call(3,t=now,data=ident(1));c.call(4,1,1,t=now)
 for cap in (1000,1001,1999,2001,7000,12345,64000,86400000):
  c=case('odd-cap-roundtrip-'+str(cap)).boot(cap=cap,decay=123456789);now=0
  for _ in range(22):
   lease=c.call(3,t=now,data=static(1));c.call(4,lease,1,t=now);now+=c.call(2,t=now,data=static(1))
  now+=123456789;c.call(2,t=now,data=static(1));c.call(5,224,t=now);c.reboot();c.call(6,224);c.call(5,224);c.call(2,data=static(1))
 c=case('success-keeps-failed-history').boot();a=c.call(3,data=ident(1));c.call(4,a,1);a=c.call(3,t=1000,data=ident(1));c.call(4,a,0,t=1000);a=c.call(3,t=1000,data=ident(1));c.call(4,a,1,t=1000);c.call(2,t=1000,data=ident(1));c.call(5,224,t=1000)
 c=case('parallel-identities-capacity').boot()
 for i in range(1,5):c.call(3,data=ident(i))
 c.call(3,data=ident(5));c.call(2,data=ident(5));c.call(3,data=ident(1));c.call(8)
 for i in range(1,5):c.call(4,i,1)
 c.call(3,t=1000,data=ident(5));c.call(3,t=59999,data=ident(5));c.call(3,t=60000,data=ident(5));c.call(5,224,t=60000)
 c=case('checkpoint-live-attempt-is-failure').boot();c.call(3,data=ident(1));c.call(3,data=static(2));c.call(5,224,t=12);c.reboot();c.call(6,224);c.call(4,1,0);c.call(2,data=ident(1));c.call(3,t=999,data=ident(1));c.call(3,t=1000,data=ident(1));c.call(4,3,1,t=1000);c.call(5,224,t=1000)
 c=case('reboot-conservative-waits-and-stale-lease').boot();a=c.call(3,data=ident(1));c.call(4,a,1,t=20);c.call(5,224,t=500);c.reboot(t=5);c.call(6,224,t=5);c.call(2,t=5,data=ident(1));c.call(3,t=524,data=ident(1));c.call(3,t=525,data=ident(1));c.call(4,a,0,t=525);c.call(4,2,1,t=525);c.call(5,224,t=525)
 c=case('short-decay-never-shortens-existing-hold').boot(decay=1);a=c.call(3,data=ident(1));c.call(4,a,1);c.call(2,t=1,data=ident(1));c.call(5,224,t=1);c.reboot();c.call(6,224);c.call(2,data=ident(1));c.call(8);c.call(3,t=999,data=ident(1));c.call(4,2,1,t=999)
 c=case('large-clock-jump-and-ceiling').boot(t=MAX-7000-60000-1000);t=c.peer.now;a=c.call(3,t=t,data=ident(1));c.call(4,a,1,t=t);c.call(2,t=MAX-7000-60000,data=ident(1));c.call(2,t=MAX-7000-60000+1,data=ident(1));c.call(2,t=t-1,data=ident(1));c.call(5,224,t=MAX-7000-60000)
 c=case('lease-overflow-and-retained-floor').boot();c.call(9,MAX-1);c.call(3,data=ident(1));c.call(4,MAX,0);c.call(8);c.call(1,4,1000,7000,60000);c.call(3,data=ident(1));c.call(5,224);c.reboot(keep=True);c.call(6,224);c.call(3,data=ident(1))
 for bad in (bytes([2,1,2,3,4,5,6]),bytes([1,1,2,3,4,5,0x40]),bytes([1,1,2,3,4,5,0x80]),bytes([1,1,2,3,4,5,0]),b''):
  c=case('reject-noncanonical-'+bad.hex()).boot();c.call(2,data=bad);c.call(3,data=bad)
 for mode in range(6):c=case('alias-'+str(mode)).boot();c.call(10,mode);c.call(5,223);c.call(6,223);c.call(4,0,1);c.call(4,1,2)
 for entries in (1,2,3,4):
  c=case('capacity-roundtrip-'+str(entries));c.call(1,entries,1000,7000,60000)
  for i in range(entries):a=c.call(3,data=ident(i));c.call(4,a,1)
  c.call(3,data=ident(99));length=64+40*entries;c.call(5,length);blob=c.peer.codec[:length];c.call(7,entries,1000,7000,60000);c.call(6,length,data=blob);c.call(5,length)
 for a,b,cap,d,t in [(0,1000,7000,60000,0),(33,1000,7000,60000,0),(32,1000,7000,60000,0),(4,0,7000,60000,0),(4,3600001,3600001,60000,0),(4,1000,999,60000,0),(4,1000,86400001,60000,0),(4,1000,7000,0,0),(4,1000,7000,604800001,0),(4,1000,7000,60000,-1),(4,1000,7000,60000,MAX)]:
  c=case('init-rejection-'+str((a,b,cap,d,t)));c.call(1,a,b,cap,d,t);c.call(2,data=ident(1));c.call(8);c.boot();c.call(1,4,1000,7000,60000)
 # Every checkpoint field is checked transactionally. A second valid import
 # after rejection proves that the first did not partially claim any identity.
 template=Case('template').boot();a=template.call(3,data=ident(1));template.call(4,a,1);template.call(3,data=static(2));template.call(5,224);original=template.peer.codec
 mutations=[('magic',0,b'X'),('entries',8,q(3)),('minimum',16,q(999)),('maximum',24,q(7001)),('decay',32,q(60001)),('floor-negative',40,q(-1)),('count-negative',48,q(-1)),('count-large',48,q(5)),('reserved',56,q(1)),('id-kind',64,b'\2'),('id-RPA',104,bytes([1,1,2,3,4,5,0x40])),('pad',71,b'\1'),('interval-small',72,q(999)),('interval-negative',72,q(-1)),('interval-large',72,q(7001)),('wait-negative',80,q(-1)),('wait-large',80,q(7001)),('decay-zero',88,q(0)),('decay-negative',88,q(-1)),('decay-large',88,q(60001)),('live-value',96,q(2)),('live-while-waiting',96,q(1)),('duplicate-identity',104,ident(1)),('trailing',223,b'\1'),('zero-interval-with-decay',72,q(0)),('live-no-floor',40,q(0))]
 for name,offset,value in mutations:
  c=case('checkpoint-reject-'+name).boot();v=bytearray(original);v[offset:offset+len(value)]=value;c.call(6,224,t=20,data=bytes(v));c.call(6,224,t=20,data=original);c.call(6,224,t=20,data=original);c.call(5,224,t=20)
 c=case('checkpoint-rollback').boot();c.call(9,3);c.call(6,224,data=original);c.call(9,2);c.call(6,224,data=original)
 c=case('all-reboot-penalties-counted').boot();a=c.call(3,data=ident(1));c.call(5,224);c.reboot();c.call(6,224)
 for _ in range(6):
  t=c.peer.now+c.call(2,t=c.peer.now,data=ident(1));c.call(3,t=t,data=ident(1));c.call(5,224,t=t);c.reboot();c.call(6,224)
 rng=random.Random(0x5a4b139)
 for n in range(60):
  c=case('random-timeline-'+str(n)).boot(base=rng.choice([1,999,1000]),cap=rng.choice([7000,12345]),decay=rng.choice([7,100,60000]));now=0
  for j in range(32):
   now+=rng.choice([0,1,6,999,1000,7000,60000]);op=rng.randrange(6);id=rng.choice([ident(i) for i in range(1,7)]+[static(1)])
   if op in (0,1):c.call(2 if op==0 else 3,t=now,data=id)
   elif op==2:c.call(4,rng.randrange(1,c.peer.floor+3),rng.randrange(2),t=now)
   elif op==3:c.call(5,224,t=now)
   elif op==4:c.call(8,t=now)
   else:
    if not c.peer.initialized:c.call(1,4,1000,7000,60000,now)
    c.call(5,224,t=now);c.reboot();now=0;c.call(6,224)
 c=case('unresolved-bucket-checkpoint-and-reconnect').boot();a=c.call(3,data=BUCKET);c.call(3,data=BUCKET);c.call(4,a,1);c.call(5,224,t=20);c.reboot();c.call(6,224);c.call(2,data=BUCKET);c.call(3,t=980,data=BUCKET);c.call(4,2,1,t=981);c.call(2,t=981,data=BUCKET)
 for direction in [0,1]:
  source,target=(BUCKET,ident(1)) if direction else (ident(1),BUCKET)
  c=case('inherit-preserves-source-'+str(direction)).boot();a=c.call(3,data=source);c.call(13,data=source+target);c.call(4,a,1);c.call(13,t=100,data=source+target);c.call(2,t=100,data=source);c.call(2,t=100,data=target);c.call(5,224,t=100);c.reboot();c.call(6,224);c.call(2,data=source);c.call(2,data=target);c.call(3,t=900,data=target);c.call(13,t=900,data=source+target);c.call(4,2,1,t=901);c.call(13,t=901,data=target+source);c.call(2,t=901,data=source);c.call(2,t=901,data=target)
 for left,right in [(1,3),(3,1),(2,2)]:
  c=case('inherit-maximum-'+str((left,right))).boot(decay=100000);now=0
  for key,n in [(BUCKET,left),(ident(1),right)]:
   for _ in range(n):
    a=c.call(3,t=now,data=key);c.call(4,a,1,t=now);now+=c.call(2,t=now,data=key)
  c.call(13,t=now,data=BUCKET+ident(1));c.call(5,224,t=now);c.call(13,t=now,data=ident(1)+BUCKET);c.call(5,224,t=now)
 c=case('inherit-refuses-capacity-and-live-peer').boot()
 for i in range(4):a=c.call(3,data=ident(i));c.call(4,a,1)
 c.call(13,data=ident(0)+BUCKET);c.call(13,t=60000,data=ident(0)+BUCKET);c.call(13,t=60000,data=BUCKET+ident(0));a=c.call(3,t=60000,data=BUCKET);c.call(13,t=60000,data=ident(1)+BUCKET);c.call(4,a,1,t=60000);c.call(13,t=60000,data=BUCKET+BUCKET)
 for bad in [bytes([2,1,0,0,0,0,0]),bytes([2,0,0,0,0,0,1]),bytes([3,0,0,0,0,0,0])]:
  c=case('reserved-key-rejected-'+bad.hex()).boot();c.call(3,data=bad);c.call(13,data=BUCKET+bad)
 return cases
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work);w.mkdir(parents=True,exist_ok=True);cases=generate();parts=[];batch=[];indices=[];size=16
 def flush():
  if not batch:return
  blob=b'SMPRETR1'+q(len(batch))+b''.join(batch);name=f'part-{len(parts)}.bin';(w/name).write_bytes(blob);parts.append(dict(file=name,bytes=len(blob),cases=indices[:],checks=sum(len(cases[i].commands) for i in indices),sha256=hashlib.sha256(blob).hexdigest()))
 for i,c in enumerate(cases):
  data=c.encode()
  if size+len(data)>950000:flush();batch=[];indices=[];size=16
  batch.append(data);indices.append(i);size+=len(data)
 flush();r=dict(cases=len(cases),checks=sum(len(c.commands) for c in cases),parts=parts,labels=[dict(label=c.label,returns=c.returns) for c in cases],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(r,indent=2)+'\n');print('PASS:',r['cases'],'retry scenarios;',r['checks'],'independent observations;',len(parts),'parts')
if __name__=='__main__':main()
