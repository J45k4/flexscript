#!/usr/bin/env python3
"""Independent host-privacy/AES and composed session-admission reference.

Core5.4 Vol6B1.3.2/Vol3C10.8.2 supplies address/hash rules. The unresolved
bucket, immutable pending/confirmed view and penalty inheritance are local policy.
Python cryptography provides AES independently of native OpenSSL/target MbedTLS.
"""
import argparse,copy,hashlib,importlib.util,json,random,struct,sys
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('privacy_owner_peer',ROOT/'tests/esp32/smp-session-vectors.py');O=importlib.util.module_from_spec(spec);sys.modules[spec.name]=O;spec.loader.exec_module(O);R=O.R;BUCKET=R.BUCKET;MAX=2**63-1
def q(*x):return struct.pack('<'+'q'*len(x),*x)
def address(p):
 if len(p)!=7 or p[0] not in [0,1]:return False
 if p[0]==0:return True
 kind=p[6]>>6
 if kind==2:return False
 n=int.from_bytes(p[4:] if kind==1 else p[1:],'little')&((1<<(22 if kind==1 else 46))-1)
 return n not in [0,(1<<(22 if kind==1 else 46))-1]
def identity(p):return address(p) and (p[0]==0 or p[6]>>6==3)
def ah(key,prand):return Cipher(algorithms.AES(key[::-1]),modes.ECB()).encryptor().update(bytes(13)+prand[::-1])[-3:][::-1]
def rpa(key,n):
 prand=((n&0x3fffff)|0x400000).to_bytes(3,'little');assert 0<(n&0x3fffff)<0x3fffff;return b'\1'+ah(key,prand)+prand
def row(id,key=None,confirmed=False):return id+bytes([int(key is not None)+2*confirmed])+(key if key is not None else bytes(16))+bytes(8)
def table_valid(data,count):
 if not 0<=count<=32 or len(data)!=count*32:return False
 ids=set()
 for i in range(count):
  p=data[i*32:(i+1)*32];id=p[:7];f=p[7]
  if not identity(id) or f>3 or any(p[24:]) or (not f&1 and any(p[8:24])) or id in ids:return False
  ids.add(id)
 return True
def resolve(peer,rows,count,fail):
 output=bytes([165])*32
 if not address(peer) or not table_valid(rows,count):return -22,output,0,0
 calls=0;found=[]
 for i in range(count):
  p=rows[i*32:(i+1)*32];match=False
  if identity(peer):match=peer==p[:7]
  elif peer[6]>>6==1 and p[7]&1:
   calls+=1
   if calls==fail:return -32,output,calls,608
   match=ah(p[8:24],peer[4:])==peer[1:4]
  if match:found.append((i,p))
 if len(found)>1:return -129,output,calls,608
 result=BUCKET+b'\0'+bytes(24)
 if found:
  i,p=found[0];confirmed=bool(p[7]&2);result=(p[:7] if confirmed else BUCKET)+b'\0'+p[:7]+bytes([2 if confirmed else 1])+q(i+1,0)
 return 0,result,calls,608
class Peer:
 def __init__(self):
  self.owner=O.Owner();self.owner.p.links=2;self.owner.p.slots=[None]*2;self.owner.rows=[None]*2;self.output=bytes([165])*32;self.calls=0;self.used=0
 def command(self,op,t=1,a=0,b=0,c=0,d=0,now=0,data=b''):
  self.output=bytes([165])*32;self.calls=0;self.used=0;o=self.owner
  if op==1:
   peer,rows=data[:7],data[7:]
   if b:return -22
   result,self.output,self.calls,self.used=resolve(peer,rows,a,c);return result
  if op==2:
   status=o.check()
   if status:return status
   local,peer,cfg,rows=data[:7],data[7:14],data[14:22],data[22:];role=b>>8;variant=b&255
   if variant or not 0<=a<=32 or not address(local) or not address(peer):return -22
   shadow=copy.deepcopy(o);pre=shadow.command(1,t,a=role,now=now,data=local+peer+cfg+BUCKET)
   if pre:return pre
   result,res,self.calls,_=resolve(peer,rows,a,c);self.used=640
   if result:return result
   return o.command(1,t,a=role,now=now,data=local+peer+cfg+res[:7])
  if op==3:
   if a not in [0,1] or not identity(data):return -22
   self.used=16;keys=(BUCKET+data) if a else (data+BUCKET);return o.r.command(13,t=now,data=keys)
  if op==4:return o.r.command(2,t=now,data=data)
  mapped={5:2,6:3,7:10,8:4,9:6,10:18,15:9,16:16}
  return o.command(mapped[op],t,a=a,b=b,now=now,data=data)
 def observe(self,t,result,data):
  o=self.owner;p=o.p;r=o.r;status=o.check();owned=o.find(t);link=o.link(t);ps=p.observe(t,result);rs=r.observe(0);v=bytearray(816)
  v[:56]=q(result,self.calls,self.used,1,1,1,status or (0 if owned else -107));v[56:312]=bytes([165])*256
  if not status and owned:v[56:280]=ps[40:264];v[280:312]=q(owned['lease'])+owned['id']+b'\0'+q(owned['denied'],o.now)
  v[312:344]=self.output;v[344:384]=q(r.now,r.floor,o.now,p.now,sum(x is not None for x in o.rows));v[384:640]=rs[200:456]
  for i,row in enumerate(o.rows):
   if row:v[640+i*32:672+i*32]=q(row['token'],row['lease'])+row['id']+b'\0'+q(row['denied'])
  v[704:712]=ps[264:272];v[712:784]=ps[272:344];v[784:816]=q(int(not link or not link.secret),1,o.fault,sum((i+1)*x for i,x in enumerate(data)));return bytes(v)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);args=p.parse_args();w=Path(args.work);w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();cases=[]
 def case(label,commands):
  model=Peer();body=bytearray();returns=[]
  for op,kw in commands:
   data=kw.get('data',b'');result=model.command(op,**kw);t=kw.get('t',1);obs=model.observe(t,result,data);assert len(obs)==816;body+=q(op,t,kw.get('a',0),kw.get('b',0),kw.get('now',0),len(data),kw.get('c',0),kw.get('d',0))+data+obs;returns.append(result)
  cases.append((label,q(len(body)+16,len(commands))+body,returns))
 def C(op,t=1,**kw):return op,dict(t=t,**kw)
 irk=bytes.fromhex('ec0234a357c8ad05341010a60a397d9b')[::-1];official=rpa(irk,0x308194);assert official[1:4]==bytes.fromhex('0dfbaa')[::-1]
 local=bytes([0,1,2,3,4,5,6]);config=bytes([1,0,13,16,7,7,7,0]);id=R.ident(1)
 def opening(token=1,peer=official,records=b'',role=1,now=0,fail=0,level=0):return C(2,token,a=len(records)//32,b=role<<8,c=fail,d=level,now=now,data=local+peer+config+records)
 for confirmed in [False,True]:
  for has_irk in [False,True]:
   records=row(id,irk if has_irk else None,confirmed)
   for peer in [id,official,R.ident(99),R.static(7),bytes([1,7,8,9,10,11,0])]:case('address-class-'+str((confirmed,has_irk,peer.hex())),[C(1,a=1,data=peer+records),opening(peer=peer,records=records),C(6,data=bytes([1,1,0,13,16,7,7])),C(7,now=1)])
 for peer in [bytes([2,1,2,3,4,5,6]),bytes([1,1,2,3,4,5,0x80]),bytes([1,0,0,0,0,0,0xc0]),bytes([1,255,255,255,255,255,255]),bytes([1,1,2,3,0,0,0x40]),bytes([1,1,2,3,255,255,0x7f]),bytes(7)]:case('address-validation-'+peer.hex(),[C(1,data=peer),opening(peer=peer)])
 for confirmed in [False,True]:
  rec=row(R.static(9),irk,confirmed);case('static-bond-identity-'+str(confirmed),[C(1,a=1,data=official+rec),C(1,a=1,data=R.static(9)+rec),opening(records=rec),C(6,data=bytes([1,1,0,13,16,7,7])),C(7,now=1)])
 for private in [official,bytes([1,7,8,9,10,11,0])]:
  rec=row(private,irk,True);case('reject-private-canonical-record-'+private.hex(),[C(1,a=1,data=official+rec),opening(records=rec)])
 good=row(id,irk,True)
 for offset,value,label in [(0,b'\2','identity-kind'),(6,b'\x80','identity-private'),(7,b'\4','flag-RFU'),(7,b'\5','flag-RFU-with-present-IRK'),(24,b'\1','reserved'),(7,b'\2','orphan-IRK')]:
  rec=bytearray(good);rec[offset:offset+len(value)]=value;case('bad-view-'+label,[C(1,a=1,data=official+bytes(rec)),opening(records=bytes(rec))])
 case('duplicate-canonical-view',[C(1,a=2,data=official+good+good),opening(records=good+good)])
 for count in [-1,33,MAX]:case('view-count-boundary-'+str(count),[C(1,a=count,data=official+good),C(2,a=count,b=256,data=local+official+config+good)])
 zero_key=bytes(16);zero_view=row(id,zero_key,True);case('explicit-zero-IRK',[C(1,a=1,data=rpa(zero_key,0x123456)+zero_view),opening(peer=rpa(zero_key,0x123456),records=zero_view)])
 duplicate=good+row(R.ident(2),irk,True);case('ambiguous-RPA',[C(1,a=2,data=official+duplicate),opening(records=duplicate),C(5),C(7)])
 for variant in range(1,9):case('resolver-alias-cap-null-'+str(variant),[C(1,a=1,b=variant,data=official+good)])
 case('isolated-peer-output-alias',[C(1,a=1,b=9,data=official+bytes(64)+good)])
 for variant in range(1,5):case('open-alias-cap-'+str(variant),[C(2,a=1,b=256+variant,data=local+official+config+good)])
 rng=random.Random(0x464)
 for n in range(80):
  keys=[rng.randbytes(16) for _ in range(rng.randrange(1,9))];which=rng.randrange(len(keys));records=b''.join(row(R.ident(i+1),key,bool(rng.randrange(2))) for i,key in enumerate(keys));peer=rpa(keys[which],rng.randrange(1,0x3fffff));case('differential-RPA-'+str(n),[C(1,a=len(keys),data=peer+records)])
 keys=[rng.randbytes(16) for _ in range(32)];keys[15]=irk;maximum=b''.join(row(R.ident(i+1),key,True) for i,key in enumerate(keys));last=rpa(keys[-1],0x123456)
 for level in range(16):
  case('all32-and-PS-'+str(level),[C(1,a=32,d=level,data=last+maximum)])
  for fail in range(1,33):case('AES-failure-'+str((level,fail)),[C(1,a=32,c=fail,d=level,data=last+maximum),opening(token=1,peer=last,records=maximum,fail=fail,level=level)])
 # Pending entries never select a canonical bucket; all unknown address kinds
 # share one lease, including across changed RPAs and physical reconnects.
 pending=row(id,irk,False);known=row(id,irk,True);other=rpa(irk,0x123456)
 case('unknown-churn-and-global-lease',[opening(),C(6,data=bytes([1,1,0,13,16,7,7])),C(16,a=90),opening(token=2,peer=other),C(6,2,data=bytes([1,1,0,13,16,7,7])),C(7,2,now=1),C(7,now=2),C(4,now=2,data=BUCKET),opening(token=3,peer=R.ident(98),now=3),C(5,3,now=3),C(6,3,now=4,data=bytes([1,1,0,13,16,7,7])),C(7,3,now=5),C(4,now=5,data=BUCKET)])
 case('pending-to-confirmed-retains-history',[opening(records=pending),C(6,data=bytes([1,1,0,13,16,7,7])),C(3,a=1,data=id),C(7,now=10),C(3,a=1,now=10,data=id),opening(token=2,peer=other,records=known,now=11),C(6,2,now=11,data=bytes([1,1,0,13,16,7,7])),C(4,now=11,data=id),C(4,now=11,data=BUCKET),C(7,2,now=12),opening(token=3,peer=other,records=known,now=1010),C(6,3,now=1010,data=bytes([1,1,0,13,16,7,7])),C(7,3,now=1011),C(3,a=0,now=1011,data=id),C(4,now=1011,data=BUCKET)])
 case('open-link-keeps-key-after-view-changes',[opening(records=pending),C(1,a=1,data=official+known),C(6,data=bytes([1,1,0,13,16,7,7])),C(7,now=1),C(4,now=1,data=BUCKET),C(3,a=1,now=1,data=id),opening(token=2,records=known,now=2),C(6,2,now=2,data=bytes([1,1,0,13,16,7,7])),C(7,2,now=3)])
 case('known-peer-independent-of-unresolved',[opening(),C(6,data=bytes([1,1,0,13,16,7,7])),opening(token=2,records=known),C(6,2,data=bytes([1,1,0,13,16,7,7])),C(7,now=1),C(7,2,now=2),C(4,now=2,data=BUCKET),C(4,now=2,data=id)])
 parts=[];batch=[];indices=[];size=16
 def flush():
  if not batch:return
  blob=b'SMPPRIV1'+q(len(batch))+b''.join(batch);name=f'part-{len(parts)}.bin';(w/name).write_bytes(blob);parts.append(dict(file=name,bytes=len(blob),cases=indices[:],checks=sum(len(cases[i][2]) for i in indices),sha256=hashlib.sha256(blob).hexdigest()))
 for i,(_,blob,_) in enumerate(cases):
  if size+len(blob)>950000:flush();batch=[];indices=[];size=16
  batch.append(blob);indices.append(i);size+=len(blob)
 flush();report=dict(cases=len(cases),checks=sum(len(c[2]) for c in cases),parts=parts,labels=[dict(label=l,returns=rs) for l,_,rs in cases],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',report['cases'],'privacy scenarios;',report['checks'],'independent observations;',len(parts),'parts')
if __name__=='__main__':main()
