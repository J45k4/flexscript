#!/usr/bin/env python3
"""Real S3 task/IRQ PHY interleavings, typed C witnesses and copied defects."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for n in ['compiler','driver','qemu','prefix','peer','work']:p.add_argument('--'+n,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/s3-phy-preempt.flex',base)
 probes=[('esp_radio_phy_buffers_init','let cal=','ph_gate(1);let cal='),('esp_radio_phy_enable','esp32_call32(esp32_external("phy_init_param_set")','ph_gate(2);esp32_call32(esp32_external("phy_init_param_set")'),('esp_radio_phy_disable','esp32_call32(esp32_external("phy_dig_reg_backup"),1','ph_gate(3);esp32_call32(esp32_external("phy_dig_reg_backup"),1'),('esp_radio_cb_phy_on','if !result {esp32_call32(','if !result {ph_gate(4);esp32_call32('),('esp_radio_cb_phy_off','esp32_call32(esp32_external("phy_wifi_enable_set")','ph_gate(5);esp32_call32(esp32_external("phy_wifi_enable_set")'),('esp_radio_phy_release_buffers','esp_sdk_free(esp_radio_phy_cal);','ph_gate(6);esp_sdk_free(esp_radio_phy_cal);')]
 changes=[(fn+'-unmasked',fn,'let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);') for fn,_,_ in probes]
 changes +=[
 ('cal-rollback-leak','esp_radio_phy_buffers_init','esp_sdk_free(cal);',''),('data-rollback-leak','esp_radio_phy_buffers_init','esp_sdk_free(data);',''),('digital-rollback-leak','esp_radio_phy_buffers_init','esp_sdk_free(digital);',''),
 ('digital-buffer-too-small','esp_radio_phy_buffers_init','esp_sdk_calloc(1,84)','esp_sdk_calloc(1,80)'),('bad-init-byte','esp_radio_phy_buffers_init','store8(data+2,80)','store8(data+2,79)'),
 ('missing-USB-PLL','esp_radio_phy_enable','esp32_call32(esp32_external("phy_bbpll_en_usb"),1,0,0,0,0,0,0,0);',''),('missing-digital-restore','esp_radio_phy_enable','esp32_call32(esp32_external("phy_dig_reg_backup"),0,esp_radio_phy_digital,0,0,0,0,0,0);',''),
 ('missing-digital-save','esp_radio_phy_disable','esp32_call32(esp32_external("phy_dig_reg_backup"),1,esp_radio_phy_digital,0,0,0,0,0,0);',''),('missing-temperature-stop','esp_radio_phy_disable','esp32_call32(esp32_external("phy_xpd_tsens"),0,0,0,0,0,0,0,0);',''),
 ('lost-backup-valid','esp_radio_phy_disable','esp_radio_phy_digital_valid=1;',''),('clock-reference-leak','esp_radio_phy_disable','esp_radio_phy_clock(0);',''),('calibration-unrecorded','esp_radio_phy_enable','esp_radio_phy_calibrated=1;',''),('digital-pointer-not-cleared','esp_radio_phy_release_buffers','esp_radio_phy_digital=0;',''),
 ('wifi-RX-not-enabled','esp_radio_cb_phy_on','esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);',''),('wifi-RX-not-disabled','esp_radio_cb_phy_off','esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);',''),
 ('wrong-clock-bit','esp_radio_phy_clock','|0x78078f','|0x78078e'),('clobbered-clock-bits','esp_radio_phy_clock','esp32_load32(esp32_external("phy_clock_register"))|0x78078f','0x78078f'),
 ('ADC-claim-not-preflighted','esp_radio_phy_enable','if esp_adc_busy {esp32_irq_restore(ps);return -16;}',''),('clock-overflow-not-preflighted','esp_radio_phy_enable',' || esp_radio_phy_clock_refs==9223372036854775807',''),
 ]
 rows=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'canonical';tree=w/name/'source';shutil.copytree(base,tree)
  def module(fn):return tree/'lib/platform'/('esp32s3-radio-os.flex' if fn in ['esp_radio_cb_phy_on','esp_radio_cb_phy_off'] else 'esp32s3-radio-hardware.flex' if fn in ['esp_radio_phy_clock','esp_radio_clocks_init'] else 'esp32s3-radio-phy.flex')
  for fn,before,after in probes:h['change'](module(fn),fn,lambda t:h['once'](t,before,after))
  for fn in ['esp_radio_clocks_init','esp_radio_phy_clock']:h['change'](module(fn),fn,lambda t:t.replace('0x60026014','esp32_external("phy_clock_register")'))
  if mutation:
   _,fn,before,after=mutation;h['change'](module(fn),fn,lambda t:h['once'](t,before,after))
  src=tree/'tests/esp32/s3-phy-preempt.flex';src.write_text(src.read_text().replace('global ph_expect_hooks=0;','global ph_expect_hooks=1;').replace('global ph_clock_override=0;','global ph_clock_override=1;'))
  report=w/(name+'.json');args=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.peer,'--source',src,'--chip','esp32s3','--xip','yes','--work',w/name/'run','--report',report]
  q=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=30);text=(q.stdout+q.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text)
  if mutation:assert q.returncode==1 and 'PHY PREEMPT FAIL' in text and 'main returned zero' in text and 'SHUTDOWN' in text,(name,text[-1800:])
  else:assert q.returncode==0 and 'hooks=0000000000000006 masked=0000000000000006' in text,(name,text[-1800:])
  rows.append(dict(name=name,detected=bool(mutation),report=str(report) if not mutation else None,log_sha256=sha(w/(name+'.log'))));print(name,'detected' if mutation else 'passed',flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,cases=rows,forced_windows=6,clock_operand_probe=True,physical_clock_gating=False,source_sha256=manifest,compiler_sha256=sha(a.compiler),peer_sha256=sha(a.peer),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_implementation_changes=False),indent=2)+'\n')
if __name__=='__main__':main()
