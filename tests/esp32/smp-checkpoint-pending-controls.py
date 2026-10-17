#!/usr/bin/env python3
"""Verify live gate/envelope binding with targeted native defect checkpoints."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-checkpoint-pending-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('valid-MAC-wrong-payload-accepted','ck_pending_verify','r!=bytes || !nb_equal(work+112,sd_checkpoint_buffer,bytes)','r!=bytes',14),
  ('verification-prematurely-ACKs-storage','ck_pending_verify','else {r=0;}','else {sd_done(sd_checkpoint_sequence,sd_checkpoint_revision,0,so_now);r=0;}',8),
  ('seal-uses-new-dirty-revision','ck_pending_seal','sd_checkpoint_sequence,sd_checkpoint_revision','sd_checkpoint_sequence,sd_revision',21),
  ('decoded-staging-not-cleared','ck_pending_verify','nb_zero(work,112+bytes);','nb_zero(work,112);',9),
  ('alias-check-after-workspace-wipe','ck_pending_verify','if !ck_disjoint(key,scope,frame,size,work+112,bytes,work,112) {return -22;}','',17),
  ('readback-ignores-frozen-revision','ck_pending_verify','sd_checkpoint_sequence,sd_checkpoint_revision,frame','sd_checkpoint_sequence,0,frame',36),
  ('bad-readback-aborts-pending-gate','ck_pending_verify','nb_zero(work,112+bytes);','if r<0 {sd_done(sd_checkpoint_sequence,sd_checkpoint_revision,r,so_now);}nb_zero(work,112+bytes);',11),
  ('sealing-prematurely-ACKs-storage','ck_pending_seal','return ck_seal(key,scope,sd_checkpoint_sequence,sd_checkpoint_revision,sd_checkpoint_buffer,bytes,out,capacity,work,work_capacity);','let r=ck_seal(key,scope,sd_checkpoint_sequence,sd_checkpoint_revision,sd_checkpoint_buffer,bytes,out,capacity,work,work_capacity);if r>0 {sd_done(sd_checkpoint_sequence,sd_checkpoint_revision,0,so_now);}return r;',5),
  ('seal-uses-ledger-instead-of-snapshot','ck_pending_seal','sd_checkpoint_buffer,bytes','sr_work,bytes',4),
 ]
 results=[]
 for item in [None]+changes:
  name=item[0] if item else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if item:
   _,fn,before,after,_=item;h['change'](tree/'lib/net/smp-checkpoint-pending.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';c=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-checkpoint-pending-native.flex'),'-o',str(exe)],cwd=tree,env=env,capture_output=True,timeout=30);(w/name/'compile.log').write_bytes(c.stdout+c.stderr);assert c.returncode==0,(name,c.stdout,c.stderr)
  r=subprocess.run([str(exe)],cwd=tree,env=env,capture_output=True,timeout=15);log=w/name/'result.log';log.write_bytes(r.stdout+r.stderr);m=re.fullmatch(rb'SMP checkpoint-pending status=(\d+) checks=35\n',r.stdout);wanted=item[4] if item else 0;assert m and int(m[1])==wanted and r.returncode==wanted,(name,wanted,r.returncode,r.stdout,r.stderr);results.append(dict(name=name,expected_checkpoint=wanted,exit_code=r.returncode,log_sha256=sha(log)));print(name,wanted,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),checks_per_run=35,cases=results,source_sha256=manifest,compiler_sha256=sha(a.compiler),physical_hardware=False,media_durability_verified=False,trusted_anchor_verified=False),indent=2)+'\n');print('PASS:9 pending-frame defects detected at the intended checkpoints')
if __name__=='__main__':main()
