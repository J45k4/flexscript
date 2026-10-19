#!/usr/bin/env python3
"""Independent Bluetooth/RFC4493 and deterministic differential SMP vectors."""
import argparse,hashlib,json,random,re,struct
from pathlib import Path
from cryptography.hazmat.primitives.cmac import CMAC
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes

def mac(k,m):c=CMAC(algorithms.AES(k));c.update(m);return c.finalize()
def e(k,m):c=Cipher(algorithms.AES(k[::-1]),modes.ECB()).encryptor();return (c.update(m[::-1])+c.finalize())[::-1]
def addr(a):return a[:1]+a[1:][::-1]
def xor(a,b):return bytes(x^y for x,y in zip(a,b))
def derive(kind,a,z=0,message=b''):
 if kind==0:return mac(a[0],message)
 if kind==1:return mac(a[2][::-1],a[0][::-1]+a[1][::-1]+bytes([z]))[::-1]
 if kind==2:
  t=mac(bytes.fromhex('6c888391aaf5a53860370bdb5a6083be'),a[0][::-1]);m=b'btle'+a[1][::-1]+a[2][::-1]+addr(a[3])+addr(a[4])+b'\x01\x00'
  return mac(t,b'\x00'+m)[::-1]+mac(t,b'\x01'+m)[::-1]
 if kind==3:return mac(a[0][::-1],a[1][::-1]+a[2][::-1]+a[3][::-1]+a[4][::-1]+addr(a[5])+addr(a[6]))[::-1]
 if kind==4:return mac(a[2][::-1],a[0][::-1]+a[1][::-1]+a[3][::-1])[-4:][::-1]
 if kind==5:return mac(a[0][::-1],a[1][::-1])[::-1]
 if kind==6:return mac(a[0][::-1],a[1][::-1])[::-1]
 if kind==7:
  p1=a[4][:1]+a[5][:1]+a[2]+a[3];p2=a[5][1:]+a[4][1:]+bytes(4)
  return e(a[0],xor(e(a[0],xor(a[1],p1)),p2))
 if kind==8:return e(a[0],a[2][:8]+a[1][:8])
 if kind==9:return e(a[0],a[1]+bytes(13))[:3]
 if kind==10:return e(a[0],a[1])
 raise AssertionError(kind)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference',required=True);p.add_argument('--work',required=True);a=p.parse_args()
 w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'vectors.json').exists()
 source=Path(a.reference).read_text();assert hashlib.sha256(Path(a.reference).read_bytes()).hexdigest()=='febf3b983e44eca722e05da0c46122a4b3a9016ea37151967c5b21763014e098','pinned Zephyr4.2.1 SMP reference required';rows=[];payload=bytearray()
 def add(kind,args,label,z=0,message=b'',expected=None):
  result=derive(kind,args,z,message)
  if expected is not None:assert result==expected,(label,result.hex(),expected.hex())
  row=bytearray(832);struct.pack_into('<3Q',row,0,kind,len(message),z)
  for i,field in enumerate(args):assert len(field)<=32;row[32+32*i:32+32*i+len(field)]=field
  assert len(message)<=512;row[256:256+len(message)]=message;row[768:768+len(result)]=result;struct.pack_into('<Q',row,800,len(result));payload.extend(row)
  rows.append(dict(index=len(rows),kind=kind,label=label,result=result.hex()))
 key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c');m=bytes.fromhex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710')
 for n,out in [(0,'bb1d6929e95937287fa37d129b756746'),(16,'070a16b46b4d4144f79bdd9dd04a287c'),(40,'dfa66747de9ae63030ca32611497c827'),(64,'51f0bebf7e3b9d92fc49741779363cfe')]:add(0,[key],f'RFC4493-{n}',message=m[:n],expected=bytes.fromhex(out))
 # Zephyr's pinned C self-tests reproduce the Bluetooth Appendix D wire arrays.
 for name,kind,fields,expected in [('f4',1,['u','v','x'],'exp'),('f5',2,['w','n1','n2'],'exp_mackey'),('f6',3,['w','n1','n2','r','io_cap'],'exp'),('g2',4,['u','v','x','y'],None),('h6',5,['w','key_id'],'exp_res'),('h7',6,['salt','w'],'exp_res')]:
  body=source.split('static int smp_'+name+'_test(void)',1)[1].split('\nstatic int ',1)[0]
  arrays={n:bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]+)',v)) for n,v in re.findall(r'uint8_t\s+(\w+)\[\d*\]\s*=\s*\{([^}]+)\}',body)}
  args=[arrays[f] for f in fields]
  if kind in [2,3]:
   for n in ['a1','a2']:
    typ,data=re.search(r'bt_addr_le_t '+n+r'\s*=\s*\{\s*\.type\s*=\s*(0x\w+),\s*\.a.val\s*=\s*\{([^}]+)',body).groups();args.append(bytes([int(typ,16)])+bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]+)',data)))
  result=arrays[expected] if expected else bytes.fromhex('bad59e2f')
  if kind==2:result+=arrays['exp_ltk']
  add(kind,args,'Bluetooth-Appendix-D-'+name,expected=result)
 be=lambda s:bytes.fromhex(s)[::-1]
 add(7,[bytes(16),be('5783d52156ad6f0e6388274ec6702ee0'),be('07071000000101'),be('05000800000302'),b'\x01'+be('a1a2a3a4a5a6'),b'\x00'+be('b1b2b3b4b5b6')],'Bluetooth-c1',expected=be('1e1e3fef878988ead2a74dc5bef13b86'))
 add(8,[bytes(16),be('000f0e0d0c0b0a091122334455667788'),be('010203040506070899aabbccddeeff00')],'Bluetooth-s1',expected=be('9a1fe1f0e8b0f49b5b4216ae796da062'))
 add(9,[be('ec0234a357c8ad05341010a60a397d9b'),be('708194')],'Bluetooth-ah',expected=be('0dfbaa'))
 add(10,[be('000102030405060708090a0b0c0d0e0f'),be('00112233445566778899aabbccddeeff')],'NIST-AES128',expected=be('69c4e0d86a7b0430d8cdb78070b4c55a'))
 rng=random.Random(0x534d5031);sizes=[[16],[32,32,16],[32,16,16,7,7],[16,16,16,16,3,7,7],[32,32,16,16],[16,4],[16,16],[16,16,7,7,7,7],[16,16,16],[16,3],[16,16]]
 for kind,lengths in enumerate(sizes):
  for i in range(24):
   args=[rng.randbytes(n) for n in lengths]
   if kind in [2,3,7]:
    for j in ([3,4] if kind==2 else [5,6] if kind==3 else [4,5]):args[j]=bytes([i%2])+args[j][1:]
   msg=rng.randbytes(([0,1,15,16,17,31,32,33,40,63,64,65,127,128,129,255,256,257,511,512][i%20])) if kind==0 else b''
   add(kind,args,f'differential-{kind}-{i}',z=[0,0x80,0x81,255][i%4],message=msg)
 large=bytearray(struct.pack('<Q',3))
 for size in [513,4096,65535]:
  k=rng.randbytes(16);m=rng.randbytes(size);large.extend(struct.pack('<Q',size)+k+mac(k,m)+m)
 (w/'large.bin').write_bytes(large)
 (w/'vectors.bin').write_bytes(payload);(w/'vectors.json').write_text(json.dumps(dict(records=len(rows),bytes=len(payload),vectors_sha256=hashlib.sha256(payload).hexdigest(),reference_sha256=hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),cases=rows),indent=2)+'\n');print('Generated',len(rows),'independent SMP vectors')
if __name__=='__main__':main()
