#!/usr/bin/env python3
"""Execute isolated ISR bool-ABI defects against guarded C and real IRQ peers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]
helper=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for name in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+name,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose a fresh work directory')
source=w/'production-source';manifest=helper['copy_closure'](ROOT/'tests/esp32/sdk-wake-abi.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
mutations=[
 ('wifi-clears-bool','esp32-radio-os-core.flex','esp_radio_cb_send_isr','return esp_sdk_queue_isr(a,b,1,c);','if c {store8(c,0);}return esp_sdk_queue_try(a,b,1);',1002),
 ('bt-give-clears-bool','esp32-bluetooth.flex','esp_bt_sem_give_isr','return esp_sdk_sem_give_isr(a,b);','if b {store8(b,0);}return esp_sdk_sem_give(a);',1002),
 ('bt-receive-clears-bool','esp32-bluetooth.flex','esp_bt_recv_isr','return esp_sdk_queue_isr(a,b,0,c);','if c {store8(c,0);}return esp_sdk_queue_try(a,b,0);',1002),
 ('bt-take-clears-bool','esp32-bluetooth.flex','esp_bt_sem_take_isr','return esp_sdk_sem_try(a);','if b {store8(b,0);}return esp_sdk_sem_try(a);',1002),
 ('word-store-corrupts-guard','esp32-sdk-sync-core.flex','esp_sdk_isr_wake_hint','store8(flag,1);','esp32_store32(flag,1);',1015),
 ('erase-accumulated-hint','esp32-sdk-sync-core.flex','esp_sdk_isr_wake_hint','if flag && !load8(flag)','if flag {store8(flag,0);}if flag && !load8(flag)',1002),
 ('missing-positive-hint','esp32-sdk-sync-core.flex','esp_sdk_isr_wake_hint','esp_sdk_task_wake_hint(esp_sdk_current,object,kind)','0',1002),
 ('queue-wake-not-requested','esp32-sdk-sync-core.flex','esp_sdk_queue_try','esp_sdk_reschedule_request();','',4000),
]
records=[]
def sha(path):
 with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
for name,file,fn,before,after,code in mutations:
    tree=w/name/'source';shutil.copytree(source,tree)
    helper['change'](tree/'lib/platform'/file,fn,lambda text:helper['once'](text,before,after))
    output=w/name/'firmware';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(output),'--source',str(tree/'tests/esp32/sdk-wake-abi.flex')];log=w/name/'execution.log'
    with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
    expected=f'WAKE FAIL {code:016x}';text=log.read_text();qmp=output/'qmp-failure.log';detected=r.returncode==1 and expected in text and 'main returned zero' in text and qmp.exists() and 'SHUTDOWN' in qmp.read_text()
    record=dict(name=name,detected=detected,exit_code=r.returncode,expected_uart=expected,log=str(log),log_sha256=sha(log));records.append(record);print(json.dumps(record),flush=True)
    (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['detected'] for x in records),controls=records,source_sha256=manifest,tools_sha256={str(Path(v).resolve()):sha(v) for v in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
    if not detected:raise RuntimeError(f'{name}: intended defect not detected; see {log}')
print('All eight C/ISR ABI defects detected with clean QEMU shutdown')
