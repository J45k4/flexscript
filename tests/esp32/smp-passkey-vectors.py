#!/usr/bin/env python3
"""Independent twenty-round SC passkey peer using OpenSSL P-256 and CMAC."""
import argparse,hashlib,json,random,runpy,struct,subprocess,sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
ROOT=Path(__file__).resolve().parents[2]
derive=runpy.run_path(str(ROOT/'tests/esp32/smp-crypto-vectors.py'))['derive']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
 base=w/'baseline';subprocess.run([sys.executable,str(ROOT/'tests/esp32/smp-sc-vectors.py'),'--work',str(base)],check=True);prior=json.loads((base/'report.json').read_text());raw=(base/'cases.bin').read_bytes();at=16;cases=[];labels=prior['cases'][:]
 for item in labels:
  n=struct.unpack_from('<q',raw,at+16)[0];end=at+32+n*280;cases.append(raw[at:end]);at=end
 assert at==len(raw);baseline_count=len(cases);rng=random.Random(0x50415353)
 for role in range(2):
  for display in range(2):
   for keypress in range(2):
    for passkey in [0,1,123456,999999]:
     mode=2+display+2*keypress;keys=[ec.derive_private_key(int.from_bytes(rng.randbytes(31),'big')+1,ec.SECP256R1()) for _ in range(2)]
     def pub(k):n=k.public_key().public_numbers();return n.x.to_bytes(32,'little')+n.y.to_bytes(32,'little')
     pa,pb=map(pub,keys);own,peer=(pa,pb) if not role else (pb,pa);nonces=[(rng.randbytes(16),rng.randbytes(16)) for _ in range(20)];dh=keys[0].exchange(ec.ECDH(),keys[1].public_key())[::-1]
     aa=bytes.fromhex('00010203040506');ab=bytes.fromhex('010a0b0c0d0ec0');auth=13+16*keypress;ownio=bytes([0 if display else 2,0,auth]);peerio=bytes([2 if display else 0,0,auth]);ioa,iob=(ownio,peerio) if not role else (peerio,ownio);na,nb=nonces[-1];mkltk=derive(2,[dh,na,nb,aa,ab]);mk,ltk=mkltk[:16],mkltk[16:];r=passkey.to_bytes(16,'little');ea=derive(3,[mk,na,nb,r,ioa,aa,ab]);eb=derive(3,[mk,nb,na,r,iob,ab,aa])
     def record(op,arg=0,result=0,data=b'',random=b'',tx=b'',state=-1,prompt=-1,flags=0):
      n=len(tx) if isinstance(tx,bytes) else tx;tx=tx if isinstance(tx,bytes) else b'';assert len(data)<=96 and len(random)<=32 and len(tx)<=72
      return struct.pack('<8q',op,arg,result,len(data),n,state,prompt,flags)+data.ljust(96,b'\0')+random.ljust(32,b'\0')+tx.ljust(72,b'\0')+ltk
     def case(name,rows):
      assert all(len(row)==280 for row in rows);cases.append(struct.pack('<4q',role,mode,len(rows),0)+b''.join(rows));labels.append(dict(name=name,rows=len(rows)))
     name=f'passkey-r{role}-d{display}-kp{keypress}-v{passkey}';rows=[]
     def add(*args,**kwargs):rows.append(record(*args,**kwargs))
     add(1,random=keys[role].private_numbers().private_value.to_bytes(32,'big'),tx=b'\x0c'+own if not role else b'',state=2 if not role else 3)
     if not role:add(3,state=3)
     add(2,result=1,data=b'\x0c'+peer,tx=b'\x0c'+own if role else b'',state=2 if role else 12,prompt=0 if not display else -1,flags=16)
     if role:add(3,state=12,prompt=0 if not display else -1,flags=16)
     ui_at=len(rows)
     if display:
      add(20,random=passkey.to_bytes(3,'little')+rng.randbytes(29),state=12,prompt=passkey,flags=16)
     elif keypress:
      for kind in [0,1,1,2,3,1,1,1,1,1,1,4]:add(24,arg=kind,tx=bytes([14,kind]),state=2);add(3,state=12)
     start_at=len(rows);first=nonces[0][role];z=128|(passkey&1);ca=derive(1,[pa[:32],pb[:32],nonces[0][0]],z=z)
     add(22 if display else 21,arg=0 if display else passkey,random=first+bytes(16) if not role else b'',tx=b'\x03'+ca if not role else b'',state=2 if not role else 13)
     if not role:add(3,state=14)
     random_rows=[];confirm_rows=[]
     for bit,(na,nb) in enumerate(nonces):
      z=128|((passkey>>bit)&1);ca=derive(1,[pa[:32],pb[:32],na],z=z);cb=derive(1,[pb[:32],pa[:32],nb],z=z)
      if role:
       confirm_rows.append(len(rows));add(2,result=1,data=b'\x03'+ca,random=nb+bytes(16),tx=b'\x03'+cb,state=2);add(3,state=15)
       random_rows.append(len(rows));add(2,result=1,data=b'\x04'+na,tx=b'\x04'+nb,state=2);add(3,state=8 if bit==19 else 13)
      else:
       confirm_rows.append(len(rows));add(2,result=1,data=b'\x03'+cb,tx=b'\x04'+na,state=2);add(3,state=16)
       random_rows.append(len(rows));nxt=b'\x0d'+ea if bit==19 else b'\x03'+derive(1,[pa[:32],pb[:32],nonces[bit+1][0]],z=128|((passkey>>(bit+1))&1))
       add(2,result=1,data=b'\x04'+nb,random=nonces[bit+1][0]+bytes(16) if bit<19 else b'',tx=nxt,state=2);add(3,state=9 if bit==19 else 14)
     add(2,result=1,data=b'\x0d'+(ea if role else eb),tx=b'\x0d'+eb if role else b'',state=2 if role else 10,flags=0 if role else 1)
     if role:add(3,state=10,flags=1)
     case(name,rows)
     # Every round can fail independently,with no later bit or key published.
     if passkey==123456 and not keypress:
      for bit,ix in enumerate(random_rows):
       bad=bytearray(nonces[bit][1-role]);bad[0]^=1
       case(name+f'-bad-round-{bit}',rows[:ix]+[record(2,result=1,data=b'\x04'+bad,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x04',state=0,flags=4)])
      # Nonce failures are retryable before commitment publication.
      ix=confirm_rows[0] if role else start_at;orig=rows[ix];op=struct.unpack_from('<q',orig)[0];arg=struct.unpack_from('<q',orig,8)[0];payload=orig[64:64+struct.unpack_from('<q',orig,24)[0]]
      if op>=20:bad=record(op,arg=arg,result=-11,data=struct.pack('<q',301),random=orig[160:192],state=12)
      else:bad=record(op,arg=301,result=-11,data=payload,random=orig[160:192],state=13)
      case(name+'-retry-nonce',rows[:ix]+[bad]+rows[ix:])
     if passkey==1 and not keypress:
      case(name+'-cancel',rows[:ui_at]+[record(23,tx=-11,state=0,flags=4),record(8,tx=b'\x05\x01',state=0,flags=4)])
      if display:
       all_bad=b'\xff'*32
       case(name+'-unbiased-retry',rows[:ui_at]+[record(20,result=-11,random=all_bad,state=12)]+rows[ui_at:])
     if passkey==1 and not display and not keypress:
      case(name+'-stale-entry',rows[:ui_at]+[record(31,arg=0,result=-116,state=12,prompt=0,flags=16),record(31,arg=1,result=-116,state=12,prompt=0,flags=16)]+rows[ui_at:])
      for label,ix,count in [('prepare',confirm_rows[0] if role else start_at,6),('verify',random_rows[9],6 if role else 12),('derive',random_rows[19],31)]:
       orig=rows[ix];op,arg=struct.unpack_from('<2q',orig);payload=orig[64:64+struct.unpack_from('<q',orig,24)[0]]
       for pos in range(1,count+1):
        failed=record(op,arg=500+pos if op==2 else arg,result=-32,data=payload if op==2 else struct.pack('<q',500+pos),random=orig[160:192],tx=-11,state=0,flags=4)
        case(name+f'-{label}-aes-{pos}',rows[:ix]+[failed,record(8,tx=b'\x05\x08',state=0,flags=4)])
      ix=confirm_rows[0] if role else start_at;orig=rows[ix];op,arg=struct.unpack_from('<2q',orig);payload=orig[64:64+struct.unpack_from('<q',orig,24)[0]]
      for fault,result in [(400,-5),(401,-110)]:
       failed=record(op,arg=fault if op==2 else arg,result=result,data=payload if op==2 else struct.pack('<q',fault),random=orig[160:192],tx=result,state=0,flags=4)
       case(name+f'-nonce-lifetime-{fault}',rows[:ix]+[failed])
     if passkey==1 and keypress:
      # The incoming notification resets only the negotiated passkey timer.
      case(name+'-keypress-timeout',rows[:ui_at]+[record(28,arg=10000,data=b'\x0e\x01',state=12),record(30,arg=10000,data=struct.pack('<3q',1,1,1),state=12),record(29,result=40000,state=12),record(5,arg=39999,state=12),record(5,arg=40000,tx=-110,state=0,flags=4)])
      case(name+'-keypress-rfu',rows[:ui_at]+[record(2,result=1,data=b'\x0e\xff',tx=-11,state=0,flags=4),record(8,tx=b'\x05\x0a',state=0,flags=4)])
 payload=struct.pack('<2Q',0x315343504d53,len(cases))+b''.join(cases);(w/'cases.bin').write_bytes(payload);parts=[];start=0
 while start<len(cases):
  count=16 if start<baseline_count else 4;subset=cases[start:start+count];data=struct.pack('<2Q',0x315343504d53,len(subset))+b''.join(subset);name=f'part-{len(parts)}.bin';(w/name).write_bytes(data);parts.append(dict(file=name,cases=len(subset),sha256=hashlib.sha256(data).hexdigest()));start+=len(subset)
 (w/'report.json').write_text(json.dumps(dict(cases=labels,sha256=hashlib.sha256(payload).hexdigest(),parts=parts,baseline_cases=baseline_count,passkey_cases=len(cases)-baseline_count),indent=2)+'\n');print('Generated',len(cases)-baseline_count,'passkey cases')
if __name__=='__main__':main()
