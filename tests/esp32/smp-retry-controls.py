#!/usr/bin/env python3
"""Independent peer corpus controls for SMP retry admission and checkpoint ownership."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-retry-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('first-failure-skips-minimum','sr_grow','if !delay {return sr_min;}','if !delay {return sr_min*2;}'),
  ('failures-do-not-increase','sr_grow','return delay*2;','return delay;'),
  ('maximum-wait-not-capped','sr_grow','return sr_max;','return sr_max*2;'),
  ('no-cooldown-decay','sr_age','if !delay || !next || sr_now<next','if 1'),
  ('decay-is-one-tick-late','sr_age','sr_now<next','sr_now<=next'),
  ('cooldown-drops-existing-wait','sr_age','store64(p+24,0);','store64(p+24,0);store64(p+16,sr_now);'),
  ('query-restarts-wait','sr_wait','sr_age(p);','sr_age(p);store64(p+16,sr_now+load64(p+8));'),
  ('begin-bypasses-wait','sr_begin','if sr_wait_at(p) {return -11;}',''),
  ('parallel-attempt-same-identity','sr_begin','if load64(p+32) {return -16;}',''),
  ('capacity-evicts-active-peer','sr_begin','!load64(q+32) && !load64(q+8) && !sr_wait_at(q)','1'),
  ('capacity-evicts-penalized-peer','sr_begin',' && !load64(q+8)',''),
  ('stale-attempt-result-accepted','sr_finish','load64(q+32)==lease','load64(q+32)!=0'),
  ('success-erases-failure-history','sr_finish','store64(p+32,0);','if !result {store64(p+8,0);store64(p+24,0);}store64(p+32,0);'),
  ('completed-attempt-retains-lease','sr_finish','store64(p+32,0);',''),
  ('clock-can-roll-back','sr_clock','now>=sr_now','now>=0'),
  ('deinit-loses-generation-floor','sr_deinit','sr_work=0;','sr_floor=0;sr_work=0;'),
  ('generation-wrap-accepted','sr_begin','if sr_floor==9223372036854775807 {return -75;}',''),
  ('checkpoint-omits-live-attempt','sr_export','store64(q+32,load64(p+32)!=0);','store64(q+32,0);'),
  ('restart-drops-unfinished-failure','sr_import','if load64(q+32) {let delay=','if 0 {let delay='),
  ('export-skips-decay','sr_export','sr_age(p);',''),
  ('checkpoint-magic-ignored','sr_validate','!nb_equal(input,"SMPTRY01",8) || ',''),
  ('duplicate-identity-check-missing','sr_validate','if nb_equal(input+64+j*40,q,7)','if 0'),
  ('unused-checkpoint-bytes-ignored','sr_validate','if !sr_zero(input+64+count*40,(sr_entries-count)*40)','if 0'),
  ('rejected-checkpoint-changes-clock','sr_validate','let i=0;','sr_now=now;let i=0;'),
  ('decayed-cap-interval-rejected','sr_delay_valid','return value==0 || (value>=sr_min && value<=sr_max);','if value==0 || value==sr_max {return 1;}let n=sr_min;while n<sr_max {if n==value {return 1;}n=sr_grow(n);}return 0;'),
  ('restart-erases-remaining-wait','sr_import','now+load64(q+16)','now'),
  ('caller-storage-alias-accepted','sr_external',' && !(p<sr_work+sr_size(sr_entries) && sr_work<p+n)',''),
  ('unresolved-private-address-accepted','sr_identity',' && (load8(p+6)&192)==192',''),
  ('zero-minimum-wait-accepted','sr_init','min_wait<1 || ',''),
  ('deinit-discards-live-penalties','sr_deinit','if load64(p+32) || load64(p+8) || sr_wait_at(p)','if 0'),
  ('checkpoint-generation-rollback-accepted','sr_validate','if load64(input+40)<sr_floor {return -116;}',''),
  ('checkpoint-policy-mismatch-accepted','sr_validate',' || load64(input+24)!=sr_max',''),
 ]

 changes +=[
  ('unresolved-tag-rejected','sr_key','return sr_identity(p) || (sr_external(p,7) && load8(p)==2 && sr_zero(p+1,6));','return sr_identity(p);'),
  ('nonzero-unresolved-tag-accepted','sr_key',' && sr_zero(p+1,6)',''),
  ('unresolved-checkpoint-rejected','sr_validate','!sr_key(q)','!sr_identity(q)'),
  ('inherit-allows-live-attempts','sr_inherit','if (from && load64(from+32)) || (to && load64(to+32))','if 0'),
  ('inherit-erases-source-history','sr_inherit','store64(to+8,interval);','nb_zero(from,64);store64(to+8,interval);'),
  ('inherit-reduces-interval','sr_inherit','load64(to+8)>interval','load64(to+8)<interval'),
  ('inherit-shortens-existing-wait','sr_inherit','load64(to+16)>until','load64(to+16)<until'),
  ('inherit-shortens-decay-window','sr_inherit','load64(to+24)>decay','load64(to+24)<decay'),
  ('inherit-evicts-penalized-peer','sr_inherit','!load64(q+32) && !load64(q+8) && !sr_wait_at(q)','1'),
  ('inherit-loses-lease-floor','sr_inherit','store64(to+8,interval);','sr_floor=0;store64(to+8,interval);'),
  ('inherit-manufactures-active-lease','sr_inherit','store64(to+8,interval);','store64(to+32,sr_floor+1);store64(to+8,interval);'),
 ]

 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/net/smp-retry.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-retry-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP RETRY FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP retry ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS: complete peer corpus;',len(changes),'admission/checkpoint defects detected')
if __name__=='__main__':main()
