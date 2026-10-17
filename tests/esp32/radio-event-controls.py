#!/usr/bin/env python3
"""Real CPU task interleavings and independent C radio event observers."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/radio-event-preempt.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[('esp_radio_events=esp_radio_events+1;','let count=esp_radio_events;ev_gate(1);esp_radio_events=count+1;'),('if id==1 {esp_radio_scan_status= -1;','if id==1 {ev_gate(2);esp_radio_scan_status= -1;'),('esp_radio_event_data=data;esp_radio_event_size=size;','esp_radio_event_data=data;ev_gate(3);esp_radio_event_size=size;')]
mutations=[
 ('counter-publication-unmasked','let ps=esp32_irq_save();','let ps=esp32_irq_save();if ev_mode==1 {esp32_irq_restore(ps);}',101),
 ('scan-publication-unmasked','let ps=esp32_irq_save();','let ps=esp32_irq_save();if ev_mode==2 {esp32_irq_restore(ps);}',102),
 ('payload-publication-unmasked','let ps=esp32_irq_save();','let ps=esp32_irq_save();if ev_mode==3 {esp32_irq_restore(ps);}',103),
 ('event-count-not-incremented','esp_radio_events=count+1;','esp_radio_events=count;',101),
 ('hook-not-invoked','esp32_call(hook,id);','',101),
 ('outer-data-cleared','esp_radio_event_data=previous_data;','esp_radio_event_data=0;',401),
 ('outer-size-cleared','esp_radio_event_size=previous_size;','esp_radio_event_size=0;',401),
 ('last-event-rewound-after-nesting','}esp32_irq_restore(ps);return 0;','}esp_radio_last_event=id;esp32_irq_restore(ps);return 0;',403),
 ('scan-completion-missing','esp_radio_scan_done=1;','',102),
 ('short-scan-accepted','size>=6','size>=4',421),
 ('no-hook-event-not-counted','esp_radio_events=count+1;','if esp_radio_event_hook {esp_radio_events=count+1;}',403),
 ('saved-PS-not-restored','}esp32_irq_restore(ps);return 0;','}if ev_mode==5 {esp32_irq_restore(0);}else {esp32_irq_restore(ps);}return 0;',411),
]
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
records=[]
for mutation in [None]+mutations:
 name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree);module=tree/'lib/platform/esp32-radio-os-core.flex'
 for before,after in probes:h['change'](module,'esp_radio_dispatch_event',lambda text:h['once'](text,before,after))
 if mutation:
  _,before,after,expected=mutation;h['change'](module,'esp_radio_dispatch_event',lambda text:h['once'](text,before,after))
 fixture=tree/'tests/esp32/radio-event-preempt.flex';fixture.write_text(h['once'](fixture.read_text(),'global ev_expect_hooks=0;','global ev_expect_hooks=1;'))
 out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
 with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
 text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
 if not mutation:ok=ok and 'hooks=0000000000000003 masked=0000000000000003' in text
 else:ok=ok and f'RADIO EVENT FAIL {expected:016x}' in text and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
 row=dict(name=name,expected_behavior=bool(ok),expected_failure=expected if mutation else None,exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,forced_windows=3,masked_windows=3,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected radio event transactions pass; all twelve isolated defects detected')
