#!/usr/bin/env python3
"""S3 typed-C OSI-v9 contract and transactional publication defect boots."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for n in ['compiler','driver','qemu','prefix','peer','work']:p.add_argument('--'+n,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/s3-osi.flex',base)
 changes=[
 ('early-ready-pointer','esp32-radio-os-core.flex','esp_radio_os_init','esp_radio_os_build(prepared);','esp_radio_osi=esp32_external("g_wifi_osi_funcs");esp_radio_os_build(prepared);',124),
 ('vendor-table-mutated-before-ready','esp32-radio-os-core.flex','esp_radio_os_init','esp_radio_os_build(prepared);','esp_radio_os_build(esp32_external("g_wifi_osi_funcs"));',124),
 ('scratch-leak','esp32-radio-os-core.flex','esp_radio_os_init','if result {esp_sdk_free(prepared);','if result {',124),
 ('new-owner-leak','esp32-radio-os-core.flex','esp_radio_os_init','if claimed && esp_radio_owner==1 {esp_radio_resources_end(esp32_callback(esp_radio_irq));}','',124),
 ('existing-owner-lost','esp32-radio-os-core.flex','esp_radio_os_init','if claimed && esp_radio_owner==1','if esp_radio_owner==1',126),
 ('truncated-copy','esp32-radio-os-core.flex','esp_radio_os_init','while i<bytes','while i<bytes-4',130),
 ('old-NVS-offset','esp32-radio-os-core.flex','esp_radio_nvs_patch','+esp_radio_nvs_offset()+','+276+',128),
 ('wrong-ABI-version','esp32s3-radio-os.flex','esp_radio_os_build','store32(table+0,9)','store32(table+0,8)',130),
 ('wrong-magic','esp32s3-radio-os.flex','esp_radio_os_build','3735928495','3735928494',130),
 ('wrong-time-callback','esp32s3-radio-os.flex','esp_radio_os_build','esp32_callback32(esp_radio_cb_get_time)','esp32_callback32(esp_radio_cb_random)',130),
 ('wrong-queue-callback','esp32s3-radio-os.flex','esp_radio_os_build','esp32_callback32(esp_radio_cb_recv)','esp32_callback32(esp_radio_cb_send)',130),
 ('wrong-slowclk-shift','esp32s3-radio-hardware.flex','esp_radio_cb_slowclk_cal','>>7','>>6',130),
 ]
 cases=[]
 for mutation in [None]+changes:
  name=mutation[0] if mutation else 'canonical';tree=w/name/'source';shutil.copytree(base,tree)
  if mutation:
   _,module,fn,before,after,expected=mutation;h['change'](tree/'lib/platform'/module,fn,lambda t:h['once'](t,before,after))
  out=w/name/'run';report=w/(name+'.json');args=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.prefix,'--extra',a.peer,'--source',tree/'tests/esp32/s3-osi.flex','--chip','esp32s3','--xip','yes','--work',out,'--report',report]
  q=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=30);text=(q.stdout+q.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text)
  if mutation:assert q.returncode==1 and f'S3 OSI FAIL {expected:016x}' in text and '0x444f4e45' in text and 'SHUTDOWN' in text,(name,text[-2200:])
  else:assert q.returncode==0 and 'PASS: S3 vendor v9 all120' in text,(name,text[-2200:])
  cases.append(dict(name=name,detected=bool(mutation),report=str(report) if not mutation else None,log_sha256=sha(w/(name+'.log'))));print(name,'detected' if mutation else 'passed',flush=True)
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),peer_sha256=sha(a.peer),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_implementation_changes=False),indent=2)+'\n')
if __name__=='__main__':main()
