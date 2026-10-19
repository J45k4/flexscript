#!/usr/bin/env python3
"""Independent peer corpus controls for SMP durable effect barriers."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-durable-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('uncommitted-packet-published','sd_next_packet','r=sd_allowed(token);if r {return r;}',''),
  ('uncommitted-event-published','sd_next_event','r=sd_allowed(token);if r {return r;}',''),
  ('key-revision-not-updated','sd_sync','store64(sd_key_revision(i),sd_revision);','store64(sd_key_revision(i),0);'),
  ('ACK-covers-later-mutations','sd_done','sd_durable=revision;','sd_durable=sd_revision;'),
  ('ACK-ignores-sequence','sd_done',' || sequence!=sd_frozen_sequence',''),
  ('ACK-ignores-revision','sd_done',' || revision!=sd_frozen_revision',''),
  ('positive-status-releases-output','sd_done','if status>0 {return -22;}',''),
  ('storage-error-treated-as-success','sd_done','if status<0 {','if 0 {'),
  ('fault-retains-packet-view','sd_fault','sm_views(sm_packet_connection);',''),
  ('fault-retains-event-view','sd_fault','sm_views(sm_event_connection);',''),
  ('input-consumed-before-admission-durable','sd_input','if load64(q+8) && code>=1 && code<=14 && code!=5','if 0'),
  ('consent-accepted-before-admission-durable','sd_consent','if accepted {r=sd_allowed(token);if r {return r;}}',''),
  ('crypto-handoff-before-admission-durable','sd_phase2','return sd_allowed(token);','return 0;'),
  ('pending-checkpoint-overwritten','sd_checkpoint','if sd_busy {return -16;}',''),
  ('peek-claims-unfrozen-revision','sd_checkpoint_peek','sd_checkpoint_revision=sd_frozen_revision;','sd_checkpoint_revision=sd_revision;'),
  ('snapshot-copied-to-shadow-buffer','sd_checkpoint','sr_export(sd_frozen(),','sr_export(sd_shadow(0),'),
  ('stale-ACK-discards-pending-payload','sd_done','{return -116;}','{sd_busy=0;nb_zero(sd_frozen(),sr_checkpoint_size());return -116;}'),
  ('checkpoint-reuses-sequence','sd_checkpoint','sd_frozen_sequence=sd_sequence+1;','sd_frozen_sequence=sd_sequence;'),
  ('ACK-skips-timeout-reconciliation','sd_done','r=sd_tick(now);if r {return r;}',''),
  ('issued-frame-ACK-blocked-by-later-write','sd_packet_sent','r=so_packet_sent(token,generation,now);','r=sd_allowed(token);if r {return r;}r=so_packet_sent(token,generation,now);'),
  ('unrelated-pending-write-blocks-committed-peer','sd_allowed','let required=','if sd_busy {return -11;}let required='),
  ('all-peers-depend-on-latest-mutation','sd_required','return load64(sd_key_revision(i));','return sd_revision;'),
  ('completed-attempt-change-not-captured','sd_sync','if !nb_equal(sd_shadow(i),sr_slot(i),64)','if load64(sr_slot(i)+32) && !nb_equal(sd_shadow(i),sr_slot(i),64)'),
  ('deinit-abandons-dirty-checkpoint','sd_deinit','if so_active || sd_busy || sd_sensitive_work || sd_revision>sd_durable','if so_active'),
  ('deinit-abandons-active-owner','sd_deinit','so_active || ',''),
  ('reinit-accepts-sequence-rollback','sd_init','if sequence<sd_sequence_floor {return -116;}',''),
  ('deinit-reuses-revision-floor','sd_deinit','sd_work=0;','sd_revision_floor=0;sd_work=0;'),
  ('partial-shadow-loses-identity-history','sd_sync','nb_copy(old,current,64);','nb_copy(old,current,32);'),
  ('sequence-wrap-publishes-negative-token','sd_checkpoint','if sd_sequence==9223372036854775807 {return sd_fault(-75);}',''),
  ('ledger-floor-rollback-accepted','sd_sync','if sr_floor<sd_seen_floor {return sd_fault(-116);}',''),
  ('owner-fault-not-latched','sd_ready','let r=so_ready();if r {return sd_fault(r);}return r;','return 0;'),
 ]

 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/net/smp-durable.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-durable-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP DURABLE FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP durable ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS: complete durable peer corpus;',len(changes),'barrier/storage-ACK defects detected')
if __name__=='__main__':main()
