#!/usr/bin/env python3
"""Detect checkpoint storage ordering/ownership defects at intended checkpoints."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-checkpoint-store-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('ACK-before-trusted-reload','cs_io_done','if cs_state==3 {cs_state=4;return 1;}','if cs_state==3 {sd_done(cs_sequence,cs_revision,0,now);cs_state=4;return 1;}',103),
  ('initial-anchor-floor-ignored','cs_io_done','value<0 || value!=cs_sequence-1 || value!=sd_sequence','0',17),
  ('advance-compares-wrong-floor','cs_next_io','cs_io_expected=cs_sequence-1;','cs_io_expected=0;',105),
  ('media-MAC-not-verified','cs_media_verified','r=ck_pending_verify(cs_work+64,cs_work+80,kv_value,kv_value_size,cs_scratch(),ck_seal_work(64+40*cs_entries));','r=0;',17),
  ('media-error-leaves-settings-busy','cs_fail','if cs_state==2 && kv_work==cs_store && kv_busy {kv_io_fail(status);}','',17),
  ('stale-completion-accepted','cs_io_done','!cs_io_token || token!=cs_io_token','!cs_io_token',101),
  ('peek-replaces-request-lease','cs_next_io','if cs_io_token {return cs_io_kind;}','if cs_io_token {cs_io_token=cs_io_token+1;return cs_io_kind;}',100),
  ('failure-does-not-fault-gate','cs_fail','if sd_work==cs_gate && sd_busy && sd_frozen_sequence==cs_sequence && sd_frozen_revision==cs_revision','if 0',17),
  ('frozen-frame-not-cleared','cs_clear_frame','nb_zero(cs_frame(),cs_size(cs_entries)-128);','nb_zero(cs_scratch(),ck_seal_work(64+40*cs_entries));',13),
  ('deinit-leaves-storage-key','cs_deinit','nb_zero(cs_work,cs_size(cs_entries));','',16),
  ('reinit-reuses-provider-tokens','cs_init','cs_now=0;','cs_now=0;cs_floor=0;',7),
  ('wrong-final-ACK-sequence','cs_io_done','r=sd_done(cs_sequence,cs_revision,0,now);','r=sd_done(cs_sequence+1,cs_revision,0,now);',12),
  ('wrong-advance-or-confirm-value-accepted','cs_io_done','if value!=cs_sequence {return cs_fail(-116,now);}','',17),
  ('ACKs-new-dirty-revision','cs_io_done','r=sd_done(cs_sequence,cs_revision,0,now);','r=sd_done(cs_sequence,sd_revision,0,now);',12),
  ('completion-clock-rolls-back','cs_io_done','now<cs_now || ','',29),
  ('anchor-request-loses-scope','cs_next_io','cs_io_scope=cs_work+80;','cs_io_scope=0;',100),
 ]
 results=[]
 for item in [None]+changes:
  name=item[0] if item else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if item:
   _,fn,before,after,_=item;h['change'](tree/'lib/net/smp-checkpoint-store.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';c=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-checkpoint-store-native.flex'),'-o',str(exe)],cwd=tree,env=env,capture_output=True,timeout=30);(w/name/'compile.log').write_bytes(c.stdout+c.stderr);assert c.returncode==0,(name,c.stdout,c.stderr)
  r=subprocess.run([str(exe)],cwd=tree,env=env,capture_output=True,timeout=15);log=w/name/'result.log';log.write_bytes(r.stdout+r.stderr);m=re.fullmatch(rb'SMP checkpoint-store status=(\d+) checks=(\d+)\n',r.stdout);wanted=item[4] if item else 0;assert m and int(m[1])==wanted and r.returncode==wanted,(name,wanted,r.returncode,r.stdout,r.stderr)
  if not item:assert int(m[2])==1005
  results.append(dict(name=name,expected_checkpoint=wanted,exit_code=r.returncode,checks=int(m[2]),log_sha256=sha(log)));print(name,wanted,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=results,source_sha256=manifest,compiler_sha256=sha(a.compiler),physical_hardware=False,physical_media_durability_verified=False,trusted_physical_anchor_verified=False),indent=2)+'\n');print('PASS:',len(changes),'storage transaction defects detected at intended checkpoints')
if __name__=='__main__':main()
