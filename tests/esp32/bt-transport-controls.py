#!/usr/bin/env python3
"""Independent C/CPU preemption controls for native Bluetooth ownership."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/bt-transport-preempt.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[('esp_bt_transport_init','    let rx=','    bt_gate(1);let rx='),('esp_bt_hci_command','esp_bt_cmd_busy=1;','bt_gate(2);esp_bt_cmd_busy=1;'),('esp_bt_recv','    esp_bt_receive_sequence=','    bt_gate(3);esp_bt_receive_sequence='),('esp_bt_transport_release','esp_sdk_free(esp_bt_event_ring);','esp_sdk_free(esp_bt_event_ring);bt_gate(4);'),('esp_bt_hci_command','esp_bt_cmd_busy=0;esp32_irq_restore(ps);return result;','esp_bt_cmd_busy=0;esp32_irq_restore(ps);bt_gate(7);return result;')]
mutations=[
 ('tx-active-not-exclusive','esp_bt_tx_claim','esp_bt_tx_active || esp_bt_tx_inflight','esp_bt_tx_inflight',105),
 ('ready-releases-C-lease','esp_bt_send_ready','esp_bt_tx_inflight=0;','esp_bt_tx_inflight=0;esp_bt_tx_active=0;',106),
 ('release-ignores-C-lease','esp_bt_transport_release','esp_bt_tx_active ||','',('trap',5,0)),
 ('controller-stop-ignores-C-lease','esp_bt_controller_deinit','esp_bt_tx_active ||','',105),
 ('command-admission-unmasked','esp_bt_hci_command','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',102),
 ('constructor-unmasked','esp_bt_transport_init','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',101),
 ('receive-lifetime-unmasked','esp_bt_recv','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',('trap',3,16)),
 ('release-publication-unmasked','esp_bt_transport_release','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',104),
 ('credit-recheck-missing','esp_bt_tx_submit','if command && !esp_bt_cmd_credits {esp_bt_tx_active=0;esp32_irq_restore(ps);return -11;}','',108),
 ('unsubmitted-reply-captured','esp_bt_recv','opcode==esp_bt_cmd_opcode && esp_bt_cmd_pending','opcode==esp_bt_cmd_opcode',108),
 ('timeout-quarantine-missing','esp_bt_command_timeout','if esp_bt_cmd_pending {esp_bt_cmd_stale=1;}','esp_bt_cmd_pending=0;esp_bt_cmd_stale=0;',210),
 ('late-quarantine-never-clears','esp_bt_recv','if esp_bt_cmd_stale {','if 0 {',212),
 ('pending-command-overwritten','esp_bt_hci_command','esp_bt_cmd_pending ||','',211),
 ('HNC-status-changes-credits','esp_bt_recv','if opcode!=0x0c35 {esp_bt_cmd_credits=load8(a+4);}','esp_bt_cmd_credits=load8(a+4);',217),
 ('status-borrowed-after-unlock','esp_bt_hci_command','return result;','return load8(esp_bt_rx+6);',107),
 ('raw-teardown-owner-missing','esp_bt_controller_deinit','if !esp_bt_control_task {esp_bt_control_task=esp_sdk_current;}','',219)]
records=[]
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
for mutation in [None]+mutations:
    name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree);module=tree/'lib/platform/esp32-bluetooth.flex'
    for fn,before,after in probes:h['change'](module,fn,lambda text:h['once'](text,before,after))
    if mutation:
        _,fn,before,after,expected=mutation
        h['change'](module,fn,lambda text:h['once'](text,before,after))
    fixture=tree/'tests/esp32/bt-transport-preempt.flex';fixture.write_text(h['once'](fixture.read_text(),'global bt_expect_hooks=0;','global bt_expect_hooks=1;'))
    out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
    with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
    text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
    if not mutation:ok=ok and 'hooks=0000000000000005 masked=0000000000000004' in text
    elif isinstance(expected,tuple):
        cases=re.findall(r'BT CASE ([0-9a-f]{16})',text);ok=ok and trace.exists() and '0x54524150' in trace.read_text() and f'EXCVADDR={expected[2]:08x}' in trace.read_text() and cases and int(cases[-1],16)==expected[1]
    else:ok=ok and f'BT CONCURRENT FAIL {expected:016x}' in text and 'main returned zero' in text
    if mutation:ok=ok and trace.exists() and 'SHUTDOWN' in trace.read_text()
    row=dict(name=name,expected_behavior=bool(ok),expected=expected if mutation else 'five windows/four masked',exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
    (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
    if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected transaction windows pass; all sixteen isolated ownership/lifetime/response defects detected')
