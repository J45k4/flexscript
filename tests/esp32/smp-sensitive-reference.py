#!/usr/bin/env python3
"""Verify separately owned pre-pairing secrets,guards andimmediate erasure."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','qemu','prefix','s3-prefix','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();compiler=Path(a.compiler).resolve();qemu=Path(a.qemu).resolve();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));source=w/'source';manifest={}
 for f in ['tests/esp32/smp-sensitive-native.flex','tests/esp32/smp-sensitive-xip.flex','tests/esp32/s3-smp-sensitive-xip.flex','scripts/test-esp32-preempt.flex','scripts/esp32-link.flex']:manifest.update(h['copy_closure'](ROOT/f,source))
 for f in ['tests/esp32/smp-sensitive-reference.py','tests/esp32/abi-oracle/abi-fixture.c']:
  dest=source/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/f,dest);manifest[f]=sha(dest)
 (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n');(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 def run(cmd,name):
  r=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=90);(w/(name+'.log')).write_bytes(r.stdout+r.stderr);assert r.returncode==0,(name,r.returncode,(r.stdout+r.stderr)[-2200:]);return r
 run([compiler,source/'tests/esp32/smp-sensitive-native.flex','-o',w/'native'],'native-build');r=run([w/'native'],'native');m=re.fullmatch(rb'PASS: SMP sensitive (\d+) independent observations\n',r.stdout);assert m;checks=int(m[1]);run([compiler,source/'scripts/test-esp32-preempt.flex','-o',w/'driver'],'driver');boots=[]
 for chip,prefix,fixture in [('esp32',a.prefix,'smp-sensitive-xip.flex'),('esp32s3',a.s3_prefix,'s3-smp-sensitive-xip.flex')]:
  out=w/chip;run([w/'driver','--compiler',compiler,'--qemu',qemu,'--prefix',prefix,'--chip',chip,'--xip','yes','--source',source/'tests/esp32'/fixture,'--work',out],chip);uart=(out/'executed.uart').read_text();m=re.search(r'PASS: SMP sensitive ([0-9a-f]{16}) independent observations',uart);assert m and int(m[1],16)==checks,(chip,uart[-1600:]);boots.append(dict(chip=chip,checks=checks,elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin'),uart_sha256=sha(out/'executed.uart')))
 mutations=[
 ('registration-does-not-clear','sd_sensitive_register','nb_zero(work,size);',''),
 ('registration-size-overflow','sd_sensitive_register','size>65536','size>65537'),
 ('registration-unaligned','sd_sensitive_register',' || work&7',''),
 ('registration-overlaps-engines','sd_sensitive_register','!sd_external(work,size)','!sm_range(work,size)'),
 ('registration-during-active-owner','sd_sensitive_register',' || so_active',''),
 ('registration-during-checkpoint','sd_sensitive_register',' || sd_busy',''),
 ('registered-area-allowed-as-external','sd_external',' && (!sd_sensitive_work || !so_overlap(p,n,sd_sensitive_work,sd_sensitive_bytes))',''),
 ('fault-does-not-erase-registered-keys','sd_fault','if sd_sensitive_work {nb_zero(sd_sensitive_work,sd_sensitive_bytes);}',''),
 ('release-does-not-check-owner','sd_sensitive_release',' || sd_sensitive_work!=work',''),
 ('release-while-connection-active','sd_sensitive_release','so_active || ',''),
 ('release-during-checkpoint','sd_sensitive_release',' || sd_busy',''),
 ('release-retains-key-bytes','sd_sensitive_release','nb_zero(sd_sensitive_work,sd_sensitive_bytes);',''),
 ('release-retains-registration','sd_sensitive_release','sd_sensitive_work=0;',''),
 ('deinit-abandons-registration','sd_deinit',' || sd_sensitive_work',''),
 ]
 defects=[]
 for name,fn,before,after in mutations:
  tree=w/name/'source';shutil.copytree(source,tree);h['change'](tree/'lib/net/smp-durable.flex',fn,lambda body:h['once'](body,before,after));exe=w/name/'native';run([compiler,tree/'tests/esp32/smp-sensitive-native.flex','-o',exe],name+'-build');r=subprocess.run([str(exe)],cwd=tree,env=env,capture_output=True,timeout=15);log=w/name/'run.log';log.write_bytes(r.stdout+r.stderr);assert r.returncode==8 and b'SMP SENSITIVE FAIL ' in r.stderr,(name,r.returncode,r.stdout,r.stderr);defects.append(dict(name=name,log_sha256=sha(log)));print(name,flush=True)
 for f,v in manifest.items():assert sha(ROOT/f)==v,f
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,checks_per_target=checks,stock_QEMU_boots=boots,defects=defects,source_sha256=manifest,compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),max_registered_bytes=65536,physical_hardware=False,emulator_changes=False,OOB_protocol=False),indent=2)+'\n');print('PASS:',checks,'sensitive-storage checks per native/original/S3 target;',len(defects),'defects detected')
if __name__=='__main__':main()
