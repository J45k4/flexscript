#!/usr/bin/env python3
"""Check isolated restart-recovery defects against the complete independent corpus."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text());h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-checkpoint-recover-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('imports-before-anchor-confirmation','cr_scan','r=kv_mount();','r=sr_import(cr_payload(),64+40*cr_entries,now);r=kv_mount();',7),
  ('CAS-success-skips-confirming-load','cr_io_done','if cr_state==2 {cr_state=3;return 1;}','if cr_state==2 {cr_state=3;}',16),
  ('trusted-request-has-wrong-scope','cr_next_io','cr_io_scope=cr_work+80;','cr_io_scope=cr_work+64;',7),
  ('CAS-compares-wrong-anchor','cr_next_io','cr_io_expected=cr_anchor;','cr_io_expected=0;',13),
  ('frame-authentication-skipped','cr_decode','let r=ck_open(cr_work+64,cr_work+80,sequence,revision,frame,ck_size(bytes),cr_payload(),bytes,cr_scratch(),112);','nb_copy(cr_payload(),frame+48,bytes);let r=bytes;',17),
  ('semantic-validation-delayed-until-after-advance','cr_decode','r=sr_validate(cr_payload(),bytes,now);','r=0;',16),
  ('stale-anchor-completion-accepted','cr_io_done','!cr_io_token || token!=cr_io_token','!cr_io_token',9),
  ('peek-replaces-anchor-lease','cr_next_io','if cr_io_token {return cr_io_kind;}','if cr_io_token {cr_io_token=cr_io_token+1;return cr_io_kind;}',8),
  ('callback-time-rolls-back','cr_io_done','now<cr_now || ','',12),
  ('reinit-reuses-anchor-token','cr_init','cr_now=sr_now;','cr_now=sr_now;cr_floor=0;',5),
  ('future-gap-not-rejected-before-provider-effects','cr_scan','if sequence>cr_anchor+1 {return -116;}','',16),
  ('stale-frame-not-rejected-before-provider-effects','cr_scan','if cr_sequence<cr_anchor {return -116;}','',16),
  ('last-bank-replaces-highest-sequence','cr_scan','if sequence>cr_sequence','if 1',15),
  ('mounted-snapshot-not-bound-before-advance','cr_scan',' || !nb_equal(kv_value,cr_frame(),size)','',16),
  ('final-authentication-and-decode-skipped','cr_io_done','r=cr_decode(cr_frame(),cr_sequence,cr_revision,now);if r<0 {return cr_fail(r);}','',17),
  ('wrong-advance-or-confirm-value-accepted','cr_io_done','if value!=cr_sequence {return cr_fail(-116);}','',15),
  ('failure-retains-copied-key','cr_fail','nb_zero(cr_work,cr_size(cr_entries));','',21),
  ('success-retains-copied-key','cr_io_done','nb_zero(cr_work,cr_size(cr_entries));','',19),
  ('idle-deinit-retains-copied-key','cr_deinit','nb_zero(cr_work,cr_size(cr_entries));','',26),
  ('second-bank-not-inspected','cr_scan','while i<2','while i<1',15),
  ('selected-revision-not-retained','cr_scan','cr_revision=load64(frame+16);','cr_revision=1;',15),
 ]
 results=[]
 for item in [None]+changes:
  name=item[0] if item else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if item:
   _,fn,before,after,_=item;h['change'](tree/'lib/net/smp-checkpoint-recover.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';c=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-checkpoint-recover-native.flex'),'-o',str(exe)],cwd=tree,env=env,capture_output=True,timeout=30);(w/name/'compile.log').write_bytes(c.stdout+c.stderr);assert c.returncode==0,(name,c.stdout,c.stderr);parts=[];detected=False
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];r=subprocess.run([str(exe),str(data)],cwd=tree,env=env,capture_output=True,timeout=30);log=w/name/f'part-{i}.log';log.write_bytes(r.stdout+r.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if r.returncode:
    m=re.search(rb'SMP RECOVER FAIL case=(\d+) step=0 offset=(\d+)',r.stderr);assert item and r.returncode==8 and m and int(m[2])==item[4],(name,r.returncode,item[4] if item else None,r.stdout,r.stderr);detected=True;break
   assert re.fullmatch(rb'PASS: SMP recover \d+ independent observations\n',r.stdout),(name,r.stdout,r.stderr)
  assert detected==bool(item),name;results.append(dict(name=name,detected=detected,expected_field=item[4] if item else None,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==h for n,h in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=results,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_media=False,trusted_physical_anchor_verified=False),indent=2)+'\n');print('PASS:',len(changes),'recovery defects detected at intended checkpoints')
if __name__=='__main__':main()
