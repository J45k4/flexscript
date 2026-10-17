#!/usr/bin/env python3
"""Independent AES-CMAC checkpoint envelope vectors (RFC4493 primitive).

FSMPCK01 framing/bounds/scope/sequence rules are the local format contract.
Crypto tags come from Python cryptography,not the Flexscript implementation.
"""
import argparse,hashlib,json,random,struct
from pathlib import Path
from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import algorithms
MAX=2**63-1
def q(*v):return struct.pack('<'+'q'*len(v),*v)
def mac(key,data):c=cmac.CMAC(algorithms.AES(key));c.update(data);return c.finalize()
def payload(entries):
 records=[]
 for i in range(entries):
  key=bytes([2,0,0,0,0,0,0]) if not i else bytes([0,i,2,3,4,5,6]);live=int(i%4==0);records.append(key+b'\0'+q(1000*(1+i%3),0 if live else 500+i,60000-i,live))
 return b'SMPTRY01'+q(entries,1000,7000,60000,32,entries,0)+b''.join(records)
def size(n):return n+64 if 104<=n<=1344 and (n-64)%40==0 else -22
def shape(data,n):return size(n)>0 and len(data)>=n and data[:8]==b'SMPTRY01' and struct.unpack('<q',data[8:16])[0]==(n-64)//40
def frame(key,scope,seq,rev,data):
 body=b'FSMPCK01'+q(seq,rev,len(data))+scope+data;return body+mac(key,body)
def expected(op,key,scope,seq,rev,data,n,fail,variant):
 if variant:return -22,0,0,b''
 if op==1:
  if size(n)<0 or seq<1 or rev<1 or not shape(data,n):return -22,0,0,b''
  calls=(48+n+15)//16+1;used=n+160
  if 1<=fail<=calls:return -32,fail,used,b''
  out=frame(key,scope,seq,rev,data[:n]);return len(out),calls,used,out
 if seq<1 or rev<0 or n<0 or n==MAX:return -22,0,0,b''
 count=n-64
 if size(count)<0:return -74,0,0,b''
 assert len(data)>=n
 actual_seq,actual_rev,declared=struct.unpack('<3q',data[8:32])
 if data[:8]!=b'FSMPCK01' or declared!=count or actual_seq<1 or actual_rev<1 or data[32:48]!=scope:return -74,0,0,b''
 if actual_seq!=seq or (rev and actual_rev!=rev):return -116,0,0,b''
 calls=(48+count+15)//16+1
 if 1<=fail<=calls:return -32,fail,112,b''
 if mac(key,data[:n-16])!=data[n-16:n] or not shape(data[48:n-16],count):return -74,calls,112,b''
 return count,calls,112,data[48:n-16]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True);a=p.parse_args();w=Path(a.work);w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();rows=[];rng=random.Random(471);key=bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c');scope=bytes.fromhex('00112233445566778899aabbccddeeff')
 def add(label,op,data,seq=1,rev=1,n=None,fail=0,level=0,variant=0,k=key,s=scope):
  n=len(data) if n is None else n
  result,calls,used,out=expected(op,k,s,seq,rev,data,n,fail,variant);checksum=sum((i+1)*b for i,b in enumerate(k+s+data));blob=q(op,seq,rev,n,fail,level,variant,result,calls,used,len(out),len(data),checksum,0)+k+s+data+out;rows.append((label,blob,result,calls,used))
 for entries in range(1,33):
  data=payload(entries)
  for level in range(16):
   k=rng.randbytes(16);s=rng.randbytes(16);seq=entries*0x100000005+level+1;rev=0x102030405060708+level;encoded=frame(k,s,seq,rev,data);add(f'seal-{entries}-PS{level}',1,data,seq,rev,level=level,k=k,s=s);add(f'open-{entries}-PS{level}',2,encoded,seq,rev,level=level,k=k,s=s)
 small=payload(1);large=payload(32);encoded=frame(key,scope,1,1,small);big=frame(key,scope,1,1,large)
 add('unsupported-zero-entry-seal',1,payload(0));add('unsupported-zero-entry-open',2,frame(key,scope,1,1,payload(0)))
 add('unsupported-33-entry-open',2,frame(key,scope,1,1,payload(33)))
 for n in [-1,0,63,64,103,105,1345,MAX]:add('invalid-payload-size-'+str(n),1,small,n=n)
 for n in [0,63,64,167,169,1409,MAX,-1]:add('invalid-frame-size-'+str(n),2,big,n=n)
 for seq,rev in [(0,1),(-1,1),(1,0),(1,-1),(MAX,MAX)]:
  add('seal-counter-'+str((seq,rev)),1,small,seq,rev)
 for seq,rev in [(0,1),(-1,1),(1,-1),(2,1),(1,2),(MAX,1),(1,0)]:add('open-counter-'+str((seq,rev)),2,encoded,seq,rev)
 add('open-maximum-counters',2,frame(key,scope,MAX,MAX,large),MAX,MAX)
 for variant in range(1,18):
  # Extra backing bytes isolate alias checks without allowing a mutant to write
  # outside the fixture's allocated input record. They are not authenticated.
  add('seal-alias-cap-null-'+str(variant),1,small+bytes(1408-len(small)),n=len(small),variant=variant)
  add('open-alias-cap-null-'+str(variant),2,encoded+bytes(1408-len(encoded)),n=len(encoded),variant=variant)
 for at in range(48):
  for bit in range(8):
   damaged=bytearray(encoded);damaged[at]^=1<<bit;add(f'header-bit-{at}-{bit}',2,bytes(damaged))
 for at in range(len(small)):
  damaged=bytearray(encoded);damaged[48+at]^=1<<(at%8);add('payload-bit-'+str(at),2,bytes(damaged))
 for at in range(16):
  damaged=bytearray(encoded);damaged[-16+at]^=128;add('full-tag-byte-'+str(at),2,bytes(damaged))
 for at in range(0,len(large),16):
  damaged=bytearray(big);damaged[48+at]^=1;add('large-payload-block-'+str(at),2,bytes(damaged))
 for offset,value,label in [(0,b'SMPTRY02','inner-domain'),(8,q(2),'inner-count')]:
  p=bytearray(small);p[offset:offset+len(value)]=value;add('seal-malformed-'+label,1,bytes(p));add('authenticated-malformed-'+label,2,frame(key,scope,1,1,bytes(p)))
 for offset,value,label in [(0,b'FSMPCK02','outer-domain'),(8,q(0),'zero-sequence'),(8,q(-1),'negative-sequence'),(16,q(0),'zero-revision'),(16,q(-1),'negative-revision'),(24,q(105),'declared-length')]:
  p=bytearray(encoded[:-16]);p[offset:offset+len(value)]=value;add('retagged-header-'+label,2,bytes(p)+mac(key,bytes(p)))
 changed=bytearray(encoded);changed[16]^=1;add('restore-wildcard-still-authenticates-revision',2,bytes(changed),rev=0);add('restore-wildcard-valid',2,frame(key,scope,1,99,small),rev=0)
 add('wrong-storage-key',2,encoded,k=bytes(16));add('wrong-store-scope',2,encoded,s=bytes(16))
 for fail in range(1,89):
  add('seal-AES-error-'+str(fail),1,large,fail=fail,level=(fail-1)%16);add('open-AES-error-'+str(fail),2,big,fail=fail,level=(fail-1)%16)
 parts=[];batch=[];indices=[];length=16
 def flush():
  if not batch:return
  data=b'SMPENV01'+q(len(batch))+b''.join(batch);name=f'part-{len(parts)}.bin';(w/name).write_bytes(data);parts.append(dict(file=name,bytes=len(data),cases=indices[:],checks=len(batch),sha256=hashlib.sha256(data).hexdigest()))
 for i,(_,blob,_,_,_) in enumerate(rows):
  if length+len(blob)>950000:flush();batch=[];indices=[];length=16
  batch.append(blob);indices.append(i);length+=len(blob)
 flush();r=dict(cases=len(rows),checks=len(rows),AES_calls=sum(x[3] for x in rows),supported_payload_bytes=[len(payload(i)) for i in range(1,33)],parts=parts,labels=[dict(label=x[0],result=x[2],calls=x[3],wipe=x[4]) for x in rows],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(r,indent=2)+'\n');print('PASS:',len(rows),'checkpoint envelope vectors;',r['AES_calls'],'AES calls;',len(parts),'parts')
if __name__=='__main__':main()
