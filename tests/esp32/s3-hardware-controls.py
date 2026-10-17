#!/usr/bin/env python3
"""Primary-header S3 MMIO operand spies; no peripheral model or ISA emulation."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/s3-radio-hardware-checks.flex',base)
 changes=[
 ('wrong-clock-register','esp32s3-radio-hardware.flex','esp_radio_phy_clock','esp32_store32(0x60026014,esp32_load32(0x60026014)|','esp32_store32(0x600c0014,esp32_load32(0x600c0014)|'),('wrong-init-register','esp32s3-radio-hardware.flex','esp_radio_clocks_init','let value=esp32_load32(0x60026014);','let value=esp32_load32(0x600c0014);'),
 ('original-clock-mask','esp32s3-radio-hardware.flex','esp_radio_phy_clock','|0x78078f','|0x3c9'),('unmasked-clock','esp32s3-radio-hardware.flex','esp_radio_phy_clock','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(ps);'),
 ('PS-not-restored','esp32s3-radio-hardware.flex','esp_radio_phy_clock','esp32_irq_restore(ps);return 0;','esp32_irq_restore(0);return 0;'),('reference-underflow','esp32s3-radio-hardware.flex','esp_radio_phy_clock','else if esp_radio_phy_clock_refs','else'),
 ('reference-not-counted','esp32s3-radio-hardware.flex','esp_radio_phy_clock','esp_radio_phy_clock_refs=esp_radio_phy_clock_refs+1;',''),('nested-clock-rewritten','esp32s3-radio-hardware.flex','esp_radio_phy_clock','if !esp_radio_phy_clock_refs {esp32_store32(0x60026014,esp32_load32(0x60026014)|','if 1 {esp32_store32(0x60026014,esp32_load32(0x60026014)|'),
 ('ADC-conflict','esp32s3-radio-hardware.flex','esp_radio_phy_clock','if enable && esp_adc_busy','if 0'),('reference-overflow','esp32s3-radio-hardware.flex','esp_radio_phy_clock','if enable && esp_radio_phy_clock_refs==9223372036854775807','if 0'),
 ('wrong-reset-bit','esp32s3-radio-hardware.flex','esp_radio_cb_wifi_reset','before|4','before|8'),('wrong-reset-register','esp32s3-radio-hardware.flex','esp_radio_cb_wifi_reset','esp32_load32(0x60026018)','esp32_load32(0x600c0020)'),
 ('original-RNG-register','esp32s3-radio-hardware.flex','esp_radio_random_word','0x6003507c','0x3ff75144'),('original-eFuse-register','esp32s3-radio-hardware.flex','esp_radio_cb_read_mac','0x60007044','0x3ff5a004'),
 ('lost-MAC-carry','esp32s3-radio-hardware.flex','esp_radio_cb_read_mac','(((hi&65535)<<32)|lo)+b','(((hi&65535)<<32)|(lo&~255)|((lo+b)&255))'),('negative-MAC-kind','esp32s3-radio-hardware.flex','esp_radio_cb_read_mac',' || b<0',''),
 ('wrong-slowclk-register','esp32s3-radio-hardware.flex','esp_radio_cb_slowclk_cal','0x60008054','0x600080b4'),('wrong-slowclk-fraction','esp32s3-radio-hardware.flex','esp_radio_cb_slowclk_cal','>>7','>>19'),
 ('random-tail-overwrite','esp32-radio-random.flex','esp_radio_cb_get_random','j<4 && i<b','j<4'),('random-byte-order','esp32-radio-random.flex','esp_fill_random','n>>(j*8)','n>>(24-j*8)'),
 ]
 cases=[];checks=0
 for change in [None]+changes:
  name=change[0] if change else 'canonical';tree=w/name/'source';shutil.copytree(base,tree)
  if change:
   _,module,fn,before,after=change;h['change'](tree/'lib/platform'/module,fn,lambda t:h['once'](t,before,after))
  exe=w/name/'checks';q=subprocess.run([a.compiler,str(tree/'tests/esp32/s3-radio-hardware-checks.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30);assert q.returncode==0,(name,q.stderr)
  q=subprocess.run([str(exe),a.vectors],cwd=ROOT,env=env,capture_output=True,timeout=10);(w/(name+'.log')).write_bytes(q.stdout+q.stderr)
  if change:assert 1<=q.returncode<=18 and b'S3 hardware operand mismatch' in q.stderr,(name,q.returncode,q.stdout,q.stderr)
  else:
   assert q.returncode==0,(q.stdout,q.stderr);match=re.fullmatch(rb'S3 hardware operands: (\d+) checks\n',q.stdout);assert match;checks=int(match[1])
  cases.append(dict(name=name,detected=bool(change),log_sha256=sha(w/(name+'.log'))))
 assert all(sha(ROOT/n)==digest for n,digest in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,checks=checks,defects=len(changes),cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(a.vectors),physical_hardware=False,peripheral_model=False,emulator_implementation_changes=False),indent=2)+'\n');print(f'PASS: {checks} primary-header MMIO checks;{len(changes)} isolated defects',flush=True)
if __name__=='__main__':main()
