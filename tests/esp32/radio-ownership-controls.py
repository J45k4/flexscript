#!/usr/bin/env python3
"""Execute independent S3 radio-ownership defects in emitted machine code."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['compiler','driver','qemu','prefix','work']:p.add_argument('--'+name,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/s3-radio-ownership.flex',source)
 env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp');records=[]
 defs=[
  ('original-source-count','esp32s3-radio-lifecycle.flex','return 99;','return 69;',1),
  ('original-route-base','esp32s3-radio-lifecycle.flex','0x600c2000','0x3ff00104',1),
  ('capacity-not-preflighted','esp32s3-irq.flex','if esp_irq_count+additional>32 {esp32_irq_restore(ps);return -12;}','',21),
  ('foreign-handler-admitted','esp32-radio-lifecycle-core.flex','if existing && (!load64(esp_radio_irq_routes+source*16) || existing!=handler) {esp32_irq_restore(ps);return -16;}','',7),
  ('saved-route-not-restored','esp32-radio-lifecycle-core.flex','esp32_store32(esp_radio_route(source),load64(p+8));','',16),
  ('thread-semaphore-stale','esp32-radio-lifecycle-core.flex','store64(t+568,0);','',15),
  ('domain-objects-leaked','esp32-radio-lifecycle-core.flex','r=esp_sdk_heap_release_owner(esp_radio_owner);','r=0;',15),
  ('software-handler-not-cleared','esp32-radio-lifecycle-core.flex','if esp_radio_soft_owned && esp_irq_soft_handler==handler','if 0 && esp_radio_soft_owned && esp_irq_soft_handler==handler',24),
 ]
 for case in [None]+defs:
  name=case[0] if case else 'protected';tree=w/name/'source';shutil.copytree(source,tree)
  if case:
   _,file,old,new,code=case;path=tree/'lib/platform'/file;text=path.read_text();assert text.count(old)==1,(name,text.count(old));path.write_text(text.replace(old,new))
  cmd=[a.driver,'--compiler',a.compiler,'--work',w/name/'run','--qemu',a.qemu,'--prefix',a.prefix,'--source',tree/'tests/esp32/s3-radio-ownership.flex','--chip','esp32s3','--profile','esp32s3-sdk-elf']
  log=w/name/'execution.log'
  with log.open('w') as output:q=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=45)
  text=log.read_text();marker=f'OWNERSHIP FAIL {case[4]:016x}' if case else 'checks=0000000000000059'
  assert q.returncode==(1 if case else 0) and marker in text,(name,q.returncode,text[-2500:])
  if case:assert 'main returned zero' in text and 'SHUTDOWN' in text
  records.append(dict(name=name,detected=True,exit_code=q.returncode,marker=marker,log_sha256=sha(log)))
  print(name,'passed',flush=True)
 report=dict(pass_all=True,checks=89,cycles=8,controls=records,source_sha256=manifest,compiler_sha256=sha(a.compiler),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_changes=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
