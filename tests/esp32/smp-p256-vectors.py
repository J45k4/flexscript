#!/usr/bin/env python3
"""Independent OpenSSL/cryptography P-256 and pinned upstream raw-key vectors."""
import argparse,hashlib,json,struct
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
P=0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
N=0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
DER=bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d03010703420004')
def public(d):
 q=ec.derive_private_key(d,ec.SECP256R1()).public_key().public_numbers();return q.x.to_bytes(32,'little')+q.y.to_bytes(32,'little')
def point(q):return ec.EllipticCurvePublicNumbers(int.from_bytes(q[:32],'little'),int.from_bytes(q[32:],'little'),ec.SECP256R1()).public_key()
def scalar(k):return int.from_bytes(k,'little')
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['reference','nist','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work);w.mkdir(parents=True,exist_ok=True);cases=[];excluded=[];eligible=[]
 def add(label,op,k=(1).to_bytes(32,'little'),q=None,rng=None,fail=0,error=-32,rng_fail=0,rng_error=-5,rng_mode=0,variant=0,level=0,ready=0):
  q=public(2) if q is None else q;rng=(2).to_bytes(32,'big')+bytes(96) if rng is None else rng;assert len(k)==32 and len(q)==64 and len(rng)==128
  output=bytearray(b'\xa5'*96);private=k;peer=q;offset=0
  if variant in [10,11]:output[:]=k+q;offset=32 if variant==11 else 0
  if variant==12:private=q[:32]
  calls=draws=0;wipe=256;data=b'';status=0
  invalid=(variant in [4,5,6] or (variant in [3,9] and op!=1) or (variant in [1,7] and op in [2,3]) or (variant in [2,8] and op in [1,3]))
  if invalid:status=-22;wipe=0
  elif ready in [1,2,3,4]:status={1:-19,2:-16,3:-16,4:-22}[ready];wipe=0
  elif ready==5 and op==4:status=-19
  else:
   if op==1:
    calls=1
    try:point(peer)
    except ValueError:status=-2
   if op==2:
    calls=1
    if not 1<=scalar(private)<N:status=-3
    else:calls=2;data=public(scalar(private))
   if op==3:
    calls=1
    if not 1<=scalar(private)<N:status=-3
    else:
     try:data=ec.derive_private_key(scalar(private),ec.SECP256R1()).exchange(ec.ECDH(),point(peer))[::-1]
     except ValueError:status=-2
   if op==4:
    calls=1
    for draw in range(1,5):
     draws=draw
     if draw==rng_fail:status=rng_error;break
     if rng_mode in [1,2]:status={1:-22,2:-116}[rng_mode];break
     d=int.from_bytes(rng[(draw-1)*32:draw*32],'big')
     if 1<=d<N:data=d.to_bytes(32,'little')+public(d);break
    else:status=-1
   if fail and fail<=calls:calls=fail;draws=0;status=error
  if not status and op!=1:output[offset:offset+len(data)]=data
  body=k+q+rng;checksum=sum((i+1)*b for i,b in enumerate(body));head=struct.pack('<16q',op,status,fail,error,rng_fail,rng_error,rng_mode,variant,level,calls,draws,wipe,len(data) if not status else 0,checksum,ready,0);cases.append((label,head+body+output,op in [2,3,4] and not status))
 for level in range(16):
  for op in [1,2,3,4]:add(f'all-PS-{level}-op-{op}',op,level=level)
 for i in range(32):
  d=int.from_bytes(hashlib.sha256(b'flex-p256-private'+bytes([i])).digest(),'big')%(N-1)+1;b=int.from_bytes(hashlib.sha256(b'flex-p256-peer'+bytes([i])).digest(),'big')%(N-1)+1
  for op in [1,2,3]:add(f'differential-{i}-{op}',op,k=d.to_bytes(32,'little'),q=public(b),level=i%16)
 for d in [0,1,2,3,N-2,N-1,N,N+1,(1<<256)-1]:
  for op in [2,3]:add(f'scalar-boundary-{d}-{op}',op,k=d.to_bytes(32,'little'))
 for x,y in [(0,0),(1,1),(P,1),(1,P),(P-1,P-1),((1<<256)-1,1),(1,(1<<256)-1)]:
  q=x.to_bytes(32,'little')+y.to_bytes(32,'little')
  for op in [1,3]:add(f'invalid-coordinate-{x}-{y}-{op}',op,q=q)
 # The pinned upstream suite attributes this pair to the NIST ECDH example.
 import re
 line=next(x for x in Path(a.nist).read_text().splitlines() if x.startswith('ecdh_primitive_testvec:MBEDTLS_ECP_DP_SECP256R1:'));v=[bytes.fromhex(x) for x in re.findall(r'"([0-9A-Fa-f]+)"',line)];assert len(v)==7
 ka,ax,ay,kb,bx,by,z=v;assert public(int.from_bytes(ka,'big'))==ax[::-1]+ay[::-1] and public(int.from_bytes(kb,'big'))==bx[::-1]+by[::-1]
 assert ec.derive_private_key(int.from_bytes(ka,'big'),ec.SECP256R1()).exchange(ec.ECDH(),point(bx[::-1]+by[::-1]))==z
 add('NIST-ECDH-A',3,ka[::-1],bx[::-1]+by[::-1]);add('NIST-ECDH-B',3,kb[::-1],ax[::-1]+ay[::-1])
 src=json.loads(Path(a.reference).read_text())
 for group in src['testGroups']:
  for v in group['tests']:
   encoded=bytes.fromhex(v['public']);d=int(v['private'],16)
   if len(encoded)!=91 or not encoded.startswith(DER) or not 0<=d<1<<256:
    excluded.append(dict(id=v['tcId'],reason='ASN.1/SEC1 form or scalar extent outside the raw64/32-byte API'));continue
   raw=encoded[-64:];q=raw[:32][::-1]+raw[32:][::-1];k=d.to_bytes(32,'little');eligible.append(v['tcId'])
   if v['result']=='valid':assert ec.derive_private_key(d,ec.SECP256R1()).exchange(ec.ECDH(),point(q)).hex()==v['shared']
   add('Wycheproof-'+str(v['tcId']),3,k,q,level=v['tcId']%16)
 for op in [1,2,3,4]:
  for variant in range(1,13):
   if variant in [10,11] and op not in [2,3]:continue
   if variant==11 and op!=3:continue
   add(f'bounds-alias-{op}-{variant}',op,variant=variant)
  for ready in range(1,6):add(f'provider-preflight-{op}-{ready}',op,ready=ready)
  for level in range(16):
   for error in [-32,-2147483648]:add(f'vendor-error-{op}-{level}-{error}',op,fail=1,error=error,level=level)
 for level in range(16):add(f'second-public-call-error-{level}',2,fail=2,level=level)
 bad=[bytes(32),N.to_bytes(32,'big'),((1<<256)-1).to_bytes(32,'big')];good=(123).to_bytes(32,'big')
 for valid_at in range(1,5):
  rng=b''.join(bad[:valid_at-1]+[good]+[bytes(32)]*(4-valid_at));add('random-rejection-then-valid-'+str(valid_at),4,rng=rng)
  for failed in range(1,valid_at+1):add(f'entropy-error-at-{valid_at}-{failed}',4,rng=rng,rng_fail=failed,level=failed)
 add('four-invalid-random-scalars',4,rng=b''.join(bad+[bytes(32)]))
 for mode in [1,2,3]:add('entropy-callback-mode-'+str(mode),4,rng_mode=mode)
 parts=[];rows=[];labels=[];cost=0
 def flush():
  nonlocal rows,labels,cost
  if not rows:return
  blob=b'SMPP2561'+struct.pack('<q',len(rows))+b''.join(rows);name=f'part-{len(parts)}.bin';(w/name).write_bytes(blob);parts.append(dict(file=name,cases=len(rows),sha256=hashlib.sha256(blob).hexdigest(),labels=labels));rows=[];labels=[];cost=0
 for label,row,expensive in cases:
  if cost>=36:flush()
  rows.append(row);labels.append(label);cost+=int(expensive)
 flush();report=dict(cases=len(cases),parts=parts,wycheproof_total=src['numberOfTests'],wycheproof_raw_eligible_ids=eligible,wycheproof_excluded=excluded,wycheproof_sha256=hashlib.sha256(Path(a.reference).read_bytes()).hexdigest(),nist_suite_sha256=hashlib.sha256(Path(a.nist).read_bytes()).hexdigest(),output_order='little-endian scalar,X,Y',physical_entropy=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('Generated',len(cases),'P-256 cases;',len(eligible),'eligible Wycheproof raw-key cases;',len(parts),'firmware parts')
if __name__=='__main__':main()
