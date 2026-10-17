#!/usr/bin/env python3
"""Independent OpenSSL P-256/CMAC peer transcripts for SC JW and NC."""
import argparse,hashlib,json,random,runpy,struct
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
ROOT=Path(__file__).resolve().parents[2]
derive=runpy.run_path(str(ROOT/'tests/esp32/smp-crypto-vectors.py'))['derive']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
 rng=random.Random(0x53435032);cases=[];labels=[]
 for role in range(2):
  for numeric in range(2):
   keys=[ec.derive_private_key(int.from_bytes(rng.randbytes(31),'big')+1,ec.SECP256R1()) for _ in range(2)]
   pub=lambda k:k.public_key().public_numbers().x.to_bytes(32,'little')+k.public_key().public_numbers().y.to_bytes(32,'little')
   pa,pb=map(pub,keys);na,nb=rng.randbytes(16),rng.randbytes(16);dh=keys[0].exchange(ec.ECDH(),keys[1].public_key())[::-1]
   aa=bytes.fromhex('00010203040506');ab=bytes.fromhex('010a0b0c0d0ec0');io=bytes([1 if numeric else 3,0,13 if numeric else 9]);mkltk=derive(2,[dh,na,nb,aa,ab]);mk,ltk=mkltk[:16],mkltk[16:]
   cb=derive(1,[pb[:32],pa[:32],nb]);ea=derive(3,[mk,na,nb,bytes(16),io,aa,ab]);eb=derive(3,[mk,nb,na,bytes(16),io,ab,aa]);number=int.from_bytes(derive(4,[pa[:32],pb[:32],na,nb]),'little')%1000000
   rows=[]
   def record(op,arg=0,result=0,data=b'',random=b'',tx=b'',state=-1,prompt=-1,flags=0):
    n=len(tx) if isinstance(tx,bytes) else tx;tx=tx if isinstance(tx,bytes) else b''
    return struct.pack('<8q',op,arg,result,len(data),n,state,prompt,flags)+data.ljust(96,b'\0')+random.ljust(32,b'\0')+tx.ljust(72,b'\0')+ltk
   def add(*args,**kwargs):rows.append(record(*args,**kwargs))
   def case(name,entries):
    assert all(len(row)==280 for row in entries)
    cases.append(struct.pack('<4q',role,numeric,len(entries),0)+b''.join(entries));labels.append(dict(name=name,rows=len(entries)))
   own=pa if not role else pb;peer=pb if not role else pa;nonce=na if not role else nb
   add(1,random=keys[role].private_numbers().private_value.to_bytes(32,'big'),tx=b'\x0c'+own if not role else b'',state=2 if not role else 3)
   if not role:add(3,state=3)
   add(2,result=1,data=b'\x0c'+peer,random=nonce+bytes(16),tx=b'\x0c'+own if role else b'',state=2 if role else 4)
   if role:
    add(3,tx=b'\x03'+cb,state=2);add(3,state=5)
    add(2,result=1,data=b'\x04'+na,tx=b'\x04'+nb,state=2,prompt=number if numeric else -1)
    if numeric:add(4,arg=1,result=-11,tx=b'\x04'+nb,state=2,prompt=number)
    add(3,state=7 if numeric else 8,prompt=number if numeric else -1)
    if numeric:
     add(2,result=-11,data=b'\x0d'+ea,state=7,prompt=number);add(4,arg=1,state=8)
    add(2,result=1,data=b'\x0d'+ea,tx=b'\x0d'+eb,state=2)
    add(3,state=10,flags=1)
   else:
    add(2,result=1,data=b'\x03'+cb,tx=b'\x04'+na,state=2);add(3,state=6)
    add(2,result=1,data=b'\x04'+nb,tx=b'' if numeric else b'\x0d'+ea,state=7 if numeric else 2,prompt=number if numeric else -1)
    if numeric:add(4,arg=1,tx=b'\x0d'+ea,state=2)
    add(3,state=9);add(2,result=1,data=b'\x0d'+eb,state=10,flags=1)
   name=f'{"responder" if role else "initiator"}-{"numeric" if numeric else "justworks"}'
   case(name,rows)
   second=ec.derive_private_key(keys[role].private_numbers().private_value+1,ec.SECP256R1());second_bytes=second.private_numbers().private_value.to_bytes(32,'little')+pub(second)
   case(name+'-two-live-sessions',rows[:1]+[record(9,random=second.private_numbers().private_value.to_bytes(32,'big'),data=second_bytes,tx=b'\x0c'+own if not role else b'',state=2 if not role else 3,flags=8)]+rows[1:]+[record(12,data=second_bytes,state=10,flags=9)])
   # Terminal storage failure must erase active and unused reserved slots now.
   case(name+'-storage-fault',rows[:1]+[record(6,result=-5,tx=-1,state=0,flags=2)])
   case(name+'-timeout',rows[:1]+[record(5,arg=30000,tx=-110,state=0,flags=4)])
   case(name+'-peer-failed',rows[:1]+[record(2,result=1,data=b'\x05\x08',tx=0,state=0,flags=4)])
   peer_at=1 if role else 2
   # Each rejected transcript is independently formed from the valid prefix.
   for label,point,reason in [('reflection',own,10),('off-curve',bytes(64),11),('debug',bytes.fromhex('20b003d2f297be2c5e2c83a7e9f9a5b9eff49111acf4fddbcc0301480e359de6')[::-1]+bytes.fromhex('dc809c49652aeb6d63329abf5a52155c766345c28fed3024741c8ed01589d28b')[::-1],10)]:
    case(name+'-'+label,rows[:peer_at]+[record(2,result=1,data=b'\x0c'+point,tx=-11,state=0,flags=4),record(8,tx=bytes([5,reason]),state=0,flags=4)])
   # Exact TX tags reject delayed or future completions without consuming TX.
   ack_at=2 if role else 1;pending=b'\x0c'+own
   case(name+'-stale-tx',rows[:ack_at]+[record(3,arg=-1,result=-116,tx=pending,state=2),record(3,arg=1,result=-116,tx=pending,state=2)]+rows[ack_at:])
   delayed_at=3 if role else 4;pending=b'\x03'+cb if role else b'\x04'+na
   case(name+'-previous-tx-tag',rows[:delayed_at]+[record(3,arg=-2,result=-116,tx=pending,state=2)]+rows[delayed_at:])
   bad_dh_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==13 and struct.unpack_from('<q',row,16)[0]==1)
   bad=bytearray(ea if role else eb);bad[0]^=1
   case(name+'-bad-dhcheck',rows[:bad_dh_at]+[record(2,result=1,data=b'\x0d'+bad,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x0b',state=0,flags=4)])
   if not role:
    random_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==4)
    bad=bytearray(nb);bad[0]^=1
    case(name+'-bad-commitment',rows[:random_at]+[record(2,result=1,data=b'\x04'+bad,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x04',state=0,flags=4)])
   if numeric:
    decision_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==4)
    case(name+'-numeric-reject',rows[:decision_at]+[record(4,arg=0,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x0c',state=0,flags=4)])
    accepted_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==4 and struct.unpack_from('<q',row,16)[0]==0)
    case(name+'-stale-approval',rows[:accepted_at]+[record(10,arg=0,result=-116,state=7,prompt=number),record(10,arg=1,result=-116,state=7,prompt=number)]+rows[accepted_at:])
   for pos in [1,2]:
    failed=record(2,arg=100+pos,result=-11,data=b'\x0c'+peer,random=nonce+bytes(16),state=3)
    case(name+f'-curve-transient-{pos}',rows[:peer_at]+[failed]+rows[peer_at:])
    failed=record(2,arg=200+pos,result=-32,data=b'\x0c'+peer,random=nonce+bytes(16),tx=-11,state=0,flags=4)
    case(name+f'-curve-error-{pos}',rows[:peer_at]+[failed,record(8,tx=b'\x05\x08',state=0,flags=4)])
   case(name+'-nonce-error',rows[:peer_at]+[record(2,arg=300,result=-5,data=b'\x0c'+peer,random=nonce+bytes(16),tx=-11,state=0,flags=4),record(8,tx=b'\x05\x08',state=0,flags=4)])
   for when,at,op,data,entropy in [('keygen',0,1,b'',keys[role].private_numbers().private_value.to_bytes(32,'big')),('nonce',peer_at,2,b'\x0c'+peer,nonce+bytes(16))]:
    for mode,expect in [(400,-5),(401,-110),(402,-5)]:
     case(name+f'-{when}-lifetime-{mode}',rows[:at]+[record(op,arg=mode,result=expect,data=data,random=entropy,tx=expect,state=0,flags=4)])
   # Enumerate every AES boundary while verifying random or deriving both checks.
   crypto_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==4)
   if numeric:crypto_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==4 and struct.unpack_from('<q',row,16)[0]==0)
   original=rows[crypto_at];op=struct.unpack_from('<q',original)[0];data=original[64:64+struct.unpack_from('<q',original,24)[0]]
   count=25+(6 if not numeric and not role else 0)
   for pos in range(1,count+1):
    case(name+f'-aes-error-{pos}',rows[:crypto_at]+[record(op,arg=500+pos,result=-32,data=data,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x08',state=0,flags=4)])
 payload=struct.pack('<2Q',0x315343504d53,len(cases))+b''.join(cases);(w/'cases.bin').write_bytes(payload);parts=[]
 for start in range(0,len(cases),16):
  subset=cases[start:start+16];data=struct.pack('<2Q',0x315343504d53,len(subset))+b''.join(subset);name=f'part-{len(parts)}.bin';(w/name).write_bytes(data);parts.append(dict(file=name,cases=len(subset),sha256=hashlib.sha256(data).hexdigest()))
 (w/'report.json').write_text(json.dumps(dict(cases=labels,sha256=hashlib.sha256(payload).hexdigest(),parts=parts),indent=2)+'\n');print('Generated',len(cases),'SC peer cases')
if __name__=='__main__':main()
