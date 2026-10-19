#!/usr/bin/env python3
"""Run independent SC peer transcripts with real P-256/AES, native and Xtensa."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','curve','aes','work']:p.add_argument('--'+k,required=True)
 p.add_argument("--vectors-script",default="smp-sc-vectors.py",choices=["smp-sc-vectors.py","smp-passkey-vectors.py","smp-oob-vectors.py"]);a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();curve=Path(a.curve).resolve();aes=Path(a.aes).resolve();source=w/'source';h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));manifest={}
 for f in ['tests/esp32/smp-sc-native.flex','tests/esp32/smp-sc-xip.flex','tests/esp32/s3-smp-sc-xip.flex','scripts/test-esp32-preempt.flex','scripts/esp32-link.flex']:manifest.update(h['copy_closure'](ROOT/f,source))
 for f in ['tests/esp32/smp-sc-vectors.py','tests/esp32/smp-passkey-vectors.py','tests/esp32/smp-oob-vectors.py','tests/esp32/smp-crypto-vectors.py','tests/esp32/smp-sc-reference.py','tests/esp32/abi-oracle/abi-fixture.c']:
  dest=source/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/f,dest);manifest[f]=sha(dest)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 def run(cmd,name,timeout=90):
  r=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=timeout);(w/(name+'.log')).write_bytes(r.stdout+r.stderr);assert r.returncode==0,(name,r.returncode,(r.stdout+r.stderr)[-2400:]);return r
 compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve();provider=curve/'native-provider.so'
 run(['python3',source/'tests/esp32'/a.vectors_script,'--work',w/'vectors'],'vectors');run([compiler,source/'tests/esp32/smp-sc-native.flex','-o',w/'native'],'native-build');r=run([w/'native',w/'vectors/cases.bin',provider],'native')
 m=re.fullmatch(rb'PASS: SMP SC (\d+) independent observations\n',r.stdout);assert m,r.stdout;checks=int(m[1]);run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver')
 boots=[];providers={};extras={};parts=json.loads((w/'vectors/report.json').read_text())['parts'];total=0
 for chip,prefix,fixture in [('esp32',a.prefix,'smp-sc-xip.flex'),('esp32s3',a.s3_prefix,'s3-smp-sc-xip.flex')]:
  extra=w/(chip+'-crypto.o');run([prefix+'ld','-r','-o',extra,curve/('provider-'+chip+'.o'),aes/(chip+'-errors.o')],chip+'-provider');extras[chip]=extra;providers[chip]=dict(curve=sha(curve/('provider-'+chip+'.o')),aes=sha(aes/(chip+'-errors.o')),combined=sha(extra))
 for i,part in enumerate(parts):
  data=w/'vectors'/part['file'];assert sha(data)==part['sha256'];r=run([w/'native',data,provider],f'native-{i}');m=re.fullmatch(rb'PASS: SMP SC (\d+) independent observations\n',r.stdout);assert m;part_checks=int(m[1]);total+=part_checks
  assembly=w/f'part-{i}.S';assembly.write_text('.section .rodata.smp_sc,"a",@progbits\n.balign 16\n.global smp_sc_cases\n.global smp_sc_cases_size\nsmp_sc_cases:\n.incbin '+json.dumps(str(data))+'\n.set smp_sc_cases_size,.-smp_sc_cases\n');obj=w/f'part-{i}.o';run([a.prefix+'as',assembly,'-o',obj],f'assembly-{i}')
  for chip,prefix,fixture in [('esp32',a.prefix,'smp-sc-xip.flex'),('esp32s3',a.s3_prefix,'s3-smp-sc-xip.flex')]:
   out=w/f'{chip}-{i}';run([w/'driver','--compiler',compiler,'--qemu',qemu,'--prefix',prefix,'--chip',chip,'--assembly',obj,'--extra',extras[chip],'--xip','yes','--source',source/'tests/esp32'/fixture,'--work',out],f'{chip}-{i}')
   uart=(out/'executed.uart').read_text();m=re.search(r'PASS: SMP SC ([0-9a-f]{16}) independent observations',uart);assert m and int(m[1],16)==part_checks,(chip,uart[-1500:]);boots.append(dict(chip=chip,part=i,checks=part_checks,elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin'),uart_sha256=sha(out/'executed.uart')))
  print('PASS batch',i,part_checks,'checks per target',flush=True)
 assert total==checks
 for f,v in manifest.items():assert sha(ROOT/f)==v,f
 result=dict(pass_all=True,cases=json.loads((w/'vectors/report.json').read_text()),checks_per_target=checks,stock_QEMU_boots=boots,source_sha256=manifest,compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),providers=providers,native_provider_sha256=sha(provider),physical_hardware=False,radio_integration=False,emulator_changes=False,production_entropy=False,controller_encryption=False)
 (w/'report.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS:',checks,'SC checks per native/original/S3 target')
if __name__=='__main__':main()
