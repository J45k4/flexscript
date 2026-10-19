#!/usr/bin/env python3
"""Prove the independent SC corpus rejects isolated protocol/cleanup defects."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','provider','work']:p.add_argument('--'+k,required=True)
 p.add_argument("--passkey",action="store_true");a=p.parse_args();compiler=Path(a.compiler).resolve();provider=Path(a.provider).resolve();vectors=Path(a.vectors).resolve();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-sc-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 defects=[
 ('DH-check-skipped','smp-sc','sc_input','if !smp_equal(p+864,packet+1,16)','if 0'),
 ('commitment-check-skipped','smp-sc','sc_random','!smp_equal(p+912,p+800,16)','0'),
 ('debug-keys-accepted','smp-sc','sc_debug','return diff==0;','return 0;'),
 ('reflected-key-accepted','smp-sc','sc_peer',' || smp_equal(peer,p+608,32)',''),
 ('ECDH-not-derived','smp-sc','sc_peer','r=p256_shared(p+576,p+672,p+736,p+1024,512);','r=0;'),
 ('initiator-responder-nonces-swapped','smp-sc','sc_derive','r=smp_f5(p+736,n1,n2,a1,a2,','r=smp_f5(p+736,n2,n1,a1,a2,'),
 ('addresses-not-bound','smp-sc','sc_derive','r=smp_f5(p+736,n1,n2,a1,a2,','r=smp_f5(p+736,n1,n2,a1,a1,'),
 ('DH-checks-not-distinct','smp-sc','sc_derive','p+864,p+1024,512)','p+848,p+1024,512)'),
 ('numeric-value-changed','smp-sc','sc_random','value%1000000','(value+1)%1000000'),
 ('numeric-rejection-ignored','smp-sc','sc_confirm','if !accepted {','if 0 {'),
 ('numeric-stale-generation-accepted','smp-sc','sc_bound',' || load64(p+528)!=generation',''),
 ('numeric-stale-lease-accepted','smp-sc','sc_bound',' || load64(p+520)!=lease || load64(q+8)!=lease',''),
 ('TX-generation-reused','smp-sc','sc_queue','let r=sm_epoch(p);','let r=0;'),
 ('keys-mark-link-secure','smp-sc','sc_finish','store64(p+512,10);','store64(p+512,10);store64(p+224,1);'),
 ('ephemeral-secrets-retained','smp-sc','sc_finish','nb_zero(p+576,256);',''),
 ('derived-secrets-retained','smp-sc','sc_finish','nb_zero(p+848,688);',''),
 ('lifetime-revalidation-skipped','smp-sc','sc_recheck','let r=sc_ready();','return 0;let r=sc_ready();'),
 ('fault-key-erasure-delayed','smp-durable','sd_fault','nb_zero(sd_engine+256+i*1536+512,1024);',''),
 ('terminal-key-erasure-skipped','smp-pairing','sm_clear_attempt','nb_zero(p+320,1216);','nb_zero(p+320,192);'),
 ]
 if a.passkey:defects.extend([('passkey-domain-bit-missing', 'smp-sc-passkey', 'sc_pk_prepare', 'let bit=128|', 'let bit=0|'), ('passkey-bits-reversed', 'smp-sc-passkey', 'sc_pk_prepare', 'load64(p+960)>>round', 'load64(p+960)>>(19-round)'), ('passkey-ends-after19-rounds', 'smp-sc-passkey', 'sc_pk_random', 'if round==19', 'if round==18'), ('passkey-round-frozen', 'smp-sc-passkey', 'sc_pk_prepare', 'store64(p+976,round);', 'store64(p+976,0);'), ('passkey-nonce-not-fresh', 'smp-sc-passkey', 'sc_pk_prepare', 'r=smp_sc_random(p+928,16,p+1024,512);', 'r=0;nb_zero(p+928,16);'), ('passkey-random-modulo-biased', 'smp-sc-passkey', 'sc_passkey_generate', 'if n<1000000 {value=n;}', 'value=n%1000000;'), ('passkey-display-value-fixed', 'smp-sc-passkey', 'sc_passkey_generate', 'store64(p+960,value);', 'store64(p+960,123456);'), ('passkey-not-bound-to-DH-check', 'smp-sc', 'sc_derive', 'if load64(p+88)==1 {store64(p+944,load64(p+960));}', ''), ('passkey-round-commit-check-skipped', 'smp-sc-passkey', 'sc_pk_random', 'if !smp_equal(p+912,p+800,16)', 'if 0'), ('passkey-peer-public-order-swapped', 'smp-sc-passkey', 'sc_pk_random', 'smp_f4(p+672,p+608,', 'smp_f4(p+608,p+672,'), ('passkey-peer-commitment-not-stored', 'smp-sc-passkey', 'sc_pk_confirm', 'nb_copy(p+800,packet+1,16);r=sc_queue', 'r=sc_queue'), ('passkey-responder-round-not-advanced', 'smp-sc', 'sc_packet_sent', 'store64(p+976,load64(p+976)+1);', 'store64(p+976,load64(p+976));'), ('passkey-keypress-rfu-accepted', 'smp-sc-passkey', 'sc_pk_keypress', 'if kind>4 {return sc_abort(p,10,0,1,now);}', 'if kind>4 {return 0;}'), ('passkey-keypress-does-not-restart-timer', 'smp-sc-passkey', 'sc_pk_keypress', 'store64(p+152,now+30000);', ''), ('passkey-cancel-wrong-reason', 'smp-sc-passkey', 'sc_passkey_cancel', 'sc_abort(p,1,-13,1,now)', 'sc_abort(p,12,-13,1,now)'), ('passkey-preparation-error-publishes', 'smp-sc-passkey', 'sc_pk_prepare', 'if r {nb_zero(p+896,16);', 'if 0 {nb_zero(p+896,16);'), ('passkey-provider-error-not-terminal', 'smp-sc-passkey', 'sc_pk_error', 'return sc_abort(p,8,r,1,now);', 'return r;')])
 results=[]
 for item in [None]+defects:
  name=item[0] if item else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if item:
   _,module,fn,before,after=item;h['change'](tree/f'lib/net/{module}.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';r=subprocess.run([str(compiler),str(tree/'tests/esp32/smp-sc-native.flex'),'-o',str(exe)],cwd=tree,env=env,capture_output=True,timeout=30);(w/name/'compile.log').write_bytes(r.stdout+r.stderr);assert r.returncode==0,(name,r.stdout,r.stderr)
  r=subprocess.run([str(exe),str(vectors),str(provider)],cwd=tree,env=env,capture_output=True,timeout=60);log=w/name/'run.log';log.write_bytes(r.stdout+r.stderr)
  if item:assert r.returncode==8 and b'SMP SC FAIL ' in r.stderr,(name,r.returncode,r.stdout,r.stderr)
  else:assert r.returncode==0 and r.stdout.startswith(b'PASS: SMP SC '),(r.returncode,r.stdout,r.stderr)
  results.append(dict(name=name,detected=bool(item),executable_sha256=sha(exe),log_sha256=sha(log)));print(name,flush=True)
 for f,v in manifest.items():assert sha(ROOT/f)==v,f
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(defects),cases=results,source_sha256=manifest,compiler_sha256=sha(compiler),provider_sha256=sha(provider),vectors_sha256=sha(vectors)),indent=2)+'\n');print('PASS:',len(defects),'SC protocol/cleanup defects detected')
if __name__=='__main__':main()
