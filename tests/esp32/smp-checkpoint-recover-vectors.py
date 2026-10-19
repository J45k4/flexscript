#!/usr/bin/env python3
"""Independent raw-NOR snapshots, CMAC frames and cold-recovery expectations."""
import argparse,hashlib,json,struct,zlib
from pathlib import Path
from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import algorithms
KEY=bytes(range(16));SCOPE=b'recovery-scope01';MAX=(1<<63)-1
def tag(data):
 c=cmac.CMAC(algorithms.AES(KEY));c.update(data);return c.finalize()
def payload(e,live=False,seed=1):
 h=b'SMPTRY01'+struct.pack('<7q',e,1000,7000,60000,max(5,e),e,0);records=[]
 for i in range(e):
  identity=bytes([0,(seed+i)&255,2,3,4,5,6]);records.append(identity+b'\0'+struct.pack('<4q',1000,0 if live else 500,60000,int(live)))
 return h+b''.join(records)
def frame(e,seq,rev=None,body=None,scope=SCOPE):
 body=payload(e) if body is None else body;h=b'FSMPCK01'+struct.pack('<3q',seq,1000+seq if rev is None else rev,len(body))+scope;return h+body+tag(h+body)
def bank(f,generation,extra=False):
 records=[]
 if extra:records.append(struct.pack('<BBHI',1,1,0,1)+b'a'+b'X'+b'\xff'*2)
 if f is not None:
  record=struct.pack('<BBHI',9,66,0,len(f))+b'smp.retry'+f;record+=b'\xff'*((-len(record))%4);records.append(record)
 body=b''.join(records);h=struct.pack('<6I',0x564b5846,1,generation&0xffffffff,len(body),len(records),zlib.crc32(body));h+=struct.pack('<II',zlib.crc32(h),0x3cc35aa5);return h+body+b'\xff'*(4096-len(h)-len(body))
def parse_bank(b):
 magic,version,generation,used,count,body_crc,header_crc,marker=struct.unpack_from('<8I',b)
 if magic!=0x564b5846 or version!=1 or marker!=0x3cc35aa5 or header_crc!=zlib.crc32(b[:24]) or used>4064 or used%4 or count>128 or body_crc!=zlib.crc32(b[32:32+used]):return None
 records={};at=32;previous=b''
 while at<used+32:
  if at+8>used+32:return None
  kn,typ,res,n=struct.unpack_from('<BBHI',b,at);end=at+8+kn+n;padded=(end+3)&~3
  if not 1<=kn<=63 or typ==0 or res or padded>used+32:return None
  key=b[at+8:at+8+kn]
  if key<=previous or any(x!=255 for x in b[end:padded]):return None
  records[key]=(typ,b[at+8+kn:end]);previous=key;at=padded
 if at!=used+32 or len(records)!=count:return None
 return generation,records
class Fault(Exception):
 def __init__(self,code):self.code=code
def semantic(b,e,floor,now):
 if len(b)!=64+40*e or b[:8]!=b'SMPTRY01':raise Fault(-74)
 be,mi,ma,de,gen,count,res=struct.unpack_from('<7q',b,8)
 if (be,mi,ma,de)!=(e,1000,7000,60000) or gen<0 or not 0<=count<=e or res:raise Fault(-74)
 if gen<floor:raise Fault(-116)
 out=bytearray(128+64*e);seen=set()
 for i in range(count):
  p=b[64+40*i:104+40*i];identity=p[:7];delay,wait,decay,live=struct.unpack_from('<4q',p,8)
  identity_ok=identity[0]==0 or (identity[0]==1 and identity[6]&192==192) or identity==b'\2'+b'\0'*6
  if not identity_ok or p[7] or not (delay==0 or 1000<=delay<=7000) or not 0<=wait<=7000 or not 0<=decay<=60000 or bool(delay)!=bool(decay) or live not in [0,1] or (live and (wait or not gen)) or not (delay or wait or live) or identity in seen:raise Fault(-74)
  seen.add(identity)
  if live:delay=min(7000,delay*2) if delay else 1000;wait=delay;decay=60000
  struct.pack_into('<5q',out,128+64*i,1,delay,now+wait,now+decay if delay else 0,0);out[168+64*i:175+64*i]=identity
 if any(b[64+40*count:]):raise Fault(-74)
 return bytes(out),gen
def model(banks,e,anchor,mode=0,fail=0,floor=0):
 calls=0;loads=1;advances=0;current=anchor;seq=rev=0;now=0;ledger=bytes(128+64*e);restored_floor=floor
 def decode(f):
  nonlocal calls
  if len(f)!=128+40*e or f[:8]!=b'FSMPCK01':raise Fault(-74)
  s,r,n=struct.unpack_from('<3q',f,8)
  if s<1 or r<1 or n!=64+40*e or f[32:48]!=SCOPE:raise Fault(-74)
  cost=1+(48+n+15)//16
  if calls<fail<=calls+cost:calls=fail;raise Fault(-32)
  calls+=cost
  if tag(f[:-16])!=f[-16:]:raise Fault(-74)
  result,_=semantic(f[48:-16],e,floor,0)
  return s,r
 try:
  if mode==1:raise Fault(-5)
  if mode==2 or anchor<0:raise Fault(-116)
  if mode==3 or anchor==MAX:raise Fault(-75)
  parsed=[parse_bank(b) for b in banks];selected=None
  for value in parsed:
   if value is None or b'smp.retry' not in value[1]:continue
   typ,f=value[1][b'smp.retry']
   if typ!=66:raise Fault(-74)
   s,r=decode(f)
   if s>anchor+1:raise Fault(-116)
   if selected is not None and s==seq and selected!=f:raise Fault(-74)
   if s>seq:selected=f;seq,rev=s,r
  if not any(x is not None for x in parsed):raise Fault(-61 if all(b==b'\xff'*4096 for b in banks) else -74)
  if selected is None:raise Fault(-61 if anchor==0 else -116)
  if seq<anchor:raise Fault(-116)
  decode(selected)
  if parsed[0] is not None and parsed[1] is not None:
   delta=(parsed[1][0]-parsed[0][0])&0xffffffff
   if delta==0:
    used=struct.unpack_from('<I',banks[0],12)[0];used1=struct.unpack_from('<I',banks[1],12)[0]
    if used!=used1 or banks[0][:used+32]!=banks[1][:used1+32]:raise Fault(-74)
    chosen=0
   elif delta==0x80000000:raise Fault(-74)
   else:chosen=int(delta<0x80000000)
  else:chosen=0 if parsed[0] is not None else 1
  active=parsed[chosen][1].get(b'smp.retry')
  if active!=(66,selected):raise Fault(-116)
  if seq==anchor+1:
   advances=1
   if mode==4:raise Fault(-5)
   current=seq
   if mode==5:raise Fault(-5)
   if mode==6:raise Fault(-116)
  loads+=1
  if mode==10:raise Fault(-16)
  if mode==11:raise Fault(-116)
  if mode==7:raise Fault(-5)
  if mode==8:raise Fault(-116)
  decode(selected);now=30 if advances else 20;ledger,restored_floor=semantic(selected[48:-16],e,floor,now);status=0
 except Fault as x:status=x.code;seq=rev=0;now=0
 return (mode,fail,e,anchor,floor,status,seq,rev,current,loads,advances,now,restored_floor,calls,len(ledger)),ledger
def generate():
 cases=[]
 def add(name,e=4,anchor=10,banks=None,mode=0,fail=0,floor=0):
  banks=banks or [bank(frame(e,10,body=payload(e,seed=1)),10),bank(frame(e,11,body=payload(e,live=True,seed=33)),11)]
  expected,ledger=model(banks,e,anchor,mode,fail,floor);body=KEY+SCOPE+b''.join(banks);checksum=sum((i+1)*x for i,x in enumerate(body));header=struct.pack('<18q',*expected,checksum,8192,len(cases));cases.append((name,header+body+ledger))
 for e in range(1,33):
  add(f'pending-{e}',e=e)
  add(f'already-advanced-{e}',e=e,anchor=11)
 add('reversed-raw-bank-order',banks=[bank(frame(4,11,body=payload(4,live=True,seed=33)),11),bank(frame(4,10),10)])
 add('explicit-first-frame-candidate',anchor=0,banks=[bank(None,1),bank(frame(4,1),2)])
 add('same-frame-duplicate',banks=[bank(frame(4,10),10)]*2)
 add('same-sequence-different-authenticated-history',banks=[bank(frame(4,10),10),bank(frame(4,10,body=payload(4,seed=70)),11)])
 add('future-gap',banks=[bank(frame(4,10),10),bank(frame(4,12),12)])
 add('only-stale-checkpoint',anchor=11,banks=[bank(frame(4,9),9),bank(frame(4,10),10)])
 add('no-frame-provisioned',anchor=0,banks=[bank(None,1),b'\xff'*4096])
 add('anchor-with-no-frame',banks=[bank(None,1),b'\xff'*4096])
 add('erased-requires-explicit-provisioning',anchor=0,banks=[b'\xff'*4096]*2)
 add('corrupt-unformatted-banks',banks=[bytes(4096)]*2)
 add('generation-and-sequence-disagree',banks=[bank(frame(4,10),11),bank(frame(4,11),10)])
 add('generation-wrap',banks=[bank(frame(4,10),0xffffffff),bank(frame(4,11),0)])
 add('half-wrap-ambiguous',banks=[bank(frame(4,10),0),bank(frame(4,11),0x80000000)])
 add('same-generation-conflicting-store',banks=[bank(frame(4,10),10),bank(frame(4,10),10,True)])
 for mode in [1,2,3,4,5,6,7,8,9,10,11,14]:add(f'provider-mode-{mode}',mode=mode)
 add('lease-floor-rollback',floor=6)
 f=frame(4,11)
 for label,offset in [('domain',0),('scope',32),('tag',len(f)-1),('payload',80)]:
  bad=bytearray(f);bad[offset]^=1;add('corrupt-'+label,banks=[bank(frame(4,10),10),bank(bytes(bad),11)])
 for offset in [16,24,32,40,48,56,64,71,72,80,88,96,104]:
  b=bytearray(payload(4));b[offset]^=128;add('authenticated-malformed-ledger-'+str(offset),banks=[bank(frame(4,10),10),bank(frame(4,11,body=bytes(b)),11)])
 b=bytearray(payload(4));b[104:111]=b[64:71];add('duplicate-ledger-identities',banks=[bank(frame(4,10),10),bank(frame(4,11,body=bytes(b)),11)])
 bad=bytearray(bank(f,11));bad[90]^=1
 add('corrupt-new-bank-retains-anchor-frame',banks=[bank(frame(4,10),10),bytes(bad)])
 add('corrupt-new-bank-after-anchor-advance',anchor=11,banks=[bank(frame(4,10),10),bytes(bad)])
 old=bank(frame(4,9),9);trusted=bank(frame(4,10),10);new=bank(frame(4,11,body=payload(4,live=True,seed=33)),11);used=struct.unpack_from('<I',new,12)[0]
 for cut in [0,1,4,28,32,128,256,2048,4095,4096]:add(f'erase-cut-{cut}',banks=[b'\xff'*cut+old[cut:],trusted])
 for cut in range(29):add(f'header-program-cut-{cut}',banks=[new[:cut]+b'\xff'*(4096-cut),trusted])
 for cut in range(used+1):
  torn=bytearray(b'\xff'*4096);torn[:28]=new[:28];torn[32:32+cut]=new[32:32+cut];add(f'body-program-cut-{cut}',banks=[bytes(torn),trusted])
 for cut in range(5):
  torn=bytearray(new);torn[28+cut:32]=b'\xff'*(4-cut);add(f'commit-marker-cut-{cut}',banks=[bytes(torn),trusted])
 add('power-loss-after-counter-advance',anchor=11,banks=[new,trusted])
 for fail in range(1,353):add(f'max-frame-AES-error-{fail}',e=32,fail=fail)
 return cases
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work);w.mkdir(parents=True,exist_ok=True);cases=generate();parts=[];rows=[];labels=[];size=16
 def flush():
  nonlocal rows,labels,size
  if not rows:return
  data=b'SMPREC01'+struct.pack('<q',len(rows))+b''.join(rows);name=f'part-{len(parts)}.bin';(w/name).write_bytes(data);parts.append(dict(file=name,cases=len(rows),sha256=hashlib.sha256(data).hexdigest(),labels=labels));rows=[];labels=[];size=16
 for label,row in cases:
  if size+len(row)>850000:flush()
  rows.append(row);labels.append(label);size+=len(row)
 flush();(w/'report.json').write_text(json.dumps(dict(cases=len(cases),parts=parts,NOR_program_prefix_cuts=343,NOR_erase_prefix_cuts=10,max_frame_AES_error_positions=352,physical_media=False,anchor_is_test_peer=True),indent=2)+'\n');print('Generated',len(cases),'recovery cases in',len(parts),'parts')
if __name__=='__main__':main()
