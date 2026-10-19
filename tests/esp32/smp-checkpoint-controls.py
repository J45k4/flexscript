#!/usr/bin/env python3
"""Independent peer corpus controls for SMP authenticated checkpoint envelopes."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-checkpoint-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('seal-MAC-omits-header-binding','ck_seal','smp_cmac(key,frame,48+bytes,','smp_cmac(key,frame+48,bytes,'),
  ('seal-MAC-omits-final-payload-byte','ck_seal','smp_cmac(key,frame,48+bytes,','smp_cmac(key,frame,47+bytes,'),
  ('seal-publishes-before-AES-succeeds','ck_seal','let r=smp_cmac','nb_copy(out,frame,size);let r=smp_cmac'),
  ('seal-truncates-full-tag','ck_seal','nb_copy(out,frame,size);return','nb_copy(out,frame,size-1);return'),
  ('open-ignores-tag','ck_open','!smp_equal(work+96,frame+48+bytes,16) || ',''),
  ('open-compares-only-15-tag-bytes','ck_open','frame+48+bytes,16)','frame+48+bytes,15)'),
  ('open-ignores-store-scope','ck_open',' || !smp_equal(scope,frame+32,16)',''),
  ('open-ignores-expected-sequence','ck_open','load64(frame+8)!=sequence || ',''),
  ('open-ignores-frozen-revision','ck_open',' || (expected_revision && load64(frame+16)!=expected_revision)',''),
  ('restore-wildcard-skips-authentication','ck_open','nb_zero(work,112);','if !expected_revision {nb_copy(out,frame+48,bytes);return bytes;}nb_zero(work,112);'),
  ('open-publishes-before-authentication','ck_open','nb_zero(work,112);','nb_copy(out,frame+48,bytes);nb_zero(work,112);'),
  ('key-scratch-not-cleared','ck_clear','nb_zero(work,n);','nb_zero(work,96);'),
  ('seal-inverts-scope-byte-order','ck_seal','nb_copy(frame+32,scope,16);','smp_reverse(frame+32,scope,16);'),
  ('seal-header-sequence-is-low-word-only','ck_seal','store64(frame+8,sequence);','store64(frame+8,sequence&4294967295);'),
  ('open-skips-envelope-domain','ck_open','!nb_equal(frame,"FSMPCK01",8) || ',''),
  ('open-skips-declared-length','ck_open',' || load64(frame+24)!=bytes',''),
  ('payload-skips-checkpoint-domain','ck_payload',' && nb_equal(p,"SMPTRY01",8)',''),
  ('payload-skips-entry-count','ck_payload',' && load64(p+8)==(n-64)/40',''),
  ('open-skips-authenticated-payload-shape','ck_open',' || !ck_payload(frame+48,bytes)',''),
  ('open-accepts-short-output-buffer','ck_open','if capacity<bytes {return -22;}',''),
  ('seal-accepts-short-output-buffer','ck_seal',' || capacity<size',''),
  ('seal-accepts-short-workspace','ck_seal',' || work_capacity<size+96',''),
  ('open-accepts-short-workspace','ck_open',' || work_capacity<112',''),
  ('key-scope-alias-accepted','ck_disjoint','!smp_overlap(key,16,scope,16) && ',''),
  ('key-payload-alias-accepted','ck_disjoint','!smp_overlap(key,16,input,n) && ',''),
  ('expected-scope-aliases-frame','ck_disjoint','!smp_overlap(scope,16,input,n) && ',''),
  ('output-aliases-input','ck_disjoint',' && !smp_overlap(out,on,input,n)',''),
  ('workspace-aliases-input','ck_disjoint',' && !smp_overlap(work,wn,input,n)',''),
  ('workspace-aliases-output','ck_disjoint',' && !smp_overlap(work,wn,out,on)',''),
  ('zero-entry-checkpoint-accepted','ck_size','bytes<104','bytes<64'),
  ('33-entry-checkpoint-accepted','ck_size','bytes>1344','bytes>1384'),
  ('storage-AES-key-reversed','ck_seal','let r=smp_cmac(key,','smp_reverse(frame+48+bytes,key,16);let r=smp_cmac(frame+48+bytes,'),
 ]

 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/net/smp-checkpoint.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-checkpoint-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP CHECKPOINT FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP checkpoint ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS: complete checkpoint corpus;',len(changes),'framing/authentication/cleanup defects detected')
if __name__=='__main__':main()
