#!/usr/bin/env python3
"""Primary-header modem power operand checks and native ownership controls.

Uses call traces and the existing stock QEMU; no peripheral or CPU model changes.
"""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','driver','qemu','prefix','original-prefix','s3-peer','original-peer','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest={}
 for n in ['s3-radio-power-checks.flex','s3-wifi-power-guards.flex','wifi-phy-admission.flex']:manifest.update(h['copy_closure'](ROOT/'tests/esp32'/n,base))
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');records=[]
 def run(cmd,log,timeout=45):
  q=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,capture_output=True,timeout=timeout);log.write_bytes(q.stdout+q.stderr);return q
 power_on='esp_radio_modem_power_on';power_off='esp_radio_modem_power_off'
 pd='esp32_store32(0x60008090,esp32_load32(0x60008090)&~(1<<17));'
 iso='esp32_store32(0x60008094,esp32_load32(0x60008094)|(1<<28));'
 down='esp32_store32(0x60008090,esp32_load32(0x60008090)|(1<<17));'
 operands=[
  ('original-PWC-address',power_on,pd,pd.replace('0x60008090','0x3ff48084')),
  ('wrong-power-up-bit',power_on,'&~(1<<17)','&~(1<<18)'),
  ('power-up-unmasked',power_on,'let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);'),
  ('missing-clock-init',power_on,'esp_radio_clocks_init();',''),
  ('power-before-clocks',power_on,'esp_radio_clocks_init();'+pd,pd+'esp_radio_clocks_init();'),
  ('wrong-delay',power_on,'esp32_call32(delay,10,','esp32_call32(delay,9,'),
  ('wrong-delay-address',power_on,'esp32_call32(delay,10,','esp32_call32(delay+4,10,'),
  ('missing-delay',power_on,'esp32_call32(delay,10,0,0,0,0,0,0,0);',''),
  ('incomplete-reset-assert',power_on,'before|0x2a1f','before|4'),
  ('incomplete-reset-release',power_on,'before&~0x2a1f','before&~4'),
  ('stale-reset-release-read',power_on,'\n    before=esp32_load32(0x60026018);','\n    '),
  ('wrong-unisolate-bit',power_on,'&~(1<<28)','&~(1<<29)'),
  ('power-up-PS-lost',power_on,'esp32_irq_restore(ps);return 0;','esp32_irq_restore(0);return 0;'),
  ('delay-pointer-truncated',power_on,' || delay>>32',''),
  ('power-down-before-isolation',power_off,iso+'\n    '+down,down+'\n    '+iso),
  ('wrong-isolate-bit',power_off,'|(1<<28)','|(1<<29)'),
  ('wrong-power-down-bit',power_off,'|(1<<17)','|(1<<18)'),
  ('power-down-unmasked',power_off,'let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);'),
  ('power-down-PS-lost',power_off,'esp32_irq_restore(ps);return 0;','esp32_irq_restore(0);return 0;'),
 ]
 for mutation in [None]+operands:
  name=mutation[0] if mutation else 'operands-protected';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,fn,before,after=mutation;h['change'](tree/'lib/platform/esp32s3-radio-power.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'checks';q=run([a.compiler,tree/'tests/esp32/s3-radio-power-checks.flex','-o',exe],w/name/'compile.log');assert q.returncode==0,(name,q.stdout,q.stderr)
  log=w/name/'execution.log';q=run([exe,a.vectors],log,10)
  if mutation:assert 1<=q.returncode<=4 and b'S3 power operand mismatch' in q.stderr,(name,q.returncode,q.stdout,q.stderr)
  else:assert q.returncode==0 and q.stdout==b'S3 power transaction: 2304 checks\n',(q.returncode,q.stdout,q.stderr)
  records.append(dict(name=name,expected_behavior=True,kind='operand trace',log_sha256=sha(log)))
 guards=[
  ('active-PHY-admitted','esp32-wifi-core.flex','esp_wifi_station_init',' || esp_radio_phy_refs','',0),
  ('active-PHY-clock-admitted','esp32-wifi-core.flex','esp_wifi_station_init',' || esp_radio_phy_clock_refs','',1),
  ('prepare-owner-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_prepare','esp_radio_owner!=1 || ','',100),
  ('prepare-ADC-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_prepare','esp_adc_busy || ','',102),
  ('prepare-PHY-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_prepare','esp_radio_phy_refs || ','',103),
  ('prepare-clock-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_prepare','esp_radio_phy_clock_refs || ','',104),
  ('release-owner-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_release','esp_radio_owner!=1 || ','',200),
  ('release-ADC-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_release',' || esp_adc_busy','',202),
  ('release-PHY-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_release','esp_radio_phy_refs || ','',203),
  ('release-clock-guard-missing','esp32s3-wifi.flex','esp_wifi_platform_release','esp_radio_phy_clock_refs || ','',204),
  ('native-delay-ABI-wrong','esp32s3-radio-power.flex','esp_radio_modem_power_on','esp32_call32(delay,10,','esp32_call32(delay,9,',401),
 ]
 for original in [False,True]:
  for mutation in [None]+(guards[:2] if original else guards):
   name=('original-' if original else 's3-')+(mutation[0] if mutation else 'guards-protected');tree=w/name/'source';shutil.copytree(base,tree)
   if mutation:
    _,module,fn,before,after,code=mutation;h['change'](tree/'lib/platform'/module,fn,lambda body:h['once'](body,before,after))
   out=w/name/'run';log=w/name/'execution.log'
   cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.original_prefix if original else a.prefix,'--extra',a.original_peer if original else a.s3_peer,'--xip','yes','--source',tree/'tests/esp32'/('wifi-phy-admission.flex' if original else 's3-wifi-power-guards.flex'),'--work',out]
   if not original:cmd+=['--chip','esp32s3']
   q=run(cmd,log);text=log.read_text()
   if mutation:
    expected=('WIFI PHY ADMISSION FAIL '+f'{0:016x}{code:016x}') if code<2 else 'S3 POWER GUARD FAIL '+f'{code:016x}'
    assert q.returncode==1 and expected in text,(name,q.returncode,text[-1500:]);assert 'SHUTDOWN' in (out/'qmp-failure.log').read_text()
   else:assert q.returncode==0 and ('PASS: original Wi-Fi96' if original else 'PASS: S3 power admission/release') in text,(name,q.returncode,text[-1500:])
   records.append(dict(name=name,expected_behavior=True,kind='native firmware',log_sha256=sha(log)));print(name,flush=True)
 assert all(sha(ROOT/n)==digest for n,digest in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,operand_checks=2304,operand_defects=len(operands),firmware_defects=len(guards)+2,native_positive_boots=2,cases=records,source_sha256=manifest,
  tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.s3_peer,a.original_peer,__file__]},vectors_sha256=sha(a.vectors),physical_hardware=False,peripheral_model=False,emulator_changes=False),indent=2)+'\n')
 print('PASS:2304 power trace checks,19 operand defects,13 firmware defects,both chips borrowed PHY guards')
if __name__=='__main__':main()
