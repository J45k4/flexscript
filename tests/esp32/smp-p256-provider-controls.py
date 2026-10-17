#!/usr/bin/env python3
"""Execute actual target guard matrix and isolated provider defects on both chips."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','driver','qemu','prefix','s3-prefix','original','s3','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest={}
 for n in ['smp-p256-guards-xip.flex','s3-smp-p256-guards-xip.flex']:manifest.update(h['copy_closure'](ROOT/'tests/esp32'/n,base))
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');cases=[]
 defects=[
  ('unaligned-context-accepted','esp_smp_curve_init','context&7 || ','',2),
  ('context-capacity-off-by-one','esp_smp_curve_init','capacity<64','capacity<63',3),
  ('ISR-init-admitted','esp_smp_curve_init',' || esp32_load32(esp32_state()+16)','',5),
  ('ISR-deinit-admitted','esp_smp_curve_deinit',' || esp32_load32(esp32_state()+16)','',6),
  ('ISR-preflight-admitted','smp_p256_ready',' || esp32_load32(esp32_state()+16)','',8),
  ('ISR-C-call-admitted','smp_p256_backend',' || esp32_load32(esp32_state()+16)','',9),
  ('busy-preflight-admitted','smp_p256_ready','esp_smp_curve_busy || ','',10),
  ('busy-C-call-admitted','smp_p256_backend','esp_smp_curve_busy || ','',11),
  ('provider-context-scratch-alias','smp_p256_ready',' || p256_overlap(work,size,esp_smp_curve_context,64)','',12),
  ('original-wire-context-alias','smp_p256_external',' && !p256_overlap(p,n,esp_smp_curve_context,64)','',37),
  ('provider-context-input-alias','esp_smp_curve_inputs',' || p256_overlap(context,64,a,an)','',17),
  ('C-error-not-sign-extended','esp_smp_curve_i32','if r>=2147483648 {return r-4294967296;}','',23),
  ('missing-entropy-still-enters-vendor','smp_p256_backend','if op==4 && !esp_smp_curve_random {esp32_irq_restore(ps);return -19;}','',22),
  ('vendor-operation-left-busy','smp_p256_backend','esp_smp_curve_busy=0;','',24),
  ('caller-interrupt-level-not-restored','smp_p256_backend','esp32_irq_restore(ps);return r;','esp32_irq_restore(ps|15);return r;',24),
  ('nonce-failure-publishes','esp_smp_curve_entropy','if !r {nb_copy(out,work,size);}','nb_copy(out,work,size);',45),
  ('nonce-staging-not-cleared','esp_smp_curve_entropy','nb_zero(work,32);esp32_irq_save();','esp32_irq_save();',44),
  ('entropy-error-lost','smp_p256_backend','if r && esp_smp_curve_entropy_error {r=esp_smp_curve_entropy_error;}','',31),
  ('entropy-byte-count-accepted-as-success','smp_curve_vendor_psa_generate_random','if r>0 {r=-22;}','if r>0 {r=0;}',31),
  ('entropy-descriptor-mutation-accepted','smp_curve_vendor_psa_generate_random','if load64(context)!=out || load64(context+8)!=size || load64(context+16)!=esp_smp_curve_argument || !esp_smp_curve_zero(context+24,40) {r=-116;}','',31),
 ]
 for chip,prefix,provider,fixture in [('esp32',a.prefix,a.original,'smp-p256-guards-xip.flex'),('esp32s3',a.s3_prefix,a.s3,'s3-smp-p256-guards-xip.flex')]:
  for item in [None]+defects:
   name=chip+'-'+(item[0] if item else 'protected');tree=w/name/'source';shutil.copytree(base,tree)
   if item:
    _,fn,before,after,_=item;h['change'](tree/'lib/platform/esp32-smp-p256.flex',fn,lambda body:h['once'](body,before,after))
   out=w/name/'run';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',prefix,'--chip',chip,'--extra',provider,'--xip','yes','--source',tree/'tests/esp32'/fixture,'--work',out]
   with log.open('w') as stream:r=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
   text=log.read_text()
   if item:assert r.returncode==1 and 'SMP P256 GUARD FAIL '+f'{item[4]:016x}' in text,(name,r.returncode,text[-2000:]);assert 'SHUTDOWN' in (out/'qmp-failure.log').read_text()
   else:assert r.returncode==0 and 'PASS: SMP P256 guards ' in text,(name,r.returncode,text[-2000:])
   cases.append(dict(name=name,defect=bool(item),expected_checkpoint=item[4] if item else None,log_sha256=sha(log),elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin')));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,positive_boots=2,defects=len(defects)*2,cases=cases,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.original,a.s3]},physical_hardware=False,physical_entropy=False,emulator_changes=False),indent=2)+'\n');print('PASS:both chips target guard matrix;',len(defects)*2,'provider defects detected')
if __name__=='__main__':main()
