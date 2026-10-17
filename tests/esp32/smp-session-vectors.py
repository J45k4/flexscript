#!/usr/bin/env python3
"""Compose independent feature-exchange and retry peers to verify ownership.

The protocol peer follows Core5.4 Vol3 PartH; owner leases/generations are a
local contract. No ISA, peripheral or timing model is implemented here.
"""
import argparse,hashlib,importlib.util,json,random,struct,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def module(name,file):
 s=importlib.util.spec_from_file_location(name,ROOT/'tests/esp32'/file);m=importlib.util.module_from_spec(s);sys.modules[name]=m;s.loader.exec_module(m);return m
P=module('owner_feature_peer','smp-pairing-vectors.py');R=module('owner_retry_peer','smp-retry-vectors.py');MAX=2**63-1
def q(*x):return struct.pack('<'+'q'*len(x),*x)
class Owner:
 def __init__(self):
  self.p=P.Peer();self.r=R.Peer();assert self.r.init(4,1000,7000,60000,0)==0;self.rows=[None]*4;self.ready=True;self.now=0;self.fault=0
 def find(self,t):return next((x for x in self.rows if x and x['token']==t),None)
 def link(self,t):return next((x for x in self.p.slots if x and x.token==t),None)
 def check(self):
  if not self.ready:return -19
  if self.fault:return self.fault
  if not self.p.ready or not self.r.initialized or sum(x is not None for x in self.p.slots)!=sum(x is not None for x in self.rows):self.fault=-116;return self.fault
  for row in self.rows:
   if row:
    link=self.link(row['token']);history=self.r.find(row['id'])
    if link is None or (row['lease'] and (history is None or history['lease']!=row['lease'])) or (not row['lease'] and link.state in [2,3,6,7,8]):self.fault=-116;return self.fault
  return 0
 def clock(self,t):return self.now<=t and self.p.now<=t<=MAX-30000 and self.r.clock(t)
 def release(self,row,t):
  if not row['lease']:return 0
  result=self.r.command(4,row['lease'],1,t=t)
  if result:self.fault=result;return result
  row['lease']=0;return 0
 def reconcile(self,t):
  for row in self.rows:
   if row and row['lease'] and self.link(row['token']).state in [4,5]:
    result=self.release(row,t)
    if result:return result
  return 0
 def tick(self,t):
  result=self.check()
  if result:return result
  if not self.clock(t):return -22
  result=self.p.command(4,now=t);assert result==0;self.now=t;return self.reconcile(t)
 def admit(self,row,t):
  if row['lease']:return 0
  lease=self.r.command(3,t=t,data=row['id'])
  if lease<0:row['denied']=lease;return lease
  row['lease']=lease;row['denied']=0;return 0
 def command(self,op,t=1,a=0,b=0,c=0,d=0,now=0,data=b''):
  if op==15:return self.p.command(15,t,a=a)
  if op==16:return self.p.command(16,t,a=a)
  if op==19:
   history=self.r.find(data)
   if history is None:return -107
   history['lease']=a;return 0
  if op==17:return self.r.command(2,t=now,data=data)
  if op==14 and (not 1<=c<=15 or d not in [0,1]):return -22
  if op==11 and not self.ready:return 0
  if op==12:
   if self.ready:return -16
   if not self.p.ready or not self.r.initialized:return -19
   if any(self.p.slots) or any(r and r['lease'] for r in self.r.slots):return -16
   if a<320 or b&7:return -22
   self.ready=True;self.rows=[None]*4;self.now=max(self.p.now,self.r.now);self.fault=0;return 0
  result=self.check()
  if result:return result
  if op==21:return -22
  if op==11:
   if any(self.rows):return -16
   self.ready=False;self.now=0;self.rows=[None]*4;self.fault=0;return 0
  if op==1:
   if len(data)!=29 or not R.valid_key(data[22:]) or not self.clock(now):return -22
   result=self.p.command(1,t,a=a,now=now,data=data[:22])
   if result:return result
   self.rows[self.rows.index(None)]=dict(token=t,lease=0,id=data[22:],denied=0);self.now=now;return self.tick(now)
  if op==4:return self.tick(now)
  row=self.find(t);link=self.link(t)
  if not row:return -107
  if op==22:return -22
  if op==5:return self.p.command(5,t)
  if op==7:return self.p.command(7,t)
  if op==8:return self.p.command(8,t,a=a,b=b)
  if op==20:return -22
  if op==9 and b not in [0,1]:return -22
  result=self.tick(now)
  if result:return result
  if op in [2,18]:
   role=int(op==18)
   if link.state==5:return -110
   if link.role!=role:return -22
   if link.state not in ([1,4] if role else [1,4,8]):return -16
   if link.tx:return -11
   if link.epoch==MAX:return -75
   cfg=link.config
   if role and cfg[2]&4 and cfg[0]==3 and not cfg[1] and not cfg[7]&8:return -22
   result=self.admit(row,now)
   if result:return result
   result=self.p.command(op,t,now=now)
   if result:
    r=self.release(row,now)
    if r:return r
   return result
  if op==3:
   if link.state==5:return -110
   code=data[0] if data else 0
   ignore=code==11 and len(data)==2 and data[1]&3<=1 and not link.role and link.state in [2,3,6]
   if code in [1,11] and not ignore and not row['lease']:
    if link.tx:return -11
    if link.epoch==MAX or (code==1 and link.epoch>=MAX-1):return -75
    result=self.admit(row,now)
    if result:return self.p.fail(link,9 if result in [-11,-16] else 8)
   result=self.p.command(3,t,now=now,data=data);cleanup=self.reconcile(now);return cleanup or result
  if op==6:return self.p.command(6,t,a=a,now=now)
  if op==9:
   result=self.p.command(9,t,a=a,b=b,now=now);cleanup=self.reconcile(now);return cleanup or result
  if op==10:
   result=self.release(row,now)
   if result:return result
   result=self.p.command(10,t)
   if result:return result
   self.rows[self.rows.index(row)]=None;return 0
  if op==13:
   if link.state==5:return -110
   if b<=0 or row['lease']!=b or link.epoch!=a or link.state!=3:return -116
   return -11 if link.tx else 0
  if op==14:
   if link.state==5:return -110
   if b<=0 or row['lease']!=b or link.epoch!=a:return -116
   result=self.p.fail(link,c,bool(d));cleanup=self.reconcile(now);return cleanup or result
  raise AssertionError(op)
 def observe(self,t,result):
  status=self.check();row=self.find(t);link=self.link(t);ps=self.p.observe(t,result);rs=self.r.observe(0);o=bytearray(896)
  vals=[result,int(self.ready),sum(x is not None for x in self.rows),4 if self.ready else 0,self.now,self.fault,self.p.now,sum(x is not None for x in self.p.slots),self.p.floor,self.r.now,self.r.floor,status or (0 if row else -107)]
  o[:96]=q(*vals);o[96:352]=b'\xa5'*256
  if not status and row:
   o[96:320]=ps[40:264];o[320:352]=q(row['lease'])+row['id']+b'\0'+q(row['denied'],self.now)
  o[352:360]=ps[264:272];o[360:432]=ps[272:344]
  o[432:488]=q(self.p.packet[0],self.p.packet[1],self.p.packet[2],*self.p.event)
  o[488:744]=rs[200:456]
  for i,row in enumerate(self.rows):
   if row:o[744+i*32:776+i*32]=q(row['token'],row['lease'])+row['id']+b'\0'+q(row['denied'])
  o[872:896]=q(int(not link or not link.secret),1,1);return bytes(o)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);args=p.parse_args();w=Path(args.work);w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();cases=[]
 def case(label,commands):
  model=Owner();body=bytearray();results=[]
  for op,kw in commands:
   result=model.command(op,**kw);token=kw.get('t',1);data=kw.get('data',b'');body+=q(op,token,kw.get('a',0),kw.get('b',0),kw.get('now',0),len(data),kw.get('c',0),kw.get('d',0))+data+model.observe(token,result);results.append(result)
  cases.append((label,q(len(body)+16,len(commands))+body,results))
 def C(op,t=1,**kw):return op,dict(t=t,**kw)
 local=bytes([0,1,2,3,4,5,6]);air=bytes([1,7,8,9,10,11,0x40])
 def cfg(policy=0,io=1,auth=13):return bytes([io,0,auth,16,7,7,7,policy])
 def opening(role=1,token=1,identity=None,config=None,now=0,remote=air):return C(1,token,a=role,now=now,data=local+remote+(config or cfg())+(identity or R.ident(1)))
 def pdu(code=1,io=1,auth=13):return bytes([code,io,0,auth,16,7,7])
 for role in [0,1]:
  prefix=[opening(role)]
  if not role:prefix += [C(2,now=1),C(5),C(6,a=2,now=2)]
  prefix += [C(3,now=3,data=pdu(1 if role else 2)),C(7),C(13,a=2+int(not role),b=1,now=3),C(3,now=3,data=b'\3'+bytes(16)),C(5)]
  if role:prefix += [C(6,a=2,now=4)]
  prefix += [C(13,a=2+int(not role),b=1,now=5),C(14,a=2+int(not role),b=1,c=4,d=1,now=6),C(7),C(5),C(17,now=6,data=R.ident(1)),C(6,a=3+int(not role),now=7),C(10,now=8),opening(role,token=2,now=8),C(18 if role else 2,2,now=8),C(3,2,now=9,data=pdu() if role else b'\x0b\x0d'),C(5,2),C(10,2,now=10)]
  case('feature-handoff-failure-reconnect-'+str(role),prefix)
 for role in [0,1]:
  for accept in [0,1]:
   prefix=[opening(role,config=cfg(16))]
   if not role:prefix += [C(2,now=1),C(6,a=2,now=2)]
   epoch=2+int(not role);prefix += [C(3,now=3,data=pdu(1 if role else 2)),C(7),C(13,a=epoch,b=1,now=3),C(9,a=epoch,b=accept,now=4),C(13,a=epoch,b=1,now=5),C(5),C(17,now=5,data=R.ident(1)),C(10,now=6),C(17,now=6,data=R.ident(1))]
   case('consent-lease-'+str((role,accept)),prefix)
 for role in [0,1]:
  case('disconnect-counts-once-'+str(role),[opening(role),C(18 if role else 2,now=10),C(16,a=0x5a),C(5),C(10,now=20),C(17,now=20,data=R.ident(1)),C(10,now=21),opening(role,token=2,now=21),C(18 if role else 2,2,now=21),C(10,2,now=22),C(17,now=22,data=R.ident(1)),opening(role,token=3,now=1020),C(18 if role else 2,3,now=1020),C(10,3,now=1021),C(17,now=1021,data=R.ident(1))])
 for via in ['tick','packet-ACK','consent','input','close','phase2','failure','new-link']:
  commands=[opening(0),C(2,now=10),C(16,a=0x9a),C(5),C(4,now=30009)]
  op=dict(tick=C(4,now=30010),**{'packet-ACK':C(6,a=2,now=30010),'consent':C(9,a=2,b=1,now=30010),'input':C(3,now=30010,data=pdu(2)),'close':C(10,now=30010),'phase2':C(13,a=2,b=1,now=30010),'failure':C(14,a=2,b=1,c=8,d=1,now=30010),'new-link':opening(1,token=2,identity=R.ident(2),now=30010)})[via]
  commands += [op,C(17,now=30010,data=R.ident(1)),C(5),C(4,now=30011),C(17,now=30011,data=R.ident(1)),C(10,now=30012),C(17,now=30012,data=R.ident(1))];case('timeout-via-'+via,commands)
 for start in [b'\x0b\x0d',b'\x0b\x01']:
  case('central-security-joins-lease-'+start.hex(),[opening(0),C(3,now=1,data=start),C(7),C(3,now=2,data=b'\x0b\x01'),C(7),C(2,now=3),C(5),C(3,now=3,data=b'\x0b\x01'),C(6,a=4,now=4),C(3,now=5,data=pdu(2)),C(13,a=5,b=1,now=5),C(10,now=6),C(17,now=6,data=R.ident(1))])
 case('peripheral-security-joins-lease',[opening(),C(18,now=1),C(5),C(6,a=2,now=2),C(3,now=3,data=pdu()),C(5),C(6,a=3,now=4),C(13,a=3,b=1,now=5),C(10,now=6),C(17,now=6,data=R.ident(1))])
 case('one-identity-two-RPAs',[opening(0),opening(1,token=2,remote=bytes([1,7,8,9,10,11,0x41])),C(2,now=1),C(3,2,now=2,data=pdu()),C(5,2),C(5),C(17,now=2,data=R.ident(1)),C(10,2,now=3),C(10,now=4),C(17,now=4,data=R.ident(1))])
 case('independent-links-expire-and-close',[opening(0),opening(1,token=2,identity=R.ident(2)),C(2,now=10),C(3,2,now=20,data=pdu()),C(5,2),C(7,2),C(10,now=21),C(13,2,a=2,b=2,now=22),C(6,2,a=2,now=23),C(13,2,a=2,b=2,now=24),C(4,now=30020),C(17,now=30020,data=R.ident(1)),C(17,now=30020,data=R.ident(2))])
 case('capacity-remains-after-reconnections',[opening(0,token=i,identity=R.ident(i)) for i in [1,2,3,4]]+[C(2,i) for i in [1,2,3,4]]+[C(10,i) for i in [1,2,3,4]]+[opening(0,token=5,identity=R.ident(5)),C(2,5),C(3,5,data=b'\x0b\x01'),C(5,5),C(10,5),C(11),C(12,a=320),opening(0,token=6,identity=R.ident(1)),C(2,6,now=999),C(2,6,now=1000),C(10,6,now=1001),C(17,now=1001,data=R.ident(1))])
 for malformed in [b'\x01',pdu(auth=2),pdu(io=5),b'\x0b',b'\x0b\x02']:
  case('malformed-start-counts-'+malformed.hex(),[opening(),C(3,now=1,data=malformed),C(5),C(7),C(17,now=1,data=R.ident(1)),C(6,a=2,now=2),C(3,now=3,data=pdu()),C(5),C(17,now=3,data=R.ident(1))])
 for role,packet in [(0,pdu()),(1,b'\x0b\x01')]:case('wrong-role-start-'+str(role),[opening(role),C(3,now=1,data=packet),C(17,now=1,data=R.ident(1)),C(5)])
 for epoch in [MAX-2,MAX-1,MAX]:
  for packet in [pdu(),b'\x0b\x01']:
   case('epoch-preflight-'+str(epoch)+'-'+str(packet[0]),[opening(1 if packet[0]==1 else 0),C(15,a=epoch),C(3,now=1,data=packet),C(5),C(17,now=1,data=R.ident(1)),C(10,now=2)])
 for bad in [0,1,2,999]:case('stale-phase2-triple-'+str(bad),[opening(),C(3,now=1,data=pdu()),C(6,a=2,now=2),C(13,a=2,b=bad,now=3),C(14,a=1,b=bad,c=8,d=0,now=4),C(14,a=2,b=bad,c=8,d=0,now=4),C(10,now=5)])
 for mode in range(5):case('snapshot-alias-'+str(mode),[opening(),C(20,a=mode),C(2),C(18),C(10)])
 for mode in range(4):case('open-input-alias-'+str(mode),[C(21,a=mode,data=local+air+cfg()+R.ident(1)),opening(),C(3,data=pdu()),C(10)])
 for mode in range(3):case('input-alias-'+str(mode),[opening(),C(22,a=mode),C(3,data=pdu()),C(10)])
 for role in [0,1]:
  commands=[opening(role),C(18 if role else 2),C(3,data=b'\x05\x08'),C(3,data=pdu() if role else b'\x0b\x01'),C(5),C(18 if role else 2,now=1000),C(3,now=1000,data=pdu() if role else b'\x0b\x01'),C(17,now=1000,data=R.ident(1)),C(6,a=4,now=1001),C(18 if role else 2,now=1001),C(5),C(10,now=1002)]
  case('retained-failure-packet-blocks-admission-'+str(role),commands)
 for config,packet in [(cfg(policy=2),pdu(auth=1)),(cfg(policy=1),pdu(io=3)),(cfg(policy=4),pdu(auth=8))]:case('negotiation-failure-releases-'+config.hex(),[opening(config=config),C(3,now=1,data=packet),C(5),C(17,now=1,data=R.ident(1)),C(10,now=2)])
 case('maximum-clock-boundary',[opening(0,now=MAX-67000),C(2,now=MAX-67000),C(4,now=MAX-66999),C(10,now=MAX-67000),C(17,now=MAX-67000,data=R.ident(1))])
 case('ledger-hijack-latches-owner',[opening(),C(3,now=1,data=pdu()),C(19,a=999,data=R.ident(1)),C(5),C(3,now=2,data=b'\x05\x08'),C(10,now=3)])
 case('clock-rollback-no-admission',[opening(0,now=100),C(2,now=99),C(2,now=100),C(10,now=99),C(13,a=2,b=1,now=101),C(3,now=100,data=b'\x05\x08'),C(10,now=102),C(17,now=102,data=R.ident(1))])
 case('owner-reinit-retains-penalties',[opening(0),C(2),C(10),C(11),C(5),C(12,a=319),C(12,a=320,b=1),C(12,a=320),opening(0,token=2),C(2,2),C(10,2),C(11),C(12,a=320),opening(0,token=3,now=1000),C(2,3,now=1000),C(10,3,now=1001)])
 for identity in [bytes([1,1,2,3,4,5,0x40]),bytes([2,1,2,3,4,5,6]),R.static(3)]:case('identity-validation-'+identity.hex(),[opening(identity=identity),C(3,data=pdu()),C(10)])
 rng=random.Random(461)
 for n in range(50):
  commands=[];nexttoken=1;tokens=[];now=0
  for j in range(30):
   now+=rng.choice([0,1,100,1000,30000]);choice=rng.randrange(9)
   if choice==0 or not tokens:
    token=nexttoken;nexttoken+=1;tokens.append(token);commands.append(opening(rng.randrange(2),token,identity=R.ident(rng.randrange(1,6)),config=cfg(rng.choice([0,16])),now=now));continue
   token=rng.choice(tokens)
   if choice==1:commands.append(C(2,token,now=now))
   elif choice==2:commands.append(C(18,token,now=now))
   elif choice==3:commands.append(C(3,token,now=now,data=rng.choice([pdu(),pdu(2),b'\x0b\x01',b'\x05\x08',b'\x03'+bytes(16),b'\xff',b'\x01'])))
   elif choice==4:commands.append(C(6,token,a=rng.randrange(1,9),now=now))
   elif choice==5:commands += [C(5,token),C(7,token)]
   elif choice==6:commands.append(C(9,token,a=rng.randrange(1,9),b=rng.randrange(2),now=now))
   elif choice==7:commands.append(C(10,token,now=now));tokens.remove(token)
   else:commands.append(C(4,now=now))
  case('mixed-connections-'+str(n),commands)
 parts=[];batch=[];indices=[];size=16
 def flush():
  if not batch:return
  blob=b'SMPOWNR1'+q(len(batch))+b''.join(batch);name=f'part-{len(parts)}.bin';(w/name).write_bytes(blob);parts.append(dict(file=name,bytes=len(blob),cases=indices[:],checks=sum(len(cases[i][2]) for i in indices),sha256=hashlib.sha256(blob).hexdigest()))
 for i,(_,blob,_) in enumerate(cases):
  if size+len(blob)>950000:flush();batch=[];indices=[];size=16
  batch.append(blob);indices.append(i);size+=len(blob)
 flush();report=dict(cases=len(cases),checks=sum(len(c[2]) for c in cases),parts=parts,labels=[dict(label=l,returns=rs) for l,_,rs in cases],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',report['cases'],'session-owner scenarios;',report['checks'],'independent observations;',len(parts),'parts')
if __name__=='__main__':main()
