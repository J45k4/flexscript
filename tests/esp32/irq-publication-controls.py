#!/usr/bin/env python3
"""Real CPU7/C observers at isolated radio publication windows; QEMU unchanged."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
ROOT=Path(__file__).resolve().parents[2]
h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for name in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+name,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose a fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/radio-irq-publication.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[
 ('esp32-radio-os.flex','esp_radio_cb_set_isr','esp_radio_isr=b;','esp_radio_isr=b;ai_probe(1);'),
 ('esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq5=b;','esp_bt_irq5=b;ai_probe(2);'),
 ('esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq7=b;','esp_bt_irq7=b;ai_probe(3);'),
 ('esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq8=b;','esp_bt_irq8=b;ai_probe(4);'),
 ('esp32-radio-os.flex','esp_radio_cb_ints_on','esp32_irq_enabled()|2','ai_mask_probe(esp32_irq_enabled(),5)|2'),
 ('esp32-bluetooth.flex','esp_bt_ints_on','esp32_irq_enabled()|2|128','ai_mask_probe(esp32_irq_enabled(),6)|2|128'),
 ('esp32-radio-os.flex','esp_radio_cb_set_intr','esp32_store32(0x3ff00104+b*4,1);','ai_probe(7);esp32_store32(0x3ff00104+b*4,1);')]
mutations=[
 ('wifi-pair-unprotected','esp32-radio-os.flex','esp_radio_cb_set_isr','esp_radio_isr=b;','esp32_irq_restore(0);esp_radio_isr=b;',101),
 ('bt-pair5-unprotected','esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq5=b;','esp32_irq_restore(0);esp_bt_irq5=b;',102),
 ('bt-pair7-unprotected','esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq7=b;','esp32_irq_restore(0);esp_bt_irq7=b;',103),
 ('bt-pair8-unprotected','esp32-bluetooth.flex','esp_bt_set_isr','esp_bt_irq8=b;','esp32_irq_restore(0);esp_bt_irq8=b;',104),
 ('wifi-enable-loses-bit','esp32-radio-os.flex','esp_radio_cb_ints_on','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',105),
 ('bt-enable-loses-bit','esp32-bluetooth.flex','esp_bt_ints_on','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',106),
 ('route-claim-unprotected','esp32-radio-os.flex','esp_radio_cb_set_intr','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',107),
 ('pending-event-dropped','esp32-irq.flex','esp_irq_software','if first {esp32_irq_clear(128);}','esp32_irq_clear(128);',103),
 ('wifi-capacity-not-preflighted','esp32-radio-os.flex','esp_radio_cb_set_isr','r=esp_irq_reserve(!esp_irq_handler(0));','r=0;',201),
 ('bt-capacity-not-preflighted','esp32-bluetooth.flex','esp_bt_set_isr','r=esp_irq_reserve(needed);','r=0;',202),
 ('bt-second-source-not-preflighted','esp32-bluetooth.flex','esp_bt_set_isr','r=esp_radio_irq_can_claim(7,handler);','r=0;',203),
 ('foreign-handler-overwritten','esp32-radio-lifecycle-core.flex','esp_radio_irq_can_claim','existing!=handler','0',204)]
records=[]
def sha(path):
 with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
for mutation in [None]+mutations:
    name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree)
    if mutation:
        _,file,fn,before,after,code=mutation
        h['change'](tree/'lib/platform'/file,fn,lambda text:h['once'](text,before,after))
    for file,fn,before,after in probes:
        h['change'](tree/'lib/platform'/file,fn,lambda text:h['once'](text,before,after))
    fixture=tree/'tests/esp32/radio-irq-publication.flex';fixture.write_text(h['once'](fixture.read_text(),'global ai_expect_hooks=0;','global ai_expect_hooks=1;'))
    out=w/name/'firmware';log=w/name/'execution.log';args=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
    with log.open('w') as stream:r=subprocess.run(args,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
    expected=f'IRQ PUBLICATION FAIL {code:016x}' if mutation else 'hooks=000000000000001c masked=000000000000001c';text=log.read_text();detected=r.returncode==(1 if mutation else 0) and expected in text
    if mutation:
        qmp=out/'qmp-failure.log';detected=detected and 'main returned zero' in text and qmp.exists() and 'SHUTDOWN' in qmp.read_text()
    record=dict(name=name,expected_behavior=detected,exit_code=r.returncode,expected_uart=expected,log=str(log),log_sha256=sha(log));records.append(record);print(json.dumps(record),flush=True)
    (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,source_sha256=manifest,tools_sha256={str(Path(v).resolve()):sha(v) for v in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
    if not detected:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected28 publication windows pass; all twelve isolated defects detected')
