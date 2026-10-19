#!/usr/bin/env python3
"""Independent SC OOB ticket and one-/two-direction wire peers."""
import argparse,hashlib,json,random,runpy,struct,subprocess,sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
ROOT=Path(__file__).resolve().parents[2]
derive=runpy.run_path(str(ROOT/'tests/esp32/smp-crypto-vectors.py'))['derive']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);p.add_argument('--only-oob',action='store_true');a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);cases=[];labels=[]
 if not a.only_oob:
  base=w/'baseline';subprocess.run([sys.executable,str(ROOT/'tests/esp32/smp-passkey-vectors.py'),'--work',str(base)],check=True);prior=json.loads((base/'report.json').read_text());raw=(base/'cases.bin').read_bytes();at=16;labels=prior['cases'][:]
  for item in labels:
   n=struct.unpack_from('<q',raw,at+16)[0];end=at+32+n*280;cases.append(raw[at:end]);at=end
  assert at==len(raw)
 baseline=len(cases);rng=random.Random(0x4f4f4231);proof=b'OBPROOF1'
 for role in range(2):
  for direction in [1,2,3]:
   keys=[ec.derive_private_key(int.from_bytes(rng.randbytes(31),'big')+1,ec.SECP256R1()) for _ in range(2)]
   def pub(k):n=k.public_key().public_numbers();return n.x.to_bytes(32,'little')+n.y.to_bytes(32,'little')
   pa,pb=map(pub,keys);own,peer=(pa,pb) if not role else (pb,pa);ra,rb,na,nb=[rng.randbytes(16) for _ in range(4)];ownr,peerr=(ra,rb) if not role else (rb,ra);ownrecord=ownr+derive(1,[own[:32],own[:32],ownr]);peerrecord=peerr+derive(1,[peer[:32],peer[:32],peerr]);localIO=bytes([3,direction&1,13]);remoteIO=bytes([3,int(bool(direction&2)),13]);ioa,iob=(localIO,remoteIO) if not role else (remoteIO,localIO);effective_own=ownr if direction&2 else bytes(16);effective_peer=peerr if direction&1 else bytes(16);era,erb=(effective_own,effective_peer) if not role else (effective_peer,effective_own)
   aa=bytes.fromhex('00010203040506');ab=bytes.fromhex('010a0b0c0d0ec0');dh=keys[0].exchange(ec.ECDH(),keys[1].public_key())[::-1];mkltk=derive(2,[dh,na,nb,aa,ab]);mk,ltk=mkltk[:16],mkltk[16:];ea=derive(3,[mk,na,nb,erb,ioa,aa,ab]);eb=derive(3,[mk,nb,na,era,iob,ab,aa])
   def record(op,arg=0,result=0,data=b'',random=b'',tx=b'',state=-1,flags=0,mode=0):
    n=len(tx) if isinstance(tx,bytes) else tx;tx=tx if isinstance(tx,bytes) else b'';assert len(data)<=88 and len(random)<=32 and len(tx)<=72
    payload=data.ljust(88,b'\0')+struct.pack('<q',mode)
    return struct.pack('<8q',op,arg,result,len(data),n,state,-1,flags)+payload+random.ljust(32,b'\0')+tx.ljust(72,b'\0')+ltk
   def case(name,rows):cases.append(struct.pack('<4q',role,10+direction,len(rows),0)+b''.join(rows));labels.append(dict(name=name,rows=len(rows)))
   def change(row,**changes):
    op,arg,result,n,tx,state,_,flags=struct.unpack_from('<8q',row);values=dict(op=op,arg=arg,result=result,data=row[64:64+n],random=row[160:192],tx=row[192:192+tx] if tx>=0 else tx,state=state,flags=flags,mode=struct.unpack_from('<q',row,152)[0]);values.update(changes);return record(**values)
   rows=[]
   def add(*args,**kw):rows.append(record(*args,**kw))
   add(39,arg=4,tx=-107)
   add(40,arg=100000,result=1,random=keys[role].private_numbers().private_value.to_bytes(32,'big'),tx=-107)
   add(41,random=ownr+bytes(16),tx=-107);add(42,data=ownrecord,tx=-107)
   witness=1
   if direction&1:add(44,arg=witness,data=peerrecord+proof,tx=-107);witness+=1
   if direction&2:add(43,arg=witness,data=proof,tx=-107)
   add(45,state=0)
   add(1,tx=b'\x0c'+own if not role else b'',state=2 if not role else 3,flags=64)
   if not role:add(3,state=3,flags=64)
   add(2,data=b'\x00',state=3,flags=64)
   add(2,result=1,data=b'\x0c'+peer,random=(na if not role else nb)+bytes(16),tx=b'\x0c'+own if role else b'\x04'+na,state=2,flags=64)
   add(3,state=19 if role else 18,flags=64)
   add(2,result=1,data=b'\x04'+(na if role else nb),tx=b'\x04'+nb if role else b'\x0d'+ea,state=2)
   add(3,state=8 if role else 9)
   add(2,result=1,data=b'\x0d'+(ea if role else eb),tx=b'\x0d'+eb if role else b'',state=2 if role else 10,flags=0 if role else 1)
   if role:add(3,state=10,flags=1)
   name=f'oob-role{role}-directions{direction}';case(name,rows)
   for n in [1,2,3]:case(name+f'-pool{n}',[change(rows[0],arg=n)]+rows[1:])
   case(name+'-missing-attestor',[record(53,arg=0,tx=-107),change(rows[0],result=-19,flags=128),record(53,arg=1,tx=-107)]+rows)
   for kind in [0,1,2,3,4]:case(name+f'-init-range-{kind}',[record(54,arg=kind,result=-22,tx=-107,flags=128)]+rows)
   for count in [0,5,-1]:case(name+f'-init-tickets-{count}',[change(rows[0],arg=count,result=-22,flags=128)]+rows)
   case(name+'-provider-rebind',[rows[0],record(53,arg=0,result=-16,tx=-107)]+rows[1:])
   opened=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==45)
   peer_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==12)
   last_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==13)
   # Possession of copied OOB bytes alone never authorizes a direction.
   case(name+'-no-proof',rows[:4]+[record(50,state=0),record(48,arg=1,result=-13,state=0)])
   for mismatch in [1,2,3]:case(name+f'-binding-{mismatch}',rows[:opened]+[record(50,arg=mismatch,state=0),record(48,arg=1,result=-13,state=0)])
   case(name+'-connection-already-open',rows[:1]+[record(50,state=0)]+[change(row,tx=0,state=0) for row in rows[1:opened]]+[record(48,arg=1,result=-116,state=0)])
   case(name+'-ticket-consumed',rows[:opened+2]+[record(49,result=-116,tx=b'\x0c'+own if not role else b'',state=2 if not role else 3,flags=64)]+rows[opened+2:])
   # Expiration before the SMP timeout revokes a live attempt andits TX view.
   short=[change(row,arg=10000) if i==1 else row for i,row in enumerate(rows)]
   case(name+'-bound-expiry',short[:peer_at]+[record(5,arg=10000,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x02',state=0)])
   if role:case(name+'-late-final-ack',short[:-1]+[record(5,arg=10000,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x02',state=0)])
   case(name+'-unbound-expiry',short[:opened]+[record(5,arg=10000,tx=-107,flags=32)])
   # Actual pool secrets must be erased before any follow-up SC poll.
   for ix in [1,2]:
    case(name+f'-entropy-fault-{ix}',rows[:ix]+[change(rows[ix],mode=400,result=-5,tx=-5,flags=32)])
   case(name+'-entropy-expiry',rows[:1]+[change(rows[1],arg=10000,mode=401,result=-110,tx=-107,flags=32)])
   case(name+'-generate-retry',rows[:2]+[change(rows[2],mode=301,result=-16)]+rows[2:])
   failed=change(rows[1],mode=101,result=-16)
   # Ticket IDs are consumed even when key generation cannot publish output.
   case(name+'-keygen-retry',rows[:1]+[failed,change(rows[1],result=2)]+rows[2:])
   for ix,row in enumerate(rows[:opened]):
    op=struct.unpack_from('<q',row)[0]
    if op not in [43,44]:continue
    for fault,expected in [(600,-13),(601,-5),(602,-116),(603,-116),(604,-116),(605,-116),(606,-5),(607,-110),(609,-116)]:
     case(name+f'-attestation-{op}-{fault}',rows[:ix]+[change(row,mode=fault,result=expected,tx=-5 if fault==606 else -107,flags=32)])
    case(name+f'-attestation-retry-{op}',rows[:ix]+[change(row,arg=-16,result=-16)]+rows[ix:])
    for level in range(16):case(name+f'-callback-ps-{op}-{level}',rows[:ix]+[change(row,mode=620+level)]+rows[ix+1:])
   if direction==3:
    first=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==44);second=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==43)
    case(name+'-witness-replay',rows[:first]+[change(rows[first],arg=2)]+rows[first+1:second]+[change(rows[second],arg=1,result=-116,flags=32)])
   # Bad commitment/point/DH-check input revokes the consumed ticket as well.
   for label,point,reason in [('offcurve',bytes(64),11),('reflected',own,10),('debug',bytes.fromhex('20b003d2f297be2c5e2c83a7e9f9a5b9eff49111acf4fddbcc0301480e359de6')[::-1]+bytes(32),10)]:
    case(name+'-'+label,rows[:peer_at]+[record(2,result=1,data=b'\x0c'+point,tx=-11,state=0,flags=36),record(8,tx=bytes([5,reason]),state=0)])
   if direction&1:
    received=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==44);bad=bytearray(peerrecord);bad[16]^=1
    case(name+'-bad-oob-commitment',rows[:received]+[change(rows[received],data=bad+proof)]+rows[received+1:peer_at]+[change(rows[peer_at],random=b'',result=1,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x04',state=0)])
   bad=bytearray(ea if role else eb);bad[0]^=1
   case(name+'-bad-dhcheck',rows[:last_at]+[record(2,result=1,data=b'\x0d'+bad,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x0b',state=0)])
   if direction==1:case(name+'-peer-false-oob-claim',rows[:opened]+[record(52,arg=3,tx=-107),change(rows[opened],result=1,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x02',state=0)])
   if direction==2:case(name+'-downgrade',rows[:opened]+[record(52,arg=0,tx=-107),change(rows[opened],result=1,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x03',state=0)])
   # No new OOB data can be attached after feature exchange starts.
   case(name+'-cancel',rows[:peer_at]+[record(46,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x02',state=0)])
   # The final DH stage can fail at each AES position without a candidate key.
   random_at=next(i for i,row in enumerate(rows) if struct.unpack_from('<q',row)[0]==2 and row[64]==4)
   for position in range(1,26):
    case(name+f'-derive-failure-{position}',rows[:random_at]+[change(rows[random_at],arg=500+position,result=-32,tx=-11,state=0,flags=36),record(8,tx=b'\x05\x08',state=0)])
 payload=struct.pack('<2Q',0x315343504d53,len(cases))+b''.join(cases);(w/'cases.bin').write_bytes(payload);parts=[];start=0
 while start<len(cases):
  count=16 if start<min(192,baseline) else 4;subset=cases[start:start+count];data=struct.pack('<2Q',0x315343504d53,len(subset))+b''.join(subset);name=f'part-{len(parts)}.bin';(w/name).write_bytes(data);parts.append(dict(file=name,cases=len(subset),sha256=hashlib.sha256(data).hexdigest()));start+=len(subset)
 (w/'report.json').write_text(json.dumps(dict(cases=labels,sha256=hashlib.sha256(payload).hexdigest(),parts=parts,baseline_cases=baseline,OOB_cases=len(cases)-baseline),indent=2)+'\n');print('Generated',len(cases)-baseline,'OOB cases')
if __name__=='__main__':main()
