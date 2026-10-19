#!/usr/bin/env python3
"""Execute protected native PHY transactions and isolated defects on stock QEMU.

The clock-mask observer redirects only the clock register operand in copied
firmware to an independent C word. It is an operand probe, not a peripheral
model; production firmware and emulator sources are unchanged.
"""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for key in ['compiler','driver','qemu','prefix','c-object','work']:p.add_argument('--'+key,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose fresh work directory')
source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/phy-preempt.flex',source)
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
probes=[('esp_radio_phy_buffers_init','    let cal=','    ph_gate(1);let cal='),('esp_radio_phy_enable','            esp32_call32(esp32_external("phy_init_param_set")','            ph_gate(2);esp32_call32(esp32_external("phy_init_param_set")'),('esp_radio_phy_disable','if !esp_radio_phy_refs {esp32_call32(','if !esp_radio_phy_refs {ph_gate(3);esp32_call32('),('esp_radio_cb_phy_on','if !r {esp32_call32(','if !r {ph_gate(4);esp32_call32('),('esp_radio_cb_phy_off','esp32_call32(esp32_external("phy_wifi_enable_set")','ph_gate(5);esp32_call32(esp32_external("phy_wifi_enable_set")'),('esp_radio_phy_release_buffers','esp_sdk_free(esp_radio_phy_cal);','ph_gate(6);esp_sdk_free(esp_radio_phy_cal);')]
mutations=[
 ('constructor-unmasked','esp_radio_phy_buffers_init','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',301),
 ('enable-unmasked','esp_radio_phy_enable','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',102),
 ('disable-unmasked','esp_radio_phy_disable','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',302),
 ('wifi-enable-unmasked','esp_radio_cb_phy_on','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',104),
 ('wifi-disable-unmasked','esp_radio_cb_phy_off','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',104),
 ('release-unmasked','esp_radio_phy_release_buffers','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);',106),
 ('rollback-cal-leaked','esp_radio_phy_buffers_init','esp_sdk_free(cal);','',210),
 ('rollback-data-leaked','esp_radio_phy_buffers_init','esp_sdk_free(data);','',210),
 ('failure-clock-leaked','esp_radio_phy_enable','if r {esp32_irq_restore(ps);return r;}','if r {esp_radio_phy_clock(1);esp32_irq_restore(ps);return r;}',210),
 ('clock-reference-leaked','esp_radio_phy_disable','esp_radio_phy_clock(0);','',302),
 ('calibration-unrecorded','esp_radio_phy_enable','esp_radio_phy_calibrated=1;','',102),
 ('calibration-not-reset','esp_radio_phy_release_buffers','esp_radio_phy_calibrated=0;','',302),
 ('wifi-RX-not-enabled','esp_radio_cb_phy_on','esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);','',105),
 ('wifi-RX-not-disabled','esp_radio_cb_phy_off','esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);','',104),
 ('clock-mask-bit-missing','esp_radio_phy_clock','value=value|0x3c9;','value=value|0x3c1;',102),
 ('clock-unrelated-bits-clobbered','esp_radio_phy_clock','value=value|0x3c9;','value=0x3c9;',302),
]
def sha(p):
 with open(p,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
records=[]
for mutation in [None]+mutations:
    name=mutation[0] if mutation else 'protected';tree=w/name/'source';shutil.copytree(source,tree);module=tree/'lib/platform/esp32-radio-os.flex'
    for fn,before,after in probes:h['change'](module,fn,lambda text:h['once'](text,before,after))
    def operand(text):
        assert text.count('0x3ff000cc')==2
        return text.replace('0x3ff000cc','esp32_external("phy_clock_register")')
    h['change'](module,'esp_radio_phy_clock',operand)
    if mutation:
        _,fn,before,after,expected=mutation;h['change'](module,fn,lambda text:h['once'](text,before,after))
    fixture=tree/'tests/esp32/phy-preempt.flex';fixture.write_text(h['once'](h['once'](fixture.read_text(),'global ph_expect_hooks=0;','global ph_expect_hooks=1;'),'global ph_clock_override=0;','global ph_clock_override=1;'))
    out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.c_object,'--xip','yes','--work',str(out),'--source',str(fixture)]
    with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
    text=log.read_text();trace=out/'qmp-failure.log';ok=r.returncode==(1 if mutation else 0)
    if not mutation:ok=ok and 'hooks=0000000000000006 masked=0000000000000006' in text
    else:ok=ok and f'PHY PREEMPT FAIL {expected:016x}' in text and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
    row=dict(name=name,expected_behavior=bool(ok),expected_failure=expected if mutation else None,exit_code=r.returncode,log=str(log),log_sha256=sha(log));records.append(row);print(json.dumps(row),flush=True)
    (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,forced_windows=6,clock_operand_probe=True,physical_clock_gating=False,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.c_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
    if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Protected PHY transactions pass; all sixteen isolated defects detected')
