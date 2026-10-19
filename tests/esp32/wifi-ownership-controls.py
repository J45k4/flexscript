#!/usr/bin/env python3
"""Force native Wi-Fi packet ownership windows; use stock QEMU unchanged."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/wifi-ownership-preempt.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[
 ('esp_wifi_frames_init','    let ring=','    wc_gate(8);let ring='),
 ('esp_wifi_rx_callback','let ps=esp32_irq_save();','let ps=esp32_irq_save();wc_gate(9);'),
 ('esp_wifi_rx_callback','if accepted {let i=0;','if accepted {wc_gate(5);let i=0;'),
 ('esp_wifi_rx_callback','esp_wifi_rx_count=esp_wifi_rx_count+1;','let before=esp_wifi_rx_count;wc_gate(13);esp_wifi_rx_count=before+1;'),
 ('esp_wifi_receive','esp_wifi_rx_reading=1;','wc_gate(3);esp_wifi_rx_reading=1;'),
 ('esp_wifi_receive','esp32_irq_restore(ps);let i=0;','esp32_irq_restore(ps);wc_gate(4);let i=0;'),
 ('esp_wifi_receive','esp_wifi_rx_count=esp_wifi_rx_count-1;','let before=esp_wifi_rx_count;wc_gate(12);esp_wifi_rx_count=before-1;'),
 ('esp_wifi_transmit','esp_wifi_tx_active=esp_wifi_tx_active+1;','wc_gate(10);esp_wifi_tx_active=esp_wifi_tx_active+1;'),
 ('esp_wifi_transmit','esp_wifi_tx_packets=esp_wifi_tx_packets+1;','let before=esp_wifi_tx_packets;wc_gate(11);esp_wifi_tx_packets=before+1;'),
 ('esp_wifi_teardown','esp_sdk_free(esp_wifi_init_config);','wc_gate(6);esp_sdk_free(esp_wifi_init_config);')]
mutations=[
 ('ring-constructor-unmasked','esp_wifi_frames_init',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if wc_mode==8 {esp32_irq_restore(ps);}')],108),
 ('TX-admission-unmasked','esp_wifi_transmit',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if wc_mode==10 {esp32_irq_restore(ps);}')],110),
 ('RX-admission-unmasked','esp_wifi_receive',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if wc_mode==3 {esp32_irq_restore(ps);}')],103),
 ('callback-admission-unmasked','esp_wifi_rx_callback',[('let ps=esp32_irq_save();','let ps=esp32_irq_save();if wc_mode==9 {esp32_irq_restore(ps);}')],109),
 ('RX-consumer-lease-missing','esp_wifi_receive',[('esp_wifi_rx_reading=1;','')],103),
 ('callback-lease-expires-before-free','esp_wifi_rx_callback',[('    if eb {','    ps=esp32_irq_save();esp_wifi_rx_callbacks=esp_wifi_rx_callbacks-1;esp32_irq_restore(ps);\n    if eb {'),('    ps=esp32_irq_save();esp_wifi_rx_callbacks=esp_wifi_rx_callbacks-1;esp32_irq_restore(ps);return 0;','    return 0;')],102),
 ('TX-count-replaced-by-bool','esp_wifi_transmit',[('esp_wifi_tx_active=esp_wifi_tx_active+1;','esp_wifi_tx_active=1;'),('esp_wifi_tx_active=esp_wifi_tx_active-1;','esp_wifi_tx_active=0;')],101),
 ('callback-count-replaced-by-bool','esp_wifi_rx_callback',[('esp_wifi_rx_callbacks=esp_wifi_rx_callbacks+1;','esp_wifi_rx_callbacks=1;'),('esp_wifi_rx_callbacks=esp_wifi_rx_callbacks-1;','esp_wifi_rx_callbacks=0;')],105),
 ('vendor-TX-masked','esp_wifi_transmit',[('let r=esp32_call32(','let held=esp32_irq_save();let r=esp32_call32('),('ps=esp32_irq_save();if !r','esp32_irq_restore(held);ps=esp32_irq_save();if !r')],101),
 ('vendor-free-masked','esp_wifi_rx_callback',[('if eb {esp32_call32(','if eb {let held=esp32_irq_save();esp32_call32('),('eb,0,0,0,0,0,0,0);}','eb,0,0,0,0,0,0,0);esp32_irq_restore(held);}')],102),
 ('lifecycle-packet-guards-missing','esp_wifi_packets_active',[('return esp_wifi_tx_active || esp_wifi_rx_reading || esp_wifi_rx_callbacks || esp_wifi_rx_busy;','return 0;')],101),
 ('post-stop-quiescence-missing','esp_wifi_stop_inner',[('if busy {return -16;}','')],107),
 ('callback-ignores-closing','esp_wifi_rx_callback',[('!esp_wifi_lifecycle_busy && ','')],107),
 ('producer-reservation-missing','esp_wifi_rx_callback',[(' && !esp_wifi_rx_busy','')],105),
 ('TX-stat-commit-unmasked','esp_wifi_transmit',[('ps=esp32_irq_save();if !r','ps=esp32_irq_save();if wc_mode==11 {esp32_irq_restore(ps);}if !r')],111),
 ('RX-consume-commit-unmasked','esp_wifi_receive',[('ps=esp32_irq_save();esp_wifi_rx_head=','ps=esp32_irq_save();if wc_mode==12 {esp32_irq_restore(ps);}esp_wifi_rx_head=')],112),
 ('RX-produce-commit-unmasked','esp_wifi_rx_callback',[('ps=esp32_irq_save();let before=','ps=esp32_irq_save();if wc_mode==13 {esp32_irq_restore(ps);}let before=')],113),
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
 fixture=tree/'tests/esp32/wifi-ownership-preempt.flex';fixture.write_text(h['once'](fixture.read_text(),'global wc_expect_hooks=0;','global wc_expect_hooks=1;'))
 out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
 with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
 text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
 if not mutation:ok=ok and 'hooks=000000000000000a masked=0000000000000008' in text
 else:ok=ok and f'WIFI OWNERSHIP FAIL {expected:016x}' in text and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
 row=dict(name=name,expected_behavior=bool(ok),expected_failure=expected if mutation else None,exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,forced_windows=10,masked_windows=8,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected Wi-Fi packet transactions pass; all seventeen isolated defects detected')
