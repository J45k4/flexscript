#!/usr/bin/env python3
"""Run the complete independent SMP authenticated-checkpoint peer corpus on native and Xtensa.

Firmware batches preserve every scenario within existing flash/heap profiles.
No physical I/O, compiler bootstrap or emulator implementation changes.
"""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','provider','s3-provider','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source';manifest={}
 for n in ['scripts/test-esp32-preempt.flex','scripts/esp32-link.flex','tests/esp32/smp-checkpoint-native.flex','tests/esp32/smp-checkpoint-xip.flex','tests/esp32/s3-smp-checkpoint-xip.flex']:manifest.update(h['copy_closure'](ROOT/n,source))
 for n in ['tests/esp32/abi-oracle/abi-fixture.c','tests/esp32/smp-checkpoint-vectors.py','tests/esp32/smp-checkpoint-reference.py','tests/esp32/abi-oracle/smp-crypto-errors.c']:
  dest=source/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,dest);manifest[n]=sha(dest)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 def run(cmd,name,timeout=60):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=timeout);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.returncode,(q.stdout+q.stderr)[-2200:]);return q
 run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver')
 run([compiler,source/'tests/esp32/smp-checkpoint-native.flex','-o',w/'native'],'native-build')
 run(['python3',source/'tests/esp32/smp-checkpoint-vectors.py','--work',w/'vectors'],'vectors');vectors=json.loads((w/'vectors/report.json').read_text())
 providers={}
 for chip,path in [('esp32',a.provider),('esp32s3',a.s3_provider)]:
  dest=w/('provider-'+chip+'.o');shutil.copyfile(path,dest);providers[chip]=dest
 native_total=0;boots=[]
 for i,part in enumerate(vectors['parts']):
  data=w/'vectors'/part['file'];assert sha(data)==part['sha256'];text=run([w/'native',data],f'native-{i}').stdout
  match=re.fullmatch(rb'PASS: SMP checkpoint (\d+) independent observations\n',text);assert match,text;checks=int(match[1]);native_total+=checks
  assembly=w/f'part-{i}.S';assembly.write_text('.section .rodata.smp_pairs,"a",@progbits\n.balign 16\n.global smp_checkpoint_cases\n.global smp_checkpoint_cases_size\nsmp_checkpoint_cases:\n.incbin '+json.dumps(str(data))+'\n.set smp_checkpoint_cases_size,.-smp_checkpoint_cases\n')
  obj=w/f'part-{i}.o';run([a.prefix+'as',assembly,'-o',obj],f'assembly-{i}')
  for chip,prefix,fixture in [('esp32',a.prefix,'smp-checkpoint-xip.flex'),('esp32s3',a.s3_prefix,'s3-smp-checkpoint-xip.flex')]:
   out=w/f'{chip}-{i}';run([w/'driver','--compiler',compiler,'--qemu',qemu,'--prefix',prefix,'--chip',chip,'--assembly',obj,'--extra',providers[chip],'--xip','yes','--source',source/'tests/esp32'/fixture,'--work',out],f'{chip}-{i}')
   uart=(out/'executed.uart').read_text();match=re.search(r'PASS: SMP checkpoint ([0-9a-f]{16}) independent observations',uart);assert match and int(match[1],16)==checks,(chip,i,uart[-1200:]);boots.append(dict(chip=chip,part=i,checks=checks,elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin'),uart_sha256=sha(out/'executed.uart')))
 assert native_total==vectors['checks']
 for n,v in manifest.items():assert sha(ROOT/n)==v,n
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,cases=vectors['cases'],observations=vectors['checks'],checks_per_target=native_total,native_checks=native_total,stock_QEMU_boots=boots,sources=len(manifest),source_manifest_sha256=sha(w/'source-sha256.json'),compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),physical_hardware=False,emulator_changes=False,radio_integration=False,authenticated_envelope=True,media_durability=False,trusted_restart_rollback_anchor=False,providers_sha256={chip:sha(path) for chip,path in providers.items()}),indent=2)+'\n')
 print('PASS:',vectors['cases'],'checkpoint vectors;',native_total,'checks per native/original/S3 target;',len(boots),'stock QEMU boots')
if __name__=='__main__':main()
