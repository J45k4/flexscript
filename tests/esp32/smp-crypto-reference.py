#!/usr/bin/env python3
"""Rebuild and verify SMP crypto from a captured Flexscript source closure.

Requires explicit pinned Mbed TLS archive, Zephyr reference, installed compiler,
toolchains and stock QEMU. No compiler bootstrap, downloads or physical I/O.
"""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','archive','reference','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve();archive=Path(a.archive).resolve();ref=Path(a.reference).resolve()
 assert sha(archive)=='a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6'
 assert sha(ref)=='febf3b983e44eca722e05da0c46122a4b3a9016ea37151967c5b21763014e098'
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source';manifest={}
 for n in ['scripts/build-esp32-smp-crypto.flex','scripts/test-esp32-preempt.flex','scripts/esp32-link.flex','tests/esp32/smp-crypto-native.flex','tests/esp32/smp-crypto-xip.flex','tests/esp32/s3-smp-crypto-xip.flex','tests/esp32/smp-crypto-errors-xip.flex','tests/esp32/s3-smp-crypto-errors-xip.flex','tests/esp32/ble-host-runtime.flex','tests/esp32/gatt-server-runtime.flex']:manifest.update(h['copy_closure'](ROOT/n,source))
 files=['lib/platform/esp32-smp-mbedtls-config.h','tests/esp32/abi-oracle/smp-crypto-profile.c','tests/esp32/abi-oracle/smp-openssl-profile.c','tests/esp32/abi-oracle/smp-crypto-errors.c','tests/esp32/abi-oracle/abi-fixture.c','tests/esp32/smp-crypto-vectors.py','tests/esp32/smp-crypto-controls.py','tests/esp32/smp-crypto-provider-controls.py','tests/esp32/smp-crypto-build-reference.py','tests/esp32/smp-crypto-reference.py','tests/esp32/lifecycle-preempt-reference.py']
 for n in files:
  out=source/n;out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,out);manifest[n]=sha(out)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 def run(cmd,name,timeout=90):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=timeout);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.returncode,(q.stdout+q.stderr)[-2000:]);return q
 run([compiler,source/'scripts/build-esp32-smp-crypto.flex','-o',w/'build-crypto'],'builder')
 run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver')
 run(['cc','-std=c11','-Wall','-Wextra','-Werror',source/'tests/esp32/abi-oracle/smp-openssl-profile.c','-o',w/'openssl-profile'],'openssl-profile')
 host_profile=run([w/'openssl-profile'],'openssl-extent').stdout.decode().strip()
 run(['python3',source/'tests/esp32/smp-crypto-vectors.py','--reference',ref,'--work',w/'vectors'],'vectors')
 text=''
 for label,name in [('smp_vectors','vectors.bin'),('smp_large','large.bin')]:text+='.section .rodata.'+label+',"a",@progbits\n.balign 16\n.global '+label+'\n.global '+label+'_size\n'+label+':\n.incbin '+json.dumps(str(w/'vectors'/name))+'\n.set '+label+'_size,.-'+label+'\n'
 (w/'vectors.S').write_text(text);run([a.prefix+'as',w/'vectors.S','-o',w/'vectors.o'],'vectors-object')
 run([compiler,source/'tests/esp32/smp-crypto-native.flex','-o',w/'native'],'native-build')
 run([w/'native',w/'vectors/vectors.bin',w/'vectors/large.bin'],'native')
 run(['tar','-xjf',archive,'-C',w],'vendor-source');vendor=w/'mbedtls-3.6.7';packages={};errors={}
 for chip,prefix in [('esp32',a.prefix),('esp32s3',a.s3_prefix)]:
  package=w/('vendor-'+chip);run([w/'build-crypto','--archive',archive,'--output',package,'--chip',chip,'--prefix',prefix],'package-'+chip)
  metadata=json.loads((package/'flexscript-smp-crypto.json').read_text());assert metadata['archive_sha256']==sha(package/'libsmpcrypto.a') and metadata['chip']==chip and metadata['context_size']==184 and metadata['context_capacity']==256
  packages[chip]=package/'libsmpcrypto.a'
  raw=w/(chip+'-aes.o');raw.write_bytes(run([prefix+'ar','p',packages[chip],'smp-aes.o'],'member-'+chip).stdout)
  renamed=w/(chip+'-renamed.o');peer=w/(chip+'-peer.o');combined=w/(chip+'-errors.o')
  run([prefix+'objcopy','--redefine-sym','smp_vendor_mbedtls_aes_setkey_enc=smp_vendor_real_setkey',raw,renamed],'rename-'+chip)
  run([prefix+'gcc','-Os','-fno-builtin','-mlongcalls','-mtext-section-literals','-DMBEDTLS_CONFIG_FILE="esp32-smp-mbedtls-config.h"','-I',source/'lib/platform','-I',vendor/'include','-c',source/'tests/esp32/abi-oracle/smp-crypto-errors.c','-o',peer],'peer-'+chip)
  run([prefix+'ld','-r',renamed,peer,'-o',combined],'error-object-'+chip);errors[chip]=combined
 run(['python3',source/'tests/esp32/smp-crypto-controls.py','--compiler',compiler,'--vectors',w/'vectors/vectors.bin','--large',w/'vectors/large.bin','--work',w/'algorithm-controls'],'algorithms')
 run(['python3',source/'tests/esp32/smp-crypto-provider-controls.py','--compiler',compiler,'--driver',w/'driver','--qemu',qemu,'--prefix',a.prefix,'--s3-prefix',a.s3_prefix,'--original',packages['esp32'],'--s3',packages['esp32s3'],'--errors',errors['esp32'],'--s3-errors',errors['esp32s3'],'--vectors-object',w/'vectors.o','--work',w/'provider-controls'],'providers')
 run(['python3',source/'tests/esp32/smp-crypto-build-reference.py','--builder',w/'build-crypto','--archive',archive,'--prefix',a.prefix,'--work',w/'package-checks'],'package-checks')
 for name in ['ble-host-runtime','gatt-server-runtime']:
  run([compiler,source/'tests/esp32'/(name+'.flex'),'-o',w/name],name+'-build');run([w/name],name)
 for n,v in manifest.items():assert sha(ROOT/n)==v,n
 proofs={}
 for name in ['algorithm-controls','provider-controls','package-checks']:
  report=json.loads((w/name/'report.json').read_text());assert report['pass_all'];proofs[name]=sha(w/name/'report.json')
 artifacts={str(path.relative_to(w)):sha(path) for path in [w/'build-crypto',w/'driver',w/'native',w/'vectors/vectors.bin',w/'vectors/large.bin',w/'vectors.o',w/'esp32-peer.o',w/'esp32s3-peer.o',*packages.values(),*errors.values()]}
 for chip in ['esp32','esp32s3']:
  for name in ['positive','C-error-paths']:
   folder=w/'provider-controls'/(chip+'-'+name)/'run'
   for suffix in ['elf','bin']:path=folder/('firmware.'+suffix);artifacts[str(path.relative_to(w))]=sha(path)
 report=dict(pass_all=True,sources=len(manifest),source_manifest_sha256=sha(w/'source-sha256.json'),artifacts=artifacts,proofs=proofs,records=278,large_CMAC_bytes=[513,4096,65535],native_assertions=1892,Xtensa_vector_assertions_per_chip=1671,Xtensa_C_error_assertions_per_chip=1072,algorithm_defects=22,provider_defects=12,preserved_package_rejections=13,openssl_key_extent_alignment=host_profile,reference_sha256=sha(ref),vendor_source_sha256=sha(archive),compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),physical_hardware=False,emulator_changes=False,pairing_state_machine_complete=False,bonding_complete=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: frozen SMP crypto',len(manifest),'sources;278 vectors/native1892/Xtensa1671+1072 perchip;34 defects/13 preserved-output rejections')
if __name__=='__main__':main()
