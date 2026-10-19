#!/usr/bin/env python3
"""Native Wi-Fi control admission and stale-result defect controls on stock QEMU."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/wifi-control-preempt.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[('esp_wifi_control_begin','esp_wifi_control_active=1;','ct_gate(6);esp_wifi_control_active=1;'),('esp_wifi_poll','esp_wifi_control_active=1;','ct_gate(7);esp_wifi_control_active=1;'),('esp_wifi_event','esp_wifi_channel=0;','ct_gate(8);esp_wifi_channel=0;'),('esp_wifi_retry_policy','esp_wifi_retry_max=max_ms;','ct_gate(9);esp_wifi_retry_max=max_ms;'),('esp_wifi_schedule_retry','esp_wifi_retry_at=now+delay*1000;','ct_gate(10);esp_wifi_retry_at=now+delay*1000;'),('esp_wifi_join','esp_sdk_free(config);','esp_sdk_free(config);ct_gate(11);')]
mutations=[
 ('admission-unmasked','esp_wifi_control_begin',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if ct_mode==6 {esp32_irq_restore(ps);}')],106),
 ('poll-admission-unmasked','esp_wifi_poll',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if ct_mode==7 {esp32_irq_restore(ps);}')],107),
 ('event-publication-unmasked','esp_wifi_event',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if ct_mode==8 {esp32_irq_restore(ps);}')],108),
 ('policy-publication-unmasked','esp_wifi_retry_policy',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if ct_mode==9 {esp32_irq_restore(ps);}')],109),
 ('retry-publication-unmasked','esp_wifi_schedule_retry',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if ct_mode==10 {esp32_irq_restore(ps);}')],110),
 ('connect-stale-result-committed','esp_wifi_connect_owned',[('if esp_wifi_generation==generation {','if 1 {')],401),
 ('disconnect-stale-result-committed','esp_wifi_disconnect',[('if esp_wifi_generation==generation {','if 1 {')],405),
 ('timeout-stale-result-committed','esp_wifi_poll',[('if esp_wifi_generation==generation {','if 1 {')],417),
 ('timeout-uses-old-clock','esp_wifi_poll',[('esp_wifi_schedule_retry(esp_sdk_now());','esp_wifi_schedule_retry(now);')],410),
 ('credentials-not-cleared','esp_wifi_join',[('while i<184 {store8(config+i,0);i=i+1;}','while i<0 {store8(config+i,0);i=i+1;}')],101),
 ('control-released-before-connect','esp_wifi_join',[('if !r {r=esp_wifi_reconnect_owned();}','if !r {esp_wifi_control_end();r=esp_wifi_reconnect_owned();}')],101),
 ('control-released-before-cleanup','esp_wifi_join',[('esp_sdk_free(config);ct_gate(11);','esp_sdk_free(config);if ct_mode==11 {esp_wifi_control_end();}ct_gate(11);')],111),
 ('lifecycle-control-guard-missing','esp_wifi_operations_active',[('return esp_wifi_control_active || esp_wifi_packets_active();','return esp_wifi_packets_active();')],101),
 ('busy-disconnect-cancels-intent','esp_wifi_disconnect',[('if r {return r;}','if r {esp_wifi_want_link=0;return r;}')],101),
 ('connect-vendor-call-masked','esp_wifi_connect_owned',[('let r=esp32_call32(','let held=esp32_irq_save();let r=esp32_call32('),('ps=esp32_irq_save();if esp_wifi_generation','esp32_irq_restore(held);ps=esp32_irq_save();if esp_wifi_generation')],101),
 ('poll-busy-guard-missing','esp_wifi_poll',[('esp_wifi_control_active || ','')],101),
 ('stopped-event-keeps-deadline','esp_wifi_event',[('esp_wifi_retry_at=0;esp_wifi_connect_until=0;esp_wifi_generation','esp_wifi_retry_at=0;esp_wifi_generation')],403),
 ('allocation-error-keeps-lease','esp_wifi_join',[('if !config {esp_wifi_control_end();return -12;}','if !config {return -12;}')],409),
]
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
records=[]
for mutation in [None]+mutations:
 name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree);module=tree/'lib/platform/esp32-wifi-core.flex'
 for fn,before,after in probes:h['change'](module,fn,lambda text:h['once'](text,before,after))
 if mutation:
  _,fn,changes,expected=mutation
  for before,after in changes:h['change'](module,fn,lambda text:h['once'](text,before,after))
 fixture=tree/'tests/esp32/wifi-control-preempt.flex';fixture.write_text(h['once'](fixture.read_text(),'global ct_expect_hooks=0;','global ct_expect_hooks=1;'))
 out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
 with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
 text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
 if not mutation:ok=ok and 'hooks=0000000000000006 masked=0000000000000005' in text
 else:ok=ok and f'WIFI CONTROL FAIL {expected:016x}' in text and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
 row=dict(name=name,expected_behavior=bool(ok),expected_failure=expected if mutation else None,exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,forced_windows=6,masked_windows=5,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected Wi-Fi control transactions pass; all eighteen isolated defects detected')
