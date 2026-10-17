#!/usr/bin/env python3
"""Independent peer corpus controls for SMP privacy and provisional-peer admission."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-privacy-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('unknown-peers-get-address-bucket','lib/net/smp-privacy.flex','sp_resolve','store8(work+512,2);','nb_copy(work+512,peer,7);'),
  ('pending-IRK-promotes-identity','lib/net/smp-privacy.flex','sp_resolve','if flags&2','if flags&1'),
  ('confirmed-identity-stays-provisional','lib/net/smp-privacy.flex','sp_resolve','if flags&2','if 0'),
  ('wrong-RPA-prand-octets','lib/net/smp-privacy.flex','sp_resolve','peer+4,work+544','peer+1,work+544'),
  ('wrong-RPA-hash-octets','lib/net/smp-privacy.flex','sp_resolve','work+544,peer+1,3','work+544,peer+4,3'),
  ('ambiguous-IRK-match-accepted','lib/net/smp-privacy.flex','sp_resolve','if matches>1','if 0'),
  ('lookup-stops-at-first-match','lib/net/smp-privacy.flex','sp_resolve','store64(work+528,i+1);','store64(work+528,i+1);i=count;'),
  ('AES-failure-masquerades-as-success','lib/net/smp-privacy.flex','sp_resolve','return sp_done(work,r);','return sp_done(work,0);'),
  ('resolver-keeps-key-scratch','lib/net/smp-privacy.flex','sp_done','nb_zero(work,608);','nb_zero(work,512);'),
  ('reserved-address-kind-accepted','lib/net/smp-privacy.flex','sp_address','if kind==128 {return 0;}',''),
  ('degenerate-prand-accepted','lib/net/smp-privacy.flex','sp_bits','return !zero && !ones;','return 1;'),
  ('private-address-used-as-canonical','lib/net/smp-privacy.flex','sp_identity',' && (load8(p)==0 || (load8(p+6)&192)==192)',''),
  ('bond-RFU-flags-ignored','lib/net/smp-privacy.flex','sp_table',' || flags>3',''),
  ('bond-reserved-bytes-ignored','lib/net/smp-privacy.flex','sp_table',' || !sr_zero(p+24,8)',''),
  ('IRK-presence-flag-ignored','lib/net/smp-privacy.flex','sp_table',' || (!(flags&1) && !sr_zero(p+8,16))',''),
  ('duplicate-identities-accepted','lib/net/smp-privacy.flex','sp_table','if nb_equal(p,records+j*32,7)','if 0'),
  ('resolver-output-aliases-peer','lib/net/smp-privacy.flex','sp_resolve',' || smp_overlap(out,32,peer,7)',''),
  ('resolver-output-aliases-IRKs','lib/net/smp-privacy.flex','sp_resolve',' || smp_overlap(out,32,records,count*32)',''),
  ('open-erases-actual-connection-address','lib/net/smp-privacy.flex','sp_open','role,local,peer,work+608','role,local,work+608,work+608'),
  ('invalid-view-keeps-workspace','lib/net/smp-privacy.flex','sp_open','nb_zero(work,640);','if r!=-22 {nb_zero(work,640);}') ,
  ('open-does-not-wipe-result-on-error','lib/net/smp-privacy.flex','sp_open','nb_zero(work,640);',''),
  ('open-turns-resolver-failure-into-owner-call','lib/net/smp-privacy.flex','sp_open','if !r {r=so_open','if 1 {r=so_open'),
  ('inherit-direction-reversed','lib/net/smp-privacy.flex','sp_inherit_identity','if to_identity {','if !to_identity {'),
  ('inherit-keeps-temporary-bucket','lib/net/smp-privacy.flex','sp_inherit_identity','nb_zero(work,16);return r;','return r;'),
  ('admission-key-rejects-unresolved-bucket','lib/net/smp-retry.flex','sr_key','return sr_identity(p) || (sr_external(p,7) && load8(p)==2 && sr_zero(p+1,6));','return sr_identity(p);'),
  ('owner-rejects-unresolved-bucket','lib/net/smp-session.flex','so_open','!sr_key(identity)','!sr_identity(identity)'),
  ('wire-order-IRK-not-reversed','lib/net/smp-crypto.flex','smp_e_work','smp_reverse(work+96,key,16);','nb_copy(work+96,key,16);'),
  ('resolution-claims-link-authentication','lib/net/smp-privacy.flex','sp_resolve','nb_copy(out,work+512,32);','store64(work+536,1);nb_copy(out,work+512,32);'),
 ]

 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,file,fn,before,after=mutation;h['change'](tree/file,fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-privacy-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP PRIVACY FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP privacy ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS: complete privacy corpus;',len(changes),'privacy/admission defects detected')
if __name__=='__main__':main()
