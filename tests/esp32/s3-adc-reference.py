#!/usr/bin/env python3
"""S3 ADC primary-header register expectations and isolated driver defects.

The operation spies supply canned samples and check writes; this adds no
instruction, peripheral or timing model to a firmware emulator.
"""
import argparse,hashlib,json,os,re,runpy,shutil,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):
 with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for key in ['compiler','reference','work']:p.add_argument('--'+key,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists(),'choose a fresh directory'
 env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp');official=Path(a.reference).resolve();oracle=ROOT/'tests/esp32/s3-adc-oracle'
 catalog=json.loads((oracle/'sources.json').read_text());include=w/'include';(include/'soc').mkdir(parents=True,exist_ok=True)
 for name,row in catalog.items():
  assert sha(official/name)==row['sha256'],name
  if name.endswith('.h'):shutil.copyfile(official/name,include/name)
 (include/'soc/soc.h').write_text('#pragma once\n#include <stdint.h>\n#include "reg_base.h"\n#define BIT(n) (UINT32_C(1) << (n))\n')
 text=(official/'adc_ll.h').read_text();end=text.index('} adc_ll_rtc_output_data_t;')+len('} adc_ll_rtc_output_data_t;');start=text.rfind('typedef struct {',0,end);assert start>=0
 (include/'adc-result-layout.h').write_text('/* From ESP-IDFv5.5.1 adc_ll.h; Espressif Systems; SPDX-License-Identifier: Apache-2.0 */\n'+text[start:end]+'\n')
 def run(args,label,expected=0):
  q=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=45);(w/(label+'.stdout')).write_bytes(q.stdout);(w/(label+'.stderr')).write_bytes(q.stderr)
  assert q.returncode==expected,(label,q.returncode,q.stderr[-1500:]);return q
 run(['cc','-std=gnu11','-Wall','-Wextra','-Werror','-I',include,oracle/'reference.c','-o',w/'reference-bin'],'C-build')
 q=run([w/'reference-bin'],'C-reference');assert len(q.stdout)==672 and struct.unpack_from('<2Q',q.stdout)==(0x5333414443000001,82);reference=w/'reference.bin';reference.write_bytes(q.stdout)
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'production-source';manifest=h['copy_closure'](ROOT/'tests/esp32/s3-adc-checks.flex',source)
 defs=[
  ('radio-owner-ignored','s3a_conflict','(unit==2 && (esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs))','0',32),
  ('PHY-owner-ignored','s3a_conflict','esp_radio_phy_refs || ','',300),
  ('PHY-clock-owner-ignored','s3a_conflict',' || esp_radio_phy_clock_refs','',300),
  ('conversion-owner-ignored','s3a_conflict','return esp_adc_busy ||','return 0 ||',91),
  ('RTC-IRQ-user-ignored','s3a_conflict','(esp32_load32(0x60008040)&irq) || ','',300),
  ('ULP-timer-user-ignored','s3a_conflict','(esp32_load32(0x600080fc)&(1<<31)) || ','',300),
  ('ULP-start-user-ignored','s3a_conflict','(esp32_load32(0x60008100)&(3<<30)) || ','',300),
  ('hardware-controller-ignored','s3a_conflict','|| s3a_controller_busy(unit)','|| 0',300),
  ('init-not-masked','esp_adc_init','let ps=esp32_irq_save();','let ps=0;',90),
  ('read-not-masked','esp_adc_read','let ps=esp32_irq_save();','let ps=0;',90),
  ('read-loses-PS','esp_adc_read','esp32_irq_restore(ps);return result;','esp32_irq_restore(0);return result;',7),
  ('shared-state-not-restored','esp_adc_read','s3a_restore();','s3a_saved_count=0;',200),
  ('conversion-owner-leaked','esp_adc_read','s3a_restore();esp_adc_busy=0;','s3a_restore();',222),
  ('wrong-ADC2-stride','esp_adc_read','let delta=(unit-1)*36;','let delta=(unit-1)*32;',7),
  ('wrong-RTC-arbiter-priority','esp_adc_read','(2<<8)|8','(1<<8)|8',106),
  ('invalid-arbiter-sample-returned','esp_adc_read','if unit==2 && (raw&0xc000)','if 0 && unit==2 && (raw&0xc000)',12),
  ('held-pad-configured','esp_adc_init','|| s3a_pad_held(pin)','|| 0',30),
  ('held-pad-deinitialized','esp_adc_deinit','if s3a_pad_held(pin)','if 0',300),
  ('digital-input-left-enabled','esp_adc_init','esp_reg_update(0x60009004+pin*4,1<<9,0);','',6),
  ('RTC-output-disable-wrong-bit','esp_adc_init','1<<(pin+10)','1<<(pin+9)',6),
  ('RTC-input-left-enabled','esp_adc_init','|(1<<13)','',5),
  ('data-inversion-retained','esp_adc_read','255|invert|interrupt','255|interrupt',101),
  ('conversion-IRQ-retained','esp_adc_read','255|invert|interrupt','255|invert',101),
  ('deadline-restarted','esp_adc_read','if !error {\n        esp_reg_update(control','if !error {\n        start=esp32_cycles();esp_reg_update(control',33),
 ]
 records=[];checks=0;reentries=0
 for case in [None]+defs:
  name=case[0] if case else 'protected';tree=w/name/'source';shutil.copytree(source,tree)
  if case:
   _,function,old,new,expected=case;path=tree/'lib/platform/esp32s3-adc.flex';text=path.read_text();begin,end=h['function'](text,function);part=text[begin:end];assert part.count(old)==1,(name,part.count(old));path.write_text(text[:begin]+part.replace(old,new)+text[end:])
  binary=w/name/'checks';run([a.compiler,tree/'tests/esp32/s3-adc-checks.flex','-o',binary],name+'-build')
  q=run([binary,reference],name,1 if case else 0)
  if case:
   assert len(q.stderr)==16 and not q.stdout,(name,q.stderr[:100]);code,n=struct.unpack('<2Q',q.stderr);assert code==expected,(name,code,expected,n)
   records.append(dict(name=name,detected=True,assertion=code,checks_before_failure=n))
  else:
   assert len(q.stdout)==16 and not q.stderr;checks,reentries=struct.unpack('<2Q',q.stdout);assert checks>=350000 and reentries>=66000
  print(name,'passed',flush=True)
 report=dict(pass_all=True,checks=checks,nested_rejections=reentries,channels=20,attenuation_codes=4,interrupt_levels=[0,1,3,7,15],saved_upper_PS=True,defects=records,primary_sources=catalog,source_sha256=manifest,compiler_sha256=sha(a.compiler),physical_hardware=False,emulator_implementation_changes=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
