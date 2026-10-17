#!/usr/bin/env python3
"""Independent peer corpus controls for SMP pairing-session admission ownership."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-session-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('local-start-skips-admission','so_start','r=so_admit(q,now);if r {return r;}',''),
  ('incoming-start-skips-admission','so_input','if (code==1 || code==11) && !ignored_security && !load64(q+8)','if 0'),
  ('uses-air-address-as-identity','so_open','nb_copy(q+16,identity,7);','nb_copy(q+16,peer,7);'),
  ('security-request-does-not-reuse-lease','so_admit','if load64(q+8) {return 0;}',''),
  ('feature-ready-releases-lease','so_cleanup','state==4 || state==5','state==3 || state==4 || state==5'),
  ('consent-prompt-releases-lease','so_cleanup','state==4 || state==5','state==4 || state==5 || state==6'),
  ('failed-attempt-reported-successful','so_release','sr_finish(lease,1,now)','sr_finish(lease,0,now)'),
  ('disconnect-does-not-release-lease','so_close','r=so_release(q,now);if r {return r;}',''),
  ('timeout-does-not-reconcile-ledger','so_tick','return so_cleanup(now);','return 0;'),
  ('released-lease-left-in-owner','so_release','store64(q+8,0);',''),
  ('phase2-accepts-stale-generation','so_phase2',' || load64(p+192)!=generation',''),
  ('phase2-accepts-stale-lease','so_phase2','load64(q+8)!=lease || ',''),
  ('failure-accepts-stale-generation','so_failure',' || load64(p+192)!=generation',''),
  ('failure-accepts-stale-lease','so_failure','load64(q+8)!=lease || ',''),
  ('phase2-skips-ready-state','so_phase2',' || load64(p+8)!=3',''),
  ('phase2-runs-before-response-ACK','so_phase2','if load64(p+168) {return -11;}',''),
  ('ACK-skips-timeout-cleanup','so_packet_sent','r=so_tick(now);if r {return r;}',''),
  ('consent-failure-keeps-lease','so_consent','let cleanup=so_cleanup(now);if cleanup {return cleanup;}',''),
  ('peer-failure-keeps-lease','so_input','let cleanup=so_cleanup(now);if cleanup {return cleanup;}',''),
  ('local-wrong-role-consumes-attempt','so_start','if load64(p+16)!=security_request {return -22;}',''),
  ('retained-failure-TX-local-admission','so_start','if load64(p+168) {return -11;}',''),
  ('retained-failure-TX-peer-admission','so_input','if load64(p+168) {return -11;}',''),
  ('epoch-preflight-acquires-untimed-lease','so_input',' || (code==1 && load64(p+192)>=9223372036854775806)',''),
  ('denied-peer-hides-repeated-attempts','so_input','let reason=9;','let reason=8;'),
  ('snapshot-claims-feature-plan-authenticated','so_snapshot','nb_zero(out+224,32);','store64(out+80,load64(sm_find(token)+136));nb_zero(out+224,32);'),
  ('ledger-hijack-not-latched','so_ready','if !r || load64(r+32)!=lease','if 0'),
  ('snapshot-aliases-owner-storage','so_snapshot',' || !so_external(out,256)',''),
  ('input-aliases-owner-storage','so_input','(size && !so_external(packet,size))','0'),
  ('reinit-clears-retry-history','so_deinit','so_work=0;','nb_zero(sr_work,sr_size(sr_entries));so_work=0;'),
  ('closed-connection-retains-ownership-record','so_close','nb_zero(q,64);',''),
  ('clocks-updated-before-validation','so_tick','if !so_clock(now) {return -22;}','so_now=now;sm_now=now;sr_now=now;')
 ]

 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/net/smp-session.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-session-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP OWNER FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP owner ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS:complete peer corpus;all31 pairing-owner defects detected')
if __name__=='__main__':main()
