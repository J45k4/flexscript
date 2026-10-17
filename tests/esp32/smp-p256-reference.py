#!/usr/bin/env python3
"""Build and exercise pinned p256-m wire/ABI/entropy consumers on native and Xtensa.

Independent expected math uses cryptography/OpenSSL and pinned raw-key vectors.
Deterministic entropy streams are test inputs,not a physical CSPRNG claim.
"""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PIN='a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6'
WYCHE='cdb8bd5d1206fddb6618c69ffa18f303b4752caba321d348d4aacae3f20cbec4'
RENAMES={'p256_validate_pubkey':'validate_pubkey','p256_validate_privkey':'validate_privkey','p256_public_from_private':'public','p256_ecdh_shared_secret':'shared','p256_gen_keypair':'gen'}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','archive','reference','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve();archive=Path(a.archive).resolve();reference=Path(a.reference).resolve();assert sha(archive)==PIN and sha(reference)==WYCHE
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source';manifest={}
 for n in ['scripts/test-esp32-preempt.flex','scripts/esp32-link.flex','scripts/build-esp32-smp-p256.flex','tests/esp32/smp-p256-native.flex','tests/esp32/smp-p256-xip.flex','tests/esp32/s3-smp-p256-xip.flex']:manifest.update(h['copy_closure'](ROOT/n,source))
 for n in ['lib/platform/esp32-smp-p256-config.h','tests/esp32/abi-oracle/smp-p256-profile.c','tests/esp32/abi-oracle/smp-p256-errors.c','tests/esp32/abi-oracle/abi-fixture.c','tests/esp32/smp-p256-vectors.py','tests/esp32/smp-p256-reference.py']:
  dest=source/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,dest);manifest[n]=sha(dest)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');shutil.copyfile(reference,w/'wycheproof.json');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 def run(cmd,name,timeout=90):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=timeout);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.returncode,(q.stdout+q.stderr)[-2600:]);return q
 vendor=w/'vendor';vendor.mkdir(exist_ok=True)
 with tarfile.open(archive) as t:
  names=[n for n in t.getnames() if n.startswith('mbedtls-3.6.7/include/') or n.startswith('mbedtls-3.6.7/3rdparty/p256-m/') or n=='mbedtls-3.6.7/tests/suites/test_suite_ecdh.data'];t.extractall(vendor,members=[t.getmember(n) for n in names],filter='data')
 root=vendor/'mbedtls-3.6.7';p256=root/'3rdparty/p256-m/p256-m';inc=root/'include';nativecc=shutil.which('cc');nativeobjcopy=shutil.which('objcopy');assert nativecc and nativeobjcopy
 run([compiler,source/'scripts/build-esp32-smp-p256.flex','-o',w/'builder'],'builder');run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver');run([compiler,source/'tests/esp32/smp-p256-native.flex','-o',w/'native'],'native-build')
 providers={};packages={}
 for chip,prefix in [('esp32',a.prefix),('esp32s3',a.s3_prefix)]:
  pkg=w/(chip+'-package');run([w/'builder','--archive',archive,'--chip',chip,'--prefix',prefix,'--output',pkg],chip+'-package');packages[chip]=json.loads((pkg/'flexscript-smp-curve.json').read_text());obj=w/(chip+'-base.o');run([prefix+'ld','-r','--whole-archive',pkg/'libsmpcurve.a','--no-whole-archive','-o',obj],chip+'-whole')
  args=[prefix+'objcopy']
  for old,new in RENAMES.items():args+=['--redefine-sym','smp_curve_vendor_'+old+'=smp_curve_real_'+new]
  real=w/(chip+'-real.o');run(args+[obj,real],chip+'-rename');error=w/(chip+'-errors.o');run([prefix+'gcc','-Os','-fno-builtin','-mlongcalls','-mtext-section-literals','-I'+str(p256),'-c',source/'tests/esp32/abi-oracle/smp-p256-errors.c','-o',error],chip+'-errors');out=w/('provider-'+chip+'.o');run([prefix+'ld','-r',real,error,'-o',out],chip+'-provider');providers[chip]=out
 run([nativecc,'-Os','-fPIC','-fno-builtin','-DMBEDTLS_CONFIG_FILE="esp32-smp-p256-config.h"','-I'+str(source/'lib/platform'),'-I'+str(inc),'-c',p256/'p256-m.c','-o',w/'native-base.o'],'native-vendor')
 args=[nativeobjcopy,'--prefix-symbols=smp_curve_vendor_'];run(args+[w/'native-base.o',w/'native-prefixed.o'],'native-prefix');args=[nativeobjcopy]
 for old,new in RENAMES.items():args+=['--redefine-sym','smp_curve_vendor_'+old+'=smp_curve_real_'+new]
 args+=['--redefine-sym','smp_curve_vendor___stack_chk_fail=__stack_chk_fail'];run(args+[w/'native-prefixed.o',w/'native-real.o'],'native-rename');run([nativecc,'-Os','-fPIC','-fno-builtin','-DSMP_P256_NATIVE_PEER','-I'+str(p256),'-c',source/'tests/esp32/abi-oracle/smp-p256-errors.c','-o',w/'native-errors.o'],'native-errors');run([nativecc,'-shared','-Wl,-z,defs',w/'native-real.o',w/'native-errors.o','-o',w/'native-provider.so'],'native-provider')
 run(['python3',source/'tests/esp32/smp-p256-vectors.py','--reference',w/'wycheproof.json','--nist',root/'tests/suites/test_suite_ecdh.data','--work',w/'vectors'],'vectors');vectors=json.loads((w/'vectors/report.json').read_text());native_total=0;boots=[]
 for i,part in enumerate(vectors['parts']):
  data=w/'vectors'/part['file'];assert sha(data)==part['sha256'];out=run([w/'native',data,w/'native-provider.so'],f'native-{i}');match=re.fullmatch(rb'PASS: SMP P256 (\d+) independent observations\n',out.stdout);assert match,out.stdout;checks=int(match[1]);assert checks==part['cases'];native_total+=checks
  asm=w/f'part-{i}.S';asm.write_text('.section .rodata.smp_pairs,"a",@progbits\n.balign 16\n.global smp_p256_cases\n.global smp_p256_cases_size\nsmp_p256_cases:\n.incbin '+json.dumps(str(data))+'\n.set smp_p256_cases_size,.-smp_p256_cases\n');obj=w/f'part-{i}.o';run([a.prefix+'as',asm,'-o',obj],f'assembly-{i}')
  for chip,prefix,fixture in [('esp32',a.prefix,'smp-p256-xip.flex'),('esp32s3',a.s3_prefix,'s3-smp-p256-xip.flex')]:
   dest=w/f'{chip}-{i}';run([w/'driver','--compiler',compiler,'--qemu',qemu,'--prefix',prefix,'--chip',chip,'--assembly',obj,'--extra',providers[chip],'--xip','yes','--source',source/'tests/esp32'/fixture,'--work',dest],f'{chip}-{i}',120);uart=(dest/'executed.uart').read_text();match=re.search(r'PASS: SMP P256 ([0-9a-f]{16}) independent observations',uart);assert match and int(match[1],16)==checks,(chip,i,uart[-2500:]);boots.append(dict(chip=chip,part=i,checks=checks,elf_sha256=sha(dest/'firmware.elf'),image_sha256=sha(dest/'firmware.bin'),uart_sha256=sha(dest/'executed.uart')))
  print('PASS P-256 part',i,checks,flush=True)
 assert native_total==vectors['cases'] and all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,cases=native_total,checks_per_target=native_total,stock_QEMU_boots=boots,sources=len(manifest),source_manifest_sha256=sha(w/'source-sha256.json'),compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),input_archive_sha256=PIN,wycheproof_sha256=WYCHE,wycheproof_raw_cases=len(vectors['wycheproof_raw_eligible_ids']),wycheproof_excluded=len(vectors['wycheproof_excluded']),packages=packages,provider_sha256={chip:sha(path) for chip,path in providers.items()},native_provider_sha256=sha(w/'native-provider.so'),physical_hardware=False,physical_entropy=False,radio_pairing=False,full_authentication=False,emulator_changes=False),indent=2)+'\n');print('PASS:',native_total,'P-256 cases per native/original/S3 target;',len(boots),'stock QEMU boots')
if __name__=='__main__':main()
