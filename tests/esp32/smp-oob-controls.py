#!/usr/bin/env python3
"""Prove independent OOB peers reject isolated ownership/authentication defects."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','provider','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();compiler=Path(a.compiler).resolve();vectors=Path(a.vectors).resolve();provider=Path(a.provider).resolve();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-sc-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 defects=[
 ('OOB-pool-not-registered','smp-sc-oob','sc_oob_init','r=sd_sensitive_register(work,n);','r=0;'),
 ('OOB-provider-context-alias-accepted','smp-sc-oob','sc_oob_init','r=smp_sc_ready(work,capacity);if r {return r;}',''),
 ('OOB-peer-identity-not-bound','smp-sc-oob','sc_oob_bind',' || !nb_equal(q+72,owner+16,7)',''),
 ('OOB-local-address-not-bound','smp-sc-oob','sc_oob_bind','!nb_equal(q+64,p+240,7)','0'),
 ('OOB-preconnection-cutoff-ignored','smp-sc-oob','sc_oob_bind',' || token<=load64(q+56)',''),
 ('OOB-no-provenance-required','smp-sc-oob','sc_oob_bind',' || (!load64(q+40) && !load64(q+48))',''),
 ('OOB-ticket-can-be-consumed-again','smp-sc-oob','sc_ob_begin','store64(q+8,4);','store64(q+8,3);'),
 ('OOB-ticket-secrets-retained','smp-sc-oob','sc_ob_begin','nb_zero(q+80,176);',''),
 ('OOB-key-replaced-at-handoff','smp-sc-oob','sc_ob_begin','nb_copy(p+576,q+80,96);','nb_zero(p+576,96);'),
 ('OOB-witness-replay-accepted','smp-sc-oob','sc_ob_attest','if r<=sc_oob_witness_floor','if 0'),
 ('OOB-descriptor-mutation-accepted','smp-sc-oob','sc_ob_attest','nb_equal(stage,stage+128,128)','1'),
 ('OOB-record-mutation-accepted','smp-sc-oob','sc_ob_attest','nb_equal(stage+256,record,32)','1'),
 ('OOB-evidence-mutation-accepted','smp-sc-oob','sc_ob_attest','nb_equal(stage+288,evidence,size)','1'),
 ('OOB-callback-not-required','smp-sc-oob','sc_ob_attest','r=smp_sc_oob_attest(stage);','r=1;'),
 ('OOB-callback-error-retains-keys','smp-sc-oob','sc_ob_attest','if !sc_transient(r) {nb_zero(p,256);}',''),
 ('OOB-commitment-not-verified','smp-sc-oob','sc_ob_peer','if !r && (load64(p+1008)&1)','if 0'),
 ('OOB-commitment-binds-local-key','smp-sc-oob','sc_ob_peer','smp_f4(p+672,p+672,','smp_f4(p+608,p+608,'),
 ('OOB-unreceived-r-not-zero','smp-sc-oob','sc_ob_begin','if load8(p+266) {','if 1 {'),
 ('OOB-local-check-ignores-peer-r','smp-sc','sc_derive','localr=p+976;','localr=p+944;'),
 ('OOB-peer-check-ignores-local-r','smp-sc','sc_derive','peerr=p+960;','peerr=p+944;'),
 ('OOB-expiry-not-reconciled','smp-sc-oob','sc_ob_tick','else if now>=load64(q+16)','else if 0'),
 ('OOB-crypto-output-after-expiry','smp-sc-oob','sc_ob_recheck','if so_now>=load64(p+16)','if 0'),
 ('OOB-outgoing-proof-not-required','smp-sc-oob','sc_ob_features',' || (load8(p+266) && !load64(q+48))',''),
 ]
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
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(defects),cases=results,source_sha256=manifest,compiler_sha256=sha(compiler),provider_sha256=sha(provider),vectors_sha256=sha(vectors)),indent=2)+'\n');print('PASS:',len(defects),'OOB protocol/ownership defects detected')
if __name__=='__main__':main()
