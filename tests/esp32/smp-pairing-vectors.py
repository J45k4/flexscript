#!/usr/bin/env python3
"""Independent LE SMP phase1 peer and normative association-table vectors."""
import argparse,dataclasses,hashlib,json,struct
from pathlib import Path
MAX=(1<<63)-1
def q(n):return struct.pack('<Q',n&((1<<64)-1))
LEGACY=[[0,0,2,0,2],[0,0,2,0,2],[1,1,1,0,1],[0]*5,[1,1,2,0,-1]]
SC=[[0,0,2,0,2],[0,3,2,0,3],[1,1,1,0,1],[0]*5,[1,3,2,0,3]]
def method(io,remote,oob,remote_oob,auth,remote_auth,role):
 sc=bool(auth&remote_auth&8);tag=256*sc
 if (any([oob,remote_oob]) if sc else all([oob,remote_oob])):return tag+67
 if not (auth|remote_auth)&4:return tag
 action=(SC if sc else LEGACY)[io][remote]
 if action==-1:action=1 if role else 2
 return tag+16*action+(2 if action==3 else 1 if action else 0)
@dataclasses.dataclass
class Link:
 token:int;role:int;local:bytes;peer:bytes;config:bytes
 state:int=1;epoch:int=1;sc:int=0;method:int=0;key:int=0;bond:int=0;ik:int=0;rk:int=0;action:int=0;candidate:int=0;failure:int=0;deadline:int=0;want:int=0;requested:int=0;events:int=0;peerfail:int=0;ct2:int=0;secret:bool=False
 preq:bytes=bytes(7);pres:bytes=bytes(7);peerpdu:bytes=bytes(7);tx:bytes=b'';txgen:int=0
 def clear(self):
  for name in ['sc','method','key','bond','ik','rk','action','candidate','failure','deadline','want','requested','events','peerfail','ct2']:setattr(self,name,0)
  self.preq=self.pres=self.peerpdu=bytes(7);self.tx=b'';self.txgen=0;self.secret=False
class Peer:
 def __init__(self):self.ready=True;self.links=4;self.slots=[None]*4;self.floor=0;self.now=0;self.packet=(0,0,0);self.event=(0,0,0,0)
 def drop_views(self,t):
  if self.packet[0]==t:self.packet=(0,0,0)
  if self.event[1]==t:self.event=(0,0,0,0)
 def time(self,l,now):
  if now<self.now or not 0<=now<=MAX-30000:return -22
  self.now=now
  if l and l.deadline and now>=l.deadline:
   l.clear();self.drop_views(l.token);l.state=5;l.failure=-110;l.events=8;l.epoch=min(l.epoch+1,MAX)
  return -110 if l and l.state==5 else 0
 def enqueue(self,l,pdu,timed=True):l.tx=pdu;l.txgen=l.epoch;l.deadline=self.now+30000 if timed else l.deadline
 def fail(self,l,reason,reply=True):
  if reply and l.tx:return -11
  if l.epoch==MAX:return -75
  l.clear();self.drop_views(l.token);l.epoch+=1;l.state=4;l.failure=reason;l.events=4
  if reply:self.enqueue(l,bytes([5,reason]),False)
  return 1
 def agree(self,l):
  req,rsp=l.preq,l.pres;c=l.config;l.key=min(req[4],rsp[4])
  if l.key<c[6]:return 6
  packed=method(c[0],l.peerpdu[1],c[1],l.peerpdu[2],c[2],l.peerpdu[3],l.role)
  sc=packed>>8;model=packed&15;action=packed>>4&15;auth=int(bool(model in [1,2] or model==3 and c[7]&8));bond=int(req[3]&3==rsp[3]&3==1);want=l.want|l.requested
  if ((c[7]&2 or want&8) and not sc) or ((c[7]&1 or want&4) and not auth) or (c[7]&4 and not bond):return 3
  ik=req[5]&rsp[5]&15;rk=req[6]&rsp[6]&15
  if not bond:ik=rk=0
  elif sc:
   ik&=14;rk&=14
   if not ik&rk&8:ik&=7;rk&=7
  else:ik&=7;rk&=7
  l.sc=sc;l.method=model;l.action=action;l.candidate=auth;l.bond=bond;l.ik=ik;l.rk=rk;l.ct2=int(sc and req[3]&rsp[3]&32!=0)
  return 0
 def command(self,op,t=0,a=0,b=0,now=0,data=b''):
  l=next((l for l in self.slots if l and l.token==t),None)
  if op==17:return method(*data)
  if op==12:
   if self.ready:return -16
   if not 1<=t<=4 or a<256+1536*t or b&7:return -22
   self.ready=True;self.links=t;self.slots=[None]*t;self.now=0;self.packet=(0,0,0);self.event=(0,0,0,0);return 0
  if op==11:
   if not self.ready:return 0
   if any(self.slots):return -16
   self.ready=False;self.links=0;self.slots=[];self.now=0;self.packet=(0,0,0);self.event=(0,0,0,0);return 0
  if not self.ready:return -19
  if op==1:
   local,remote,c=data[:7],data[7:14],data[14:]
   valid=(len(data)==22 and t>self.floor and a in [0,1] and local[0]<=1 and remote[0]<=1 and c[0]<=4 and c[1]<=1 and c[2]<=63 and c[2]&3<=1 and 7<=c[3]<=16 and c[4]<=15 and c[5]<=15 and (c[2]&8 or not (c[4]|c[5])&8) and 7<=c[6]<=c[3] and c[7]<=31 and (not c[7]&1 or c[2]&4) and (not c[7]&2 or c[2]&8) and (not c[7]&4 or c[2]&3==1) and self.now<=now<=MAX-30000)
   if not valid:return -22
   if all(self.slots):return -105
   self.now=now;self.slots[self.slots.index(None)]=Link(t,a,local,remote,c);self.floor=t;return 0
  if op==4:
   if self.time(None,now):return -22
   for entry in self.slots:
    if entry:self.time(entry,now)
   return 0
  if not l:return -107
  if op==10:self.slots[self.slots.index(l)]=None;self.drop_views(t);return 0
  if op==13:return -22
  if op==14:return -22
  if op==15:l.epoch=a;return 0
  if op==16:l.secret=bool(a&255);return 0
  if op==5:
   if l.state==5:return -110
   if not l.tx:return 0
   self.packet=(t,l.txgen,len(l.tx));return len(l.tx)
  if op==6:
   r=self.time(l,now)
   if r:return r
   if not l.tx or l.txgen!=a:return -116
   l.tx=b'';l.txgen=0
   if self.packet[:2]==(t,a):self.packet=(0,0,0)
   return 0
  if op==7:
   if not l.events:return 0
   kind=(l.events&-l.events).bit_length();self.event=(kind,t,l.epoch,l.want if kind==5 else l.failure);return 1
  if op==8:
   if not 1<=b<=5:return -22
   if a!=l.epoch or not l.events&(1<<(b-1)):return -116
   l.events&=~(1<<(b-1))
   if self.event[:3]==(b,t,a):self.event=(0,0,0,0)
   return 0
  if op==2:
   if l.role:return -22
   if l.state==5:return -110
   if l.state not in [1,4,8]:return -16
   if l.tx:return -11
   if l.epoch==MAX:return -75
   r=self.time(l,now)
   if r:return r
   want=l.want;l.clear();self.drop_views(t);l.epoch+=1;l.want=want;l.state=2;l.preq=b'\x01'+l.config[:6];self.enqueue(l,l.preq);return 0
  if op==18:
   if l.role!=1:return -22
   if l.state==5:return -110
   if l.state not in [1,4]:return -16
   if l.tx:return -11
   if l.epoch==MAX:return -75
   c=l.config
   if c[2]&4 and c[0]==3 and not c[1] and not c[7]&8:return -22
   r=self.time(l,now)
   if r:return r
   l.clear();self.drop_views(t);l.epoch+=1;l.state=7;l.requested=c[2];self.enqueue(l,bytes([11,c[2]]));return 0
  if op==9:
   if b not in [0,1]:return -22
   r=self.time(l,now)
   if r:return r
   if l.state!=6 or a!=l.epoch:return -116
   if l.tx:return -11
   if not b:r=self.fail(l,8);return min(r,0)
   if l.epoch==MAX:return -75
   self.drop_views(t);l.epoch+=1;l.state=3;l.events=1
   if l.role:self.enqueue(l,l.pres)
   return 0
  assert op==3,op
  r=self.time(l,now)
  if r:return r
  if not data:return self.fail(l,10)
  code=data[0]
  if code==0 or code>14:return 0
  if code==5:
   if len(data)!=2:return self.fail(l,10)
   raw=data[1];r=self.fail(l,raw if 1<=raw<=15 else 8,False)
   if r>0:l.peerfail=raw
   return r
  if code==11:
   if len(data)!=2 or data[1]&3>1:return self.fail(l,10)
   if l.role:return self.fail(l,8)
   if l.state in [2,3,6]:return 0
   if l.tx:return -11
   if l.epoch==MAX:return -75
   auth=l.want|data[1]&63;l.clear();self.drop_views(t);l.epoch+=1;l.want=auth;l.state=8;l.events=16;l.deadline=now+30000;return 1
  if code in [1,2]:
   if l.tx:return -11
   if len(data)!=7:return self.fail(l,10)
   if data[1]>4 or data[2]>1 or data[3]&3>1:return self.fail(l,10)
   if not 7<=data[4]<=16:return self.fail(l,6)
   if (code==1 and (l.role!=1 or l.state not in [1,4,7])) or (code==2 and (l.role!=0 or l.state!=2)):return self.fail(l,8)
   if l.epoch>=MAX-1:return -75
   if code==1:
    requested=l.requested;l.clear();self.drop_views(t);l.epoch+=1;l.requested=requested;l.preq=data;l.pres=bytes([2])+l.config[:4]+bytes([l.config[4]&data[5]&15,l.config[5]&data[6]&15]);l.deadline=now+30000
   else:
    mask=15 if l.preq[3]&data[3]&8 else 7
    if data[5]&mask&~l.preq[5] or data[6]&mask&~l.preq[6]:return self.fail(l,10)
    l.epoch+=1;l.pres=data
   l.peerpdu=data;error=self.agree(l)
   if error:return self.fail(l,error)
   if l.config[7]&16:l.state=6;l.events=2
   else:
    l.state=3;l.events=1
    if l.role:self.enqueue(l,l.pres)
   return 1
  expected={7:11,9:8,12:65,14:2}.get(code,17)
  if len(data)!=expected:return self.fail(l,10)
  return (-11 if l.tx else 2) if l.state==3 else self.fail(l,8)
 def observe(self,t,result):
  l=next((l for l in self.slots if l and l.token==t),None);out=bytearray(432)
  def word(at,value):out[at:at+8]=q(value)
  for at,value in [(0,result),(8,self.now),(16,sum(x is not None for x in self.slots)),(24,self.floor),(32,0 if l else -107 if self.ready else -19)]:word(at,value)
  if not l:out[40:264]=b'\xa5'*224
  else:
   s=bytearray(224);values=[l.state,l.role,l.sc,l.method,l.key,l.bond,l.ik,l.rk,l.action,l.candidate,0,l.failure,l.deadline,l.epoch,len(l.tx),l.events,l.want,l.requested,l.ct2,l.peerfail]
   for i,v in enumerate(values):s[i*8:i*8+8]=q(v)
   for at,value in [(160,l.local),(168,l.peer),(176,l.preq),(184,l.pres),(192,l.config),(200,l.peerpdu),(208,q(t))]:s[at:at+len(value)]=value
   out[40:264]=s;word(264,len(l.tx));out[272:272+len(l.tx)]=l.tx
  for at,value in [(344,self.packet[0]),(352,self.packet[1]),(360,self.event[0]),(368,self.event[1]),(376,self.event[2]),(384,self.event[3]),(392,self.packet[2]),(400,int(not l or not l.secret)),(408,1),(416,1)]:word(at,value)
  return out

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();cases=[]
 def case(label,commands):
  model=Peer();body=bytearray();results=[]
  for command in commands:
   op=command[0];kw=command[1];result=model.command(op,**kw);data=kw.get('data',b'');token=kw.get('t',0);header=[op,token,kw.get('a',0),kw.get('b',0),kw.get('now',0),len(data),0,0];body+=b''.join(q(x) for x in header)+data+model.observe(token,result);results.append(result)
  cases.append((label,q(len(body)+16)+q(len(commands))+body,results))
 def C(op,t=1,**kw):return (op,dict(t=t,**kw))
 local=b'\x00'+bytes.fromhex('665544332211');remote=b'\x01'+bytes.fromhex('ffeeddccbbaa')
 def cfg(io=1,oob=0,auth=13,key=16,ik=7,rk=7,min=7,policy=0):return bytes([io,oob,auth,key,ik,rk,min,policy])
 def opening(role=1,config=None,token=1,now=0):return C(1,token,a=role,now=now,data=local+remote+(config or cfg()))
 def pdu(code=1,io=1,oob=0,auth=13,key=16,ik=7,rk=7):return bytes([code,io,oob,auth,key,ik,rk])
 methods=[]
 for io in range(5):
  for peerio in range(5):
   for la,pa in [(0,0),(8,0),(0,8),(8,8)]:
    for lm,pm in [(0,0),(4,0),(0,4),(4,4)]:
     for lo,po in [(0,0),(1,0),(0,1),(1,1)]:
      for role in [0,1]:methods.append(C(17,0,data=bytes([io,peerio,lo,po,la|lm|1,pa|pm|1,role])))
 for at in range(0,len(methods),400):case('association-table-'+str(at),methods[at:at+400])
 # Real feature exchanges in both roles, crossing every I/O pair and SC/legacy.
 for role in [0,1]:
  for sc in [0,8]:
   for io in range(5):
    for peerio in range(5):
     auth=1|4|sc;commands=[opening(role,cfg(io=io,auth=auth))]
     if not role:commands += [C(2,now=10),C(5),C(6,a=2,now=11)]
     commands += [C(3,now=20,data=pdu(1 if role else 2,io=peerio,auth=auth)),C(5),C(7),*([C(6,a=2,now=21)] if role else []),C(3,now=22,data=b'\x03'+bytes(16)),C(10),C(11)]
     case(f'features-{role}-{sc}-{io}-{peerio}',commands)
 for maximum in range(7,17):
  for peermax in range(7,17):
   for minimum in [7,maximum]:case(f'key-{maximum}-{peermax}-{minimum}',[opening(config=cfg(key=maximum,min=minimum)),C(3,now=1,data=pdu(key=peermax)),C(5),C(7)])
 for la,pa in [(0,0),(0,1),(1,0),(1,1)]:
  for sc in [0,8]:
   for secure in [0,8]:
    for policy in [0,1]:case(f'oob-{la}-{pa}-{sc}-{secure}-{policy}',[opening(config=cfg(io=3,oob=la,auth=5|sc,policy=secure|policy)),C(3,now=10,data=pdu(io=3,oob=pa,auth=5|sc)),C(5),C(7)])
 for sc in [0,8]:
  for bond in [0,1]:
   for ik,rk in [(0,0),(1,2),(7,7),(8,8),(8,0),(0,8),(15,15),(14,10)]:case(f'keys-{sc}-{bond}-{ik}-{rk}',[opening(config=cfg(auth=bond|sc|32,ik=15 if sc else 7,rk=15 if sc else 7)),C(3,now=1,data=pdu(auth=1|sc|32,ik=ik,rk=rk)),C(5)])
 for policy in [1,2,4,16,17,18,20,31]:
  for auth in [0,1,5,9,13,45]:case(f'policy-{policy}-{auth}',[opening(config=cfg(auth=45,oob=1,policy=policy)),C(3,now=10,data=pdu(auth=auth)),C(7),C(9,a=2,b=1,now=100),C(5)])
 bad=[b'',b'\x01',pdu()[:-1],pdu()+b'\0',pdu(io=5),pdu(oob=2),pdu(auth=2),pdu(auth=3),pdu(key=6),pdu(key=17),pdu()+bytes(60),b'\x03',b'\x0c'+bytes(63),b'\x05',b'\x0b',b'\x0b\x02']
 for i,packet in enumerate(bad):case(f'malformed-{i}',[opening(),C(3,now=1,data=packet),C(5),C(7)])
 for role in [0,1]:
  for accept in [0,1]:case(f'consent-{role}-{accept}',[opening(role,cfg(policy=16)),*([C(2,now=1),C(6,a=2,now=2)] if not role else []),C(3,now=10,data=pdu(1 if role else 2)),C(7),C(5),C(9,a=2 if role else 3,b=accept,now=20),C(5),C(7),C(9,a=2 if role else 3,b=1,now=21)])
 case('timeout-lock',[opening(0),C(2,now=100),C(5),C(16,a=107),C(4,now=30099),C(4,now=30100),C(5),C(7),C(2,now=30101),C(3,now=30102,data=pdu()),C(3,now=30103,data=b'\xff'),C(8,a=3,b=4),C(10),opening(0,token=1,now=30104),opening(0,token=2,now=30104),C(2,2,now=30105)])
 case('failure-cancels-output',[opening(0),C(2,now=1),C(5),C(16,a=51),C(3,now=2,data=b'\x05\x04'),C(6,a=2,now=3),C(7),C(2,now=4),C(6,a=2,now=5),C(5)])
 case('crypto-handoff-backpressure',[opening(1),C(3,now=1,data=pdu()),C(5),C(16,a=90),C(3,now=2,data=b'\x03'+bytes(16)),C(6,a=2,now=3),C(3,now=4,data=b'\x03'+bytes(16)),C(7)])
 case('backpressure',[opening(0),C(2,now=1),C(16,a=51),C(5),C(3,now=2,data=pdu(2)),C(3,now=3,data=b'\xff\x01'),C(6,a=2,now=4),C(3,now=5,data=pdu(2)),C(7)])
 case('stale-event-ACK',[opening(config=cfg(policy=16)),C(3,now=1,data=pdu()),C(7),C(3,now=2,data=b'\x05\x08'),C(3,now=3,data=pdu()),C(7),C(8,a=2,b=2),C(8,a=4,b=2),C(9,a=4,b=1,now=4)])
 case('stale-consent',[opening(config=cfg(policy=16)),C(3,now=1,data=pdu()),C(7),C(3,now=2,data=b'\x05\x08'),C(9,a=2,b=1,now=3),C(8,a=2,b=2),C(3,now=4,data=pdu()),C(7),C(9,a=2,b=1,now=5)])
 case('independent-links',[opening(0),opening(1,token=2),C(2,1,now=10),C(16,2,a=107),C(5,1),C(3,2,now=11,data=pdu()),C(5,2),C(10,1),C(6,2,a=2,now=12),C(7,2),C(10,2),C(11),C(12,4,a=6400),opening(token=1,now=0),opening(token=3,now=0)])
 case('security-request',[opening(1),C(18,now=1),C(5),C(6,a=2,now=2),C(18,now=3),C(3,now=4,data=pdu(auth=1)),C(5),C(7)])
 case('central-security-request',[opening(0),C(3,now=1,data=b'\x0b\x0d'),C(7),C(3,now=2,data=b'\x0b\x01'),C(7),C(2,now=3),C(6,a=4,now=4),C(3,now=5,data=pdu(2,auth=1)),C(5),C(7)])
 case('ignored-security-when-pairing',[opening(0),C(2,now=1),C(3,now=2,data=b'\x0b\x0d'),C(5)])
 case('raw-RFU-transcript',[opening(config=cfg(auth=45,ik=15,rk=15)),C(3,now=1,data=pdu(auth=237,ik=247,rk=255)),C(5),C(7)])
 case('legacy-LinkKey-receive-ignore',[opening(0,cfg(auth=1,ik=7,rk=7)),C(2,now=1),C(6,a=2,now=2),C(3,now=3,data=pdu(2,auth=1,ik=15,rk=15)),C(7)])
 case('legacy-LinkKey-local-invalid',[opening(0,cfg(auth=1,ik=15,rk=7)),opening(0,cfg(auth=1,ik=7,rk=15))])
 case('SC-distribution-subset',[opening(0,cfg(auth=45,ik=15,rk=15)),C(2,now=1),C(6,a=2,now=2),C(3,now=3,data=pdu(2,auth=45,ik=2,rk=4)),C(5),C(7)])
 case('legacy-distribution-subset',[opening(0,cfg(auth=5,ik=7,rk=7)),C(2,now=1),C(6,a=2,now=2),C(3,now=3,data=pdu(2,auth=5,ik=1,rk=2)),C(5),C(7)])
 case('close-wipes-inflight',[opening(0),C(2,now=1),C(16,a=107),C(5),C(10),C(6,a=2,now=2),opening(0,token=2,now=2),C(5,2)])
 case('response-superset',[opening(0,cfg(ik=1,rk=2)),C(2,now=1),C(6,a=2,now=2),C(3,now=3,data=pdu(2,ik=7,rk=7)),C(5)])
 case('clock-and-overflow',[opening(),C(3,now=10,data=b'\xff'),C(3,now=9,data=pdu()),C(4,now=MAX),C(15,a=MAX-1),C(3,now=11,data=pdu()),C(10)])
 case('alias-and-snapshot',[opening(0),C(2,now=1),C(5),C(13,a=0),C(13,a=1),C(13,a=2),C(14,a=576,b=7,now=2),C(6,a=2,now=3),C(10),C(13,a=0)])
 case('closed-token-and-capacity',[opening(token=i) for i in [1,2,3,4]]+[opening(token=5),C(10,2),opening(token=5),C(2,2,now=1),C(5,2),C(7,2)])
 case('unknown-peer-error',[opening(0),C(2,now=1),C(3,now=2,data=b'\x05\xff'),C(7),C(5)])
 for code in [0,15,127,255]:
  for size in [1,65,66]:case(f'ignored-RFU-{code}-{size}',[opening(0),C(2,now=1),C(5),C(3,now=2,data=bytes([code])+bytes(size-1)),C(5)])
 case('minimum-larger-than-maximum',[opening(config=cfg(key=7,min=16))])
 case('security-request-without-IO',[opening(config=cfg(io=3)),C(18,now=1),C(5)])
 case('local-RFU-auth-invalid',[opening(config=cfg(auth=205))])
 case('address-type-invalid',[C(1,a=1,data=b'\x02'+local[1:]+remote+cfg()),C(1,a=1,data=local+b'\x03'+remote[1:]+cfg())])
 for i in range(8):
  config=bytearray(cfg());config[i]=[5,2,2,17,16,16,6,32][i];case('invalid-config-'+str(i),[opening(config=bytes(config)),C(11),C(12,4,a=6399),C(12,4,a=6400,b=1),C(12,4,a=6400)])
 chunks=[];current=[];current_size=16
 def flush():
  nonlocal current,current_size
  if not current:return
  data=b'SMPPAIR1'+q(len(current))+b''.join(cases[i][1] for i in current);name=f'part-{len(chunks)}.bin';(w/name).write_bytes(data);chunks.append(dict(file=name,cases=current,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()));current=[];current_size=16
 for i,(_,data,_) in enumerate(cases):
  if current_size+len(data)>950000:flush()
  current.append(i);current_size+=len(data)
 flush();report=dict(cases=len(cases),association_cases=len(methods),observations=sum(len(x[2]) for x in cases),parts=chunks,case_details=[dict(label=l,returns=r) for l,_,r in cases],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('Generated',len(cases),'peer scenarios;',len(methods),'association selections;',report['observations'],'observations;',len(chunks),'complete firmware batches')
if __name__=='__main__':main()
