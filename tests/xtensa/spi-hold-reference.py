#!/usr/bin/env python3
"""Compare independent physical SPI captures and reject timing model defects.

This verifier never opens hardware. Captures must have successful RAM-only
cleanup, unchanged flash and exact image/transcript identity.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--capture',nargs=2,action='append',metavar=('DIRECTORY','CASES'),required=True)
 p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True)
 p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
 a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
 compiler=a.compiler.resolve();refs=a.reference.resolve();captures=[(Path(d).resolve(),int(n)) for d,n in a.capture]
 def compare(model,label):
  reports=[]
  for i,(capture,n) in enumerate(captures):
   out=work/label/str(i);out.mkdir(parents=True,exist_ok=True);report=out/'report.json'
   args=['python3',str(root/'tests/esp32/spi-waveform-reference.py'),'--capture',str(capture),'--expected-cases',str(n),'--compiler',str(compiler),'--reference',str(refs),'--work',str(out),'--report',str(report),'--model',str(model)]
   q=subprocess.run(args,cwd=root,capture_output=True);(out/'run.log').write_bytes(q.stdout+q.stderr)
   assert q.returncode in [0,1] and report.exists(),(label,i,q.returncode,q.stderr[-1500:])
   x=json.loads(report.read_text());assert x['cases']==n and bool(q.returncode)==(not x['pass'])
   reports.append(x)
  return reports
 baseline=compare(source_path(root,'esp32-emulator.flex'),'baseline');assert all(x['pass'] and x['model_verified'] for x in baseline)
 mutations=[
  ('ignored-command-delay','if (u2&255)==0x52{completion=1;}',''),
  ('command-length-nine-only','if (u2&255)==0x52{completion=1;}','if (u2&255)==0x52 && command==9{completion=1;}'),
  ('command-phase-dependent','if (u2&255)==0x52{completion=1;}','if (u2&255)==0x52 && command{completion=1;}'),
  ('msb-first-only','if (u2&255)==0x52{completion=1;}','if (u2&255)==0x52 && !txlsb{completion=1;}'),
  ('upper-command-byte-sensitive','if (u2&255)==0x52{completion=1;}','if (u2&65535)==0x52{completion=1;}'),
  ('forced-hold-when-disabled','if hold>completion{hold=completion;}','if (u2&255)==0x52{hold=1;}else if hold>completion{hold=completion;}'),
  ('missing-hold-cap','if hold>completion{hold=completion;}',''),
  ('wrong-delay-field','((se_spi_cfg(s,bus,12)>>28)&15)+1','((se_spi_cfg(s,bus,12)>>27)&15)+1'),
  ('ignored-programmed-delay','((se_spi_cfg(s,bus,12)>>28)&15)+1','6'),
 ]
 controls=[]
 for label,old,new in mutations:
  out=work/label/'modules';out.mkdir(parents=True,exist_ok=True)
  for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex']:
   source=clone_source(root,name)
   if name=='esp32-spi-emulator.flex':assert source.count(old)==1,(label,source.count(old));source=source.replace(old,new)
   source=source.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex'))));(out/name).write_text(source)
  results=compare(out/'esp32-emulator.flex',label);failures=[{'capture':i,'failures':x['model_failures']} for i,x in enumerate(results) if not x['pass']]
  assert failures,label+' escaped physical comparisons'
  controls.append({'control':label,'detected':True,'failures':failures});print(label+': detected',flush=True)
 report={'pass':True,'scope_complete':False,'physical_captures_compared':len(captures),'cases':sum(x['cases'] for x in baseline),'bits':sum(x['bits'] for x in baseline),'clock_edges':sum(x['clock_edges'] for x in baseline),'baseline':baseline,'negative_controls':controls,'physical_hardware_accessed':False,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'limitations':['Saved captures are original ESP32 rev3; S3 and other silicon revisions remain unverified.','Pin comparisons establish the measured CS/clock/data behavior. The separate completion-marker verifier checks TRANS_DONE/USR timing.']}
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['pass','cases','bits','clock_edges']}));return 0
if __name__=='__main__':raise SystemExit(main())
