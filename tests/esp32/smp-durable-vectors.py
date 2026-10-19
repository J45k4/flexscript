#!/usr/bin/env python3
"""Independent checkpoint-barrier peer over the verified owner/retry models.

Successful storage acknowledgments are injected boundary events, not proof of
actual media/authentication/counter durability. No hardware emulator is added.
"""
import argparse,copy,hashlib,importlib.util,json,random,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('durable_owner_peer',ROOT/'tests/esp32/smp-session-vectors.py');O=importlib.util.module_from_spec(spec);sys.modules[spec.name]=O;spec.loader.exec_module(O);R=O.R;MAX=2**63-1
def q(*x):return struct.pack('<'+'q'*len(x),*x)
class Peer:
 def __init__(self):
  self.o=O.Owner();self.o.p.links=2;self.o.p.slots=[None]*2;self.o.rows=[None]*2;self.revfloor=0;self.seqfloor=0;self.attached=False;self.error=0;self.rev=0;self.durable=0;self.seq=0;self.seen=0;self.busy=False;self.fr=0;self.fs=0;self.frozen=bytes(224);self.view=(0,0,0,0);self.shadow=[bytes(64)]*4;self.kr=[0]*4;assert self.init(576,0,0)==0
 def fault(self,error):self.error=error;self.o.p.packet=(0,0,0);self.o.p.event=(0,0,0,0);return error
 def ready(self):
  if not self.attached:return -19
  if self.error:return self.error
  r=self.o.check();return self.fault(r) if r else 0
 def raw(self):return [bytes(self.o.r.observe(0)[200+i*64:264+i*64]) for i in range(4)]
 def init(self,capacity,offset,seq):
  if self.attached:return -16
  r=self.o.check()
  if r:return r
  if any(self.o.rows):return -16
  if capacity<576 or offset&7 or seq<0:return -22
  if seq<self.seqfloor:return -116
  if seq==MAX or self.revfloor==MAX:return -75
  self.attached=True;self.revfloor+=1;self.rev=self.revfloor;self.durable=0;self.seq=seq;self.seqfloor=seq;self.seen=self.o.r.floor;self.busy=False;self.fr=self.fs=self.error=0;self.view=(0,0,0,0);self.frozen=bytes(224);self.shadow=self.raw();self.kr=[self.rev]*4;return 0
 def sync(self):
  r=self.ready()
  if r:return r
  if self.o.r.floor<self.seen:return self.fault(-116)
  rows=self.raw();changed=[i for i in range(4) if rows[i]!=self.shadow[i]]
  if not changed and self.o.r.floor==self.seen:return 0
  if self.revfloor==MAX:return self.fault(-75)
  self.revfloor+=1;self.rev=self.revfloor;self.seen=self.o.r.floor
  for i in changed:
   old,current=self.shadow[i],rows[i];keys=[]
   if any(old[:8]):keys.append(old[40:47])
   if any(current[:8]):keys.append(current[40:47])
   for row in self.o.rows:
    if row and row['id'] in keys:self.o.p.drop_views(row['token'])
   self.shadow[i]=current;self.kr[i]=self.rev
  return 0
 def required(self,t):
  row=self.o.find(t)
  if row is None:return -107
  record=self.o.r.find(row['id']);return self.kr[self.o.r.slots.index(record)] if record else self.rev
 def allowed(self,t):
  need=self.required(t);return need if need<0 else -11 if need>self.durable else 0
 def tick(self,now):
  r=self.ready()
  if r:return r
  r=self.o.tick(now);return self.sync() or r
 def command(self,op,t=1,a=0,b=0,c=0,d=0,now=0,data=b''):
  if op==15:return self.init(a,b,c)
  if op==20:self.revfloor=a;return 0
  if op==21:self.o.r.floor=a;return 0
  if op==22:return self.o.command(16,t,a=a)
  if op==24:
   row=self.o.r.find(data)
   if row is None:return -107
   row['lease']=a;return 0
  if op==14 and not self.attached:return 0
  r=self.ready()
  if r:return r
  if op==1:
   r=self.o.command(1,t,a=a,now=now,data=data);return self.sync() or r
  if op in [2,18,6,10,17]:
   mapped={2:2,18:18,6:6,10:10,17:14}[op];r=self.o.command(mapped,t,a=a,b=b,c=c,d=d,now=now);return self.sync() or r
  if op==4:return self.tick(now)
  if op==3:
   row=self.o.find(t)
   if not row:return -107
   r=self.tick(now)
   if r:return r
   code=data[0] if data else 0
   if row['lease'] and 1<=code<=14 and code!=5:
    r=self.allowed(t)
    if r:return r
   result=self.o.command(3,t,now=now,data=data);r=self.sync()
   if r:return r
   return (self.allowed(t) or result) if result==2 else result
  if op in [5,7]:
   r=self.sync()
   if r:return r
   link=self.o.link(t)
   if self.o.find(t) is None:return -107
   if op==5 and link.state==5:return -110
   if not (link.tx if op==5 else link.events):return 0
   r=self.allowed(t)
   if r:return r
   return self.o.command(op,t)
  if op==8:return self.o.command(8,t,a=a,b=b)
  if op==9:
   if b not in [0,1]:return -22
   if not self.o.find(t):return -107
   r=self.tick(now)
   if r:return r
   if b:
    r=self.allowed(t)
    if r:return r
   result=self.o.command(9,t,a=a,b=b,now=now);return self.sync() or result
  if op==11:
   r=self.tick(now)
   if r:return r
   if self.busy:return -16
   if self.rev<=self.durable:return 0
   if self.seq==MAX:return self.fault(-75)
   result=self.o.r.command(5,224,t=now);assert result==224
   self.frozen=self.o.r.codec;r=self.sync()
   if r:self.frozen=bytes(224);return r
   self.busy=True;self.fr=self.rev;self.fs=self.seq+1;return 1
  if op==12:
   if not self.busy:return 0
   self.view=(1,224,self.fr,self.fs);return 224
  if op==13:
   if c>0:return -22
   if not self.busy or a!=self.fs or b!=self.fr:return -116
   if not self.o.clock(now):return -22
   r=self.tick(now)
   if r:return r
   if c<0:self.fault(c);self.busy=False;self.fr=self.fs=0;self.frozen=bytes(224);self.view=(0,0,0,0);return c
   self.seq=self.seqfloor=a;self.durable=b;self.busy=False;self.fr=self.fs=0;self.frozen=bytes(224);self.view=(0,0,0,0);return 0
  if op==14:
   r=self.sync()
   if r:return r
   if any(self.o.rows) or self.busy or self.rev>self.durable:return -16
   self.attached=False;self.rev=self.durable=self.seq=self.seen=self.fr=self.fs=self.error=0;self.shadow=[bytes(64)]*4;self.kr=[0]*4;self.frozen=bytes(224);self.view=(0,0,0,0);return 0
  if op==16:
   result=self.o.command(13,t,a=a,b=b,now=now);return self.sync() or result or self.allowed(t)
  if op==19:
   if not self.o.clock(now):return -22
   result=self.o.r.command(13,t=now,data=data);return self.sync() or result
  if op==23:
   r=self.sync();return r or -22
  raise AssertionError(op)
 def observe(self,t,result,data):
  status=self.sync();owned=self.o.find(t);link=self.o.link(t);status=status or (0 if owned else -107);ps=self.o.p.observe(t,result);rs=self.o.r.observe(0);out=bytearray(1216)
  out[:128]=q(result,int(self.attached),self.rev,self.revfloor,self.durable,self.seq,self.seqfloor,int(self.busy),self.fr,self.fs,self.error,*self.view,self.seen);out[128:352]=self.frozen;out[352:384]=q(*self.kr);out[384:640]=rs[200:456];out[640:648]=q(status);out[648:920]=bytes([165])*272
  if not status:
   out[648:872]=ps[40:264];out[872:904]=q(owned['lease'])+owned['id']+b'\0'+q(owned['denied'],self.o.now);out[904:920]=q(self.required(t),self.durable)
  out[920:928]=ps[264:272];out[928:1000]=ps[272:344];out[1000:1056]=q(self.o.p.packet[0],self.o.p.packet[1],self.o.p.packet[2],*self.o.p.event);out[1056:1096]=q(self.o.r.now,self.o.r.floor,self.o.now,self.o.p.now,sum(row is not None for row in self.o.rows))
  for i,row in enumerate(self.o.rows):
   if row:out[1096+i*32:1128+i*32]=q(row['token'],row['lease'])+row['id']+b'\0'+q(row['denied'])
  out[1160:1216]=q(1,1,1,sum((i+1)*v for i,v in enumerate(data)),int(not link or not link.secret),self.o.fault,0);return bytes(out)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);args=p.parse_args();w=Path(args.work);w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();cases=[]
 def C(op,t=1,**kw):return op,dict(t=t,**kw)
 def case(label,commands):
  model=Peer();body=bytearray();results=[]
  for op,kw in commands:
   kw=dict(kw)
   if op==13 and kw.get('a')==-1 and kw.get('b')==-1 and model.busy:kw.update(a=model.fs,b=model.fr)
   data=kw.get('data',b'');t=kw.get('t',1);result=model.command(op,**kw);body+=q(op,t,kw.get('a',0),kw.get('b',0),kw.get('now',0),len(data),kw.get('c',0),kw.get('d',0))+data+model.observe(t,result,data);results.append(result)
  cases.append((label,q(len(body)+16,len(commands))+body,results))
 local=bytes([0,1,2,3,4,5,6]);peer=bytes([1,7,8,9,10,11,0x40]);cfg=bytes([1,0,13,16,7,7,7,0]);req=bytes([1,1,0,13,16,7,7]);rsp=bytes([2])+req[1:]
 def open(role=1,token=1,key=None,policy=0,now=0):return C(1,token,a=role,now=now,data=local+peer+cfg[:7]+bytes([policy])+(key or R.ident(1)))
 case('local-start-and-completion-barriers',[open(0),C(2,now=1),C(5),C(11,now=1),C(12),C(13,a=1,b=1,now=2),C(5),C(13,a=1,b=2,now=2),C(5),C(6,a=2,now=3),C(3,now=4,data=rsp),C(16,a=3,b=1,now=5),C(17,a=3,b=1,c=4,d=1,now=6),C(5),C(7),C(11,now=6),C(12),C(13,a=1,b=2,now=7),C(13,a=2,b=3,now=7),C(5),C(10,now=8),C(14),C(15,a=576,c=2),C(13,a=2,b=3,now=9)])
 case('early-ACK-does-not-authorize-input',[open(0),C(2),C(6,a=2),C(3,data=rsp),C(11),C(13,a=1,b=2),C(3,data=rsp),C(16,a=3,b=1)])
 case('phase2-after-early-ACK-still-needs-durability',[open(),C(3,data=req),C(6,a=2),C(16,a=2,b=1),C(11),C(13,a=1,b=2),C(16,a=2,b=1)])
 case('baseline-commit-does-not-cover-new-admission',[C(11),C(13,a=1,b=1),open(0),C(2),C(5),C(11),C(13,a=2,b=2),C(5)])
 case('committed-A-progresses-during-B-write',[open(0),open(token=2,key=R.ident(2)),C(2),C(11),C(13,a=1,b=2),C(3,2,data=req),C(11),C(12),C(5),C(5,2),C(13,a=2,b=3),C(5,2)])
 case('deinit-cannot-abandon-pending-checkpoint',[C(14),C(11),C(12),C(14),C(13,a=1,b=1),C(14),C(15,a=575,c=1),C(15,a=576,b=1,c=1),C(15,a=576,c=1)])
 case('peer-start-retains-crypto-until-durable',[open(),C(3,now=1,data=req),C(5),C(7),C(3,now=2,data=b'\3'+bytes(16)),C(16,a=2,b=1,now=2),C(11,now=2),C(12),C(13,a=1,b=2,now=3),C(5),C(16,a=2,b=1,now=3),C(6,a=2,now=4),C(3,now=5,data=b'\3'+bytes(16)),C(16,a=2,b=1,now=5)])
 for accept in [0,1]:
  case('consent-before-durability-'+str(accept),[open(policy=16),C(3,now=1,data=req),C(7),C(11,now=1),C(12),C(9,a=2,b=accept,now=2),C(7),C(13,a=1,b=2,now=3),C(7),C(9,a=2,b=1,now=4),C(11,now=4),C(12),C(13,a=2,b=3,now=5),C(7),C(5)])
 case('frozen-A-then-mutated-B',[open(0),open(1,token=2,key=R.ident(2)),C(2,now=1),C(11,now=1),C(12),C(3,2,now=2,data=req),C(11,now=2),C(12),C(13,a=1,b=2,now=3),C(5),C(5,2),C(6,a=2,now=4),C(3,2,now=5,data=b'\5\x08'),C(7,2),C(11,now=5),C(12),C(13,a=2,b=4,now=6),C(7,2),C(3,now=7,data=rsp),C(16,a=3,b=1,now=8)])
 for path in ['tick','ack','close','checkpoint']:
  action={'tick':C(4,now=30000),'ack':C(13,a=1,b=2,now=30000),'close':C(10,now=30000),'checkpoint':C(11,now=30000)}[path]
  case('timeout-while-storing-'+path,[open(0),C(2),C(22,a=90),C(11),C(12),action,C(5),C(7),C(12),C(13,a=1,b=2,now=30000),C(11,now=30001),C(12),C(13,a=2,b=3,now=30002),C(7),C(10,now=30003)])
 for status in [-5,-28,-110]:case('failed-storage-ACK-'+str(status),[open(0),C(2),C(11),C(12),C(13,a=1,b=2,c=status),C(5),C(3,data=b'\5\x08'),C(11),C(13,a=1,b=2),C(14)])
 case('failure-revokes-earlier-consent-event',[open(policy=16),open(token=2,key=R.ident(2)),C(3,data=req),C(11),C(13,a=-1,b=-1),C(7),C(3,2,data=req),C(11),C(13,a=-1,b=-1,c=-5),C(7)])
 case('ACK-of-issued-frame-survives-quiet-history-write',[open(0),C(2),C(11),C(13,a=-1,b=-1),C(3,data=b'\5\x08'),C(11),C(13,a=-1,b=-1),C(2,now=59000),C(11,now=59000),C(13,a=-1,b=-1,now=59000),C(5),C(11,now=60000),C(12),C(6,a=4,now=60001),C(3,now=60002,data=rsp),C(13,a=-1,b=-1,now=60003),C(3,now=60004,data=rsp)])
 case('deinit-keeps-committed-active-owner',[open(0),C(2),C(11),C(13,a=-1,b=-1),C(5),C(14),C(5)])
 case('owner-lease-fault-revokes-views',[open(0),C(2),C(11),C(13,a=-1,b=-1),C(5),C(24,a=999,data=R.ident(1)),C(5),C(12)])
 case('failure-revokes-earlier-views',[open(0),open(token=2,key=R.ident(2)),C(2),C(11),C(13,a=1,b=2),C(5),C(3,2,data=req),C(11),C(12),C(13,a=2,b=3,c=-5),C(5),C(7,2)])
 case('same-identity-denial-depends-on-pending-lease',[open(0,key=R.BUCKET),open(token=2,key=R.BUCKET),C(2),C(3,2,data=req),C(5,2),C(11),C(12),C(13,a=1,b=2),C(5),C(5,2),C(10,2),C(10),C(11),C(13,a=2,b=3),C(14)])
 case('inheritance-needs-commit-before-reclassified-start',[open(0,key=R.BUCKET),C(2),C(10),C(19,data=R.BUCKET+R.ident(1)),open(0,token=2),C(2,2,now=1000),C(5,2),C(11,now=1000),C(12),C(13,a=1,b=5,now=1000),C(5,2)])
 case('unmodified-polls-do-not-write',[C(11),C(12),C(13,a=1,b=1),C(11,now=1),C(11,now=1000),C(14),C(15,a=576,c=0),C(15,a=576,c=1),C(11,now=1000),C(13,a=2,b=2,now=1000),C(14),C(15,a=576,c=1),C(13,a=1,b=1,now=1000)])
 for b,a in [(0,0),(1,1),(3,1),(2,0),(2,2)]:case('stale-storage-tuple-'+str((a,b)),[open(0),C(2),C(11),C(12),C(13,a=a,b=b),C(12),C(5),C(13,a=1,b=2),C(5)])
 case('positive-status-and-clock-rollback',[open(0,now=10),C(2,now=10),C(11,now=10),C(12),C(13,a=1,b=2,c=1,now=10),C(13,a=1,b=2,now=9),C(12),C(13,a=1,b=2,now=11),C(5)])
 case('sequence-exhaustion',[C(11),C(13,a=1,b=1),C(14),C(15,a=576,c=MAX),C(15,a=576,c=MAX-1),C(11),C(13,a=MAX,b=2),open(0),C(2),C(11),C(5)])
 case('revision-exhaustion-revokes-views',[open(0),C(2),C(11),C(13,a=1,b=2),C(5),C(20,a=MAX),C(3,data=b'\5\x08'),C(5),C(12)])
 case('ledger-floor-rollback-stops-owner',[open(0),C(2),C(11),C(13,a=1,b=2),C(5),C(21,a=0),C(5),C(14)])
 for mode in range(6):case('gate-buffer-alias-'+str(mode),[open(0),C(23,a=mode),C(2),C(11),C(12)])
 for packet in [b'\1',bytes([1,5,0,13,16,7,7]),b'\x0b\2']:
  case('malformed-start-persists-failure-'+packet.hex(),[open(),C(3,data=packet),C(5),C(7),C(11),C(12),C(13,a=1,b=2),C(13,a=1,b=3),C(5)])
 rng=random.Random(470)
 for n in range(50):
  commands=[open(rng.randrange(2)),open(rng.randrange(2),token=2,key=R.ident(rng.randrange(1,3)))];now=0
  for j in range(28):
   now+=rng.choice([0,1,100,1000,30000]);t=rng.choice([1,2]);choice=rng.randrange(12)
   if choice==0:commands.append(C(2,t,now=now))
   elif choice==1:commands.append(C(18,t,now=now))
   elif choice==2:commands.append(C(3,t,now=now,data=rng.choice([req,rsp,b'\5\x08',b'\x0b\x01',b'\xff',b'\3'+bytes(16)])))
   elif choice==3:commands += [C(5,t),C(7,t)]
   elif choice==4:commands += [C(11,now=now),C(12)]
   elif choice==5:commands.append(C(13,a=-1,b=-1,now=now))
   elif choice==6:commands.append(C(6,t,a=rng.randrange(1,7),now=now))
   elif choice==7:commands.append(C(10,t,now=now))
   elif choice==8:commands.append(C(4,now=now))
   elif choice==9:commands.append(C(16,t,a=rng.randrange(1,6),b=rng.randrange(1,5),now=now))
   elif choice==10:commands.append(C(9,t,a=rng.randrange(1,6),b=rng.randrange(2),now=now))
   else:commands.append(C(17,t,a=rng.randrange(1,6),b=rng.randrange(1,5),c=8,d=1,now=now))
  case('interleaved-ledger-storage-'+str(n),commands)
 parts=[];batch=[];indices=[];size=16
 def flush():
  if not batch:return
  blob=b'SMPDURA1'+q(len(batch))+b''.join(batch);name=f'part-{len(parts)}.bin';(w/name).write_bytes(blob);parts.append(dict(file=name,bytes=len(blob),cases=indices[:],checks=sum(len(cases[i][2]) for i in indices),sha256=hashlib.sha256(blob).hexdigest()))
 for i,(_,blob,_) in enumerate(cases):
  if size+len(blob)>950000:flush();batch=[];indices=[];size=16
  batch.append(blob);indices.append(i);size+=len(blob)
 flush();report=dict(cases=len(cases),checks=sum(len(rs) for _,_,rs in cases),parts=parts,labels=[dict(label=l,returns=rs) for l,_,rs in cases],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',report['cases'],'durable-barrier scenarios;',report['checks'],'independent observations;',len(parts),'parts')
if __name__=='__main__':main()
