#!/usr/bin/env python3
"""Independent peer corpus controls for SMP negotiation and session ownership."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();vectors=Path(a.vectors).resolve();v=json.loads((vectors/'report.json').read_text())
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-pairing-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 bond='let bond=(load8(preq+3)&3)==1 && (load8(pres+3)&3)==1;'
 changes=[
  ('SC-requires-only-one-peer','sm_method','((auth&remote_auth)&8)','((auth|remote_auth)&8)'),
  ('MITM-requires-both-peers','sm_method','!((auth|remote_auth)&4)','!((auth&remote_auth)&4)'),
  ('legacy-OOB-accepts-one-sided-data','sm_method','(!sc && oob && remote_oob)','(!sc && (oob || remote_oob))'),
  ('legacy-numeric-comparison','sm_method','if sc && (io==1 || io==4)','if (io==1 || io==4)'),
  ('legacy-keyboard-display-role','sm_method','if role {action=1;}','if !role {action=1;}'),
  ('maximum-instead-of-minimum-key','sm_negotiate','if load8(pres+4)<size','if load8(pres+4)>size'),
  ('minimum-key-policy-missing','sm_negotiate','if size<load64(p+32)','if 0'),
  ('bonding-with-one-peer','sm_negotiate',bond,bond.replace(' && ',' || ')),
  ('distribution-union','sm_negotiate','load8(preq+5)&load8(pres+5)&15','((load8(preq+5)|load8(pres+5))&15)'),
  ('method-plan-claims-authentication','sm_negotiate','store64(p+136,authenticated);','store64(p+136,authenticated);store64(p+224,authenticated);'),
  ('timeout-one-tick-late','sm_expire','sm_now>=load64(p+152)','sm_now>load64(p+152)'),
  ('timeout-permits-more-input','sm_live_time','if load64(p+8)==5 {return -110;}','if 0 {return -110;}'),
  ('TX-ACK-extends-deadline','sm_packet_sent','nb_zero(p+320,72);','store64(p+152,sm_now+30000);nb_zero(p+320,72);'),
  ('temporary-keys-not-wiped','sm_clear_attempt','nb_zero(p+320,1216);','nb_zero(p+320,72);'),
  ('closed-link-keeps-key-material','sm_close','nb_zero(p,1536);','nb_zero(p,512);'),
  ('stale-TX-ACK-accepted','sm_packet_sent',' || load64(p+200)!=generation',''),
  ('stale-consent-accepted','sm_consent',' || load64(p+192)!=generation',''),
  ('raw-request-RFU-normalized','sm_input','nb_copy(p+272,packet,7);','nb_copy(p+272,packet,7);store8(p+275,load8(p+275)&63);'),
  ('legacy-LinkKey-advertised','sm_config',' && (auth&8 || !((load8(config+4)|load8(config+5))&8))',''),
  ('legacy-LinkKey-not-ignored','sm_input','let mask=7;','let mask=15;'),
  ('crypto-input-consumed-before-response-ACK','sm_input','if state==3 {if load64(p+168) {return -11;}return 2;}','if state==3 {return 2;}'),
  ('snapshot-claims-candidate-authentication','sm_snapshot','store64(out+80,load64(p+224))','store64(out+80,load64(p+136))'),
  ('RFU-commands-extend-timeout','sm_input','if code==0 || code>14 {return 0;}','if code==0 || code>14 {store64(p+152,sm_now+30000);return 0;}'),
  ('foreign-packet-view-cleared','sm_views','if sm_packet_connection==token','if 1'),
  ('stale-event-ACK-accepted','sm_event_consumed','load64(p+192)!=generation || ',''),
  ('connection-floor-lost-on-deinit','sm_deinit','sm_work=0;','sm_token_floor=0;sm_work=0;'),
  ('clock-rollback-accepted','sm_time','now<sm_now || ',''),
  ('timeout-retains-output-lease','sm_expire','sm_clear_attempt(p);',''),
 ]
 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/net/smp-pairing.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-pairing-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr);detected=False;parts=[]
  for i,part in enumerate(v['parts']):
   data=vectors/part['file'];assert sha(data)==part['sha256'];q=subprocess.run([str(exe),str(data)],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/f'part-{i}.log';log.write_bytes(q.stdout+q.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if q.returncode:
    assert mutation and q.returncode in [8,9] and b'SMP PAIRING FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr);detected=True;break
   assert b'PASS: SMP pairing ' in q.stdout,(name,q.stdout,q.stderr)
  assert detected==bool(mutation),name;cases.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(vectors/'report.json'),physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS:complete peer corpus;all28 negotiation/ownership/timeout defects detected')
if __name__=='__main__':main()
