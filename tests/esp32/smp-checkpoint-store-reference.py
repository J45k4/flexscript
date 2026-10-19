#!/usr/bin/env python3
"""Exercise the real settings/checkpoint coordinator with independent NOR and anchor boundary peers.

The counter peer is not a physical anti-rollback provider. No emulator changes,
physical device I/O, flash provisioning or compiler bootstrap are performed.
"""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','provider','s3-provider','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source';manifest={}
 for n in ['scripts/test-esp32-preempt.flex','scripts/esp32-link.flex','tests/esp32/smp-checkpoint-store-native.flex','tests/esp32/smp-checkpoint-store-xip.flex','tests/esp32/s3-smp-checkpoint-store-xip.flex']:manifest.update(h['copy_closure'](ROOT/n,source))
 for n in ['tests/esp32/abi-oracle/abi-fixture.c','tests/esp32/abi-oracle/smp-crypto-errors.c','tests/esp32/smp-checkpoint-store-reference.py']:
  dest=source/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,dest);manifest[n]=sha(dest)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve()
 def run(cmd,name,timeout=90):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=timeout);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.returncode,(q.stdout+q.stderr)[-2000:]);return q
 run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver')
 run([compiler,source/'tests/esp32/smp-checkpoint-store-native.flex','-o',w/'native'],'native-build')
 native=run([w/'native'],'native').stdout;m=re.fullmatch(rb'SMP checkpoint-store status=0 checks=(\d+)\n',native);assert m,native;checks=int(m[1]);boots=[]
 for chip,prefix,fixture,provider in [('esp32',a.prefix,'smp-checkpoint-store-xip.flex',a.provider),('esp32s3',a.s3_prefix,'s3-smp-checkpoint-store-xip.flex',a.s3_provider)]:
  obj=w/('provider-'+chip+'.o');shutil.copyfile(provider,obj);out=w/chip
  run([w/'driver','--compiler',compiler,'--qemu',qemu,'--prefix',prefix,'--chip',chip,'--extra',obj,'--xip','yes','--source',source/'tests/esp32'/fixture,'--work',out],chip)
  uart=(out/'executed.uart').read_text();m=re.search(r'PASS: SMP checkpoint-store ([0-9a-f]{16})',uart);assert m and int(m[1],16)==checks,(chip,uart[-2000:]);boots.append(dict(chip=chip,checks=checks,elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin'),uart_sha256=sha(out/'executed.uart'),provider_sha256=sha(obj)))
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,scenarios=23,checks_per_target=checks,stock_QEMU_boots=boots,sources=len(manifest),source_manifest_sha256=sha(w/'source-sha256.json'),compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),physical_hardware=False,emulator_changes=False,physical_media_durability_verified=False,trusted_physical_anchor_verified=False,anchor_is_boundary_peer=True,boot_recovery_implemented=False,full_authentication=False),indent=2)+'\n');print('PASS:23 settings/NOR/anchor-boundary scenarios;',checks,'checks per native/original/S3 target;2 stock QEMU boots')
if __name__=='__main__':main()
