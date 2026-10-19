#!/usr/bin/env python3
"""Independent C mask/ABI checks plus isolated native scheduler defects."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/sdk-masked-waits.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
mask='if esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}'
mutations=[
 ('yield-mask-ignored','esp32-sdk-task-core.flex','esp_sdk_yield',mask,'',101),
 ('delay-mask-ignored','esp32-sdk-task-core.flex','esp_sdk_delay',mask,'',102),
 ('wait-mask-ignored','esp32-sdk-task-core.flex','esp_sdk_task_wait',mask,'',104),
 ('self-delete-published-before-guard','esp32-sdk-task-core.flex','esp_sdk_task_delete','if task==esp_sdk_current &&','if task==esp_sdk_current {store64(task+544,2);}if task==esp_sdk_current &&',105),
 ('semaphore-blocks-while-masked','esp32-sdk-sync-core.flex','esp_sdk_sem_take','let blocking=ticks && esp_sdk_can_block();','let blocking=ticks;',106),
 ('queue-blocks-while-masked','esp32-sdk-sync-core.flex','esp_sdk_queue_op','if !ticks || !esp_sdk_can_block()','if !ticks',108),
 ('event-blocks-while-masked','esp32-sdk-sync-core.flex','esp_sdk_event_wait','let blocking=ticks && esp_sdk_can_block();','let blocking=ticks;',111),
 ('unavailable-mutex-reported-success','esp32-sdk-sync-core.flex','esp_sdk_mutex_lock','if !blocking {return 0;}','if !blocking {return 1;}',110),
 ('timer-poll-mask-ignored','esp32-sdk-timer-core.flex','esp_sdk_timer_poll','if !esp_sdk_can_block() {return -16;}','',118),
 ('wifi-stop-mask-ignored','esp32-wifi-core.flex','esp_wifi_station_stop','esp_sdk_irq_blocked(ps) || ','',112),
 ('wifi-start-mask-ignored','esp32-wifi-core.flex','esp_wifi_station_start','esp_sdk_irq_blocked(ps) || ','',113),
 ('wifi-deinit-mask-ignored','esp32-wifi-core.flex','esp_wifi_station_deinit','esp_sdk_irq_blocked(ps) || ','',114),
 ('wifi-init-mask-ignored','esp32-wifi-core.flex','esp_wifi_station_init','esp_sdk_irq_blocked(ps) || ','',115),
 ('BT-init-mask-ignored','esp32-bluetooth.flex','esp_bt_controller_init','(ps&15) || ','',116),
 ('BT-deinit-mask-ignored','esp32-bluetooth.flex','esp_bt_controller_deinit','(ps&15) || ','',117),
 ('immediate-semaphore-rejected','esp32-sdk-sync-core.flex','esp_sdk_sem_take','if !s {return 0;}','if !s || !esp_sdk_can_block() {return 0;}',202),
 ('immediate-queue-rejected','esp32-sdk-sync-core.flex','esp_sdk_queue_op','return esp_sdk_queue_try(q,item,operation);','return 0;',203),
 ('immediate-mutex-rejected','esp32-sdk-sync-core.flex','esp_sdk_mutex_lock','if !m || !esp_sdk_current ||','if !esp_sdk_can_block() || !m || !esp_sdk_current ||',204),
 ('immediate-event-rejected','esp32-sdk-sync-core.flex','esp_sdk_event_wait','let blocking=ticks && esp_sdk_can_block();','if !esp_sdk_can_block() {return 0;}let blocking=ticks && esp_sdk_can_block();',111),
]
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
records=[]
for mutation in [None]+mutations:
 name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree)
 # Observe attempts to touch the SDK clock in forbidden contexts; a timeout
 # alone never counts as detection of a defective wait.
 h['change'](tree/'lib/platform/esp32-sdk-task-core.flex','esp_sdk_now',lambda text:h['once'](text,'let ps=esp32_irq_save();','mw_clock_calls=mw_clock_calls+1;let ps=esp32_irq_save();'))
 if mutation:
  _,file,fn,before,after,expected=mutation;h['change'](tree/'lib/platform'/file,fn,lambda text:h['once'](text,before,after))
 fixture=tree/'tests/esp32/sdk-masked-waits.flex';out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
 with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
 text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
 if not mutation:ok=ok and 'C cases=0000000000000036' in text
 else:ok=ok and f'MASKED WAIT FAIL {expected:016x}' in text and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
 row=dict(name=name,expected_behavior=bool(ok),expected_failure=expected if mutation else None,exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,C_masked_cases=54,SDK_clock_observer=True,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Masked runtime contract passes; all nineteen isolated defects detected')
