#!/usr/bin/env python3
"""S3 station ABI/lifecycle and IRQ-capacity firmware checks on stock QEMU."""
import argparse, hashlib, json, os, runpy, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','driver','qemu','prefix','peer','original-prefix','original-peer','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source'
 manifest=h['copy_closure'](ROOT/'tests/esp32/s3-wifi-lifecycle-failures.flex',source)
 manifest.update(h['copy_closure'](ROOT/'tests/esp32/wifi-irq-capacity.flex',source))
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');records=[]
 defects=[
  ('crypto-tail-truncated','esp32-wifi-core.flex','esp_wifi_build_init_config','while i<52','while i<48',30),
  ('init-tail-not-cleared','esp32-wifi-core.flex','esp_wifi_build_init_config','while zero<160','while zero<156',30),
  ('tx-hetb-misplaced','esp32-wifi-core.flex','esp_wifi_build_init_config','config+144,3','config+140,3',30),
  ('management-buffer-wrong','esp32-wifi-core.flex','esp_wifi_build_init_config','config+80,5','config+80,4',30),
  ('nvs-flag-missing','esp32-wifi-core.flex','esp_wifi_build_init_config','if esp_radio_nvs_table','if 0',30),
  ('station-auth-misplaced','esp32-wifi-core.flex','esp_wifi_station_config','config+120,auth','config+124,auth',32),
  ('wpa3-pmf-not-required','esp32-wifi-core.flex','esp_wifi_station_config','if auth==6','if 0',32),
  ('s3-capacity-preflight-missing','esp32s3-wifi.flex','esp_wifi_platform_prepare','result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));','result=0;',35),
  ('s3-only-one-slot-reserved','esp32s3-wifi.flex','esp_wifi_platform_prepare','result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));','result=esp_irq_reserve(1);',36),
  ('s3-power-ownership-not-published','esp32s3-wifi.flex','esp_wifi_platform_prepare','esp_wifi_power_owned=1;','esp_wifi_power_owned=0;',2),
  ('s3-power-ownership-not-released','esp32s3-wifi.flex','esp_wifi_platform_release','esp_wifi_power_owned=0;','esp_wifi_power_owned=1;',2),
 ]
 for defect in [None]+defects:
  name=defect[0] if defect else 'protected';tree=w/name/'source';shutil.copytree(source,tree)
  if defect:
   _,module,fn,before,after,code=defect
   h['change'](tree/'lib/platform'/module,fn,lambda body:h['once'](body,before,after))
  out=w/name/'run';log=w/name/'execution.log'
  cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.peer,'--chip','esp32s3','--xip','yes','--source',tree/'tests/esp32/s3-wifi-lifecycle-failures.flex','--work',out]
  with log.open('w') as stream:r=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
  text=log.read_text();ok=r.returncode==(1 if defect else 0)
  if defect:
   trace=out/'qmp-failure.log';ok=ok and f'S3 WIFI FAIL {code:016x}' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
  else:ok=ok and 'PASS: S3 typed config/canaries' in text
  records.append(dict(name=name,expected_behavior=bool(ok),log=str(log),log_sha256=sha(log)))
  print(json.dumps(records[-1]),flush=True);assert ok,(name,text[-1600:])
 # The original chip needs one free slot; its register map is checked separately.
 for broken in [False,True]:
  name='original-capacity'+('-defect' if broken else '');tree=w/name/'source';shutil.copytree(source,tree)
  if broken:h['change'](tree/'lib/platform/esp32-wifi.flex','esp_wifi_platform_prepare',lambda body:h['once'](body,'let result=esp_irq_reserve(!esp_irq_handler(0));','let result=0;'))
  out=w/name/'run';log=w/name/'execution.log'
  cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.original_prefix,'--extra',a.original_peer,'--xip','yes','--source',tree/'tests/esp32/wifi-irq-capacity.flex','--work',out]
  with log.open('w') as stream:r=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
  text=log.read_text();ok=r.returncode==(1 if broken else 0) and ('WIFI CAPACITY FAIL' if broken else 'PASS: original Wi-Fi IRQ-capacity') in text
  if broken:assert 'SHUTDOWN' in (out/'qmp-failure.log').read_text()
  records.append(dict(name=name,expected_behavior=bool(ok),log=str(log),log_sha256=sha(log)));print(json.dumps(records[-1]),flush=True);assert ok,(name,text[-1600:])
 report=dict(pass_all=True,cases=records,defects=len(defects)+1,source_sha256=manifest,
  tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.peer,a.original_peer,__file__]},physical_hardware=False,emulator_changes=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS: typed S3 lifecycle/config, both chips IRQ capacity, all12 isolated defects')

if __name__=='__main__':main()
