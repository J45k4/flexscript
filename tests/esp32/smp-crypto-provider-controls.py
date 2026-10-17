#!/usr/bin/env python3
"""Execute real Xtensa AES/C-error cleanup and provider defect controls."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','driver','qemu','prefix','s3-prefix','original','s3','errors','s3-errors','vectors-object','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest={}
 for n in ['smp-crypto-xip.flex','s3-smp-crypto-xip.flex','smp-crypto-errors-xip.flex','s3-smp-crypto-errors-xip.flex']:manifest.update(h['copy_closure'](ROOT/'tests/esp32'/n,base))
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');cases=[]
 defects=[
  ('negative-C-result-not-sign-extended','smp_aes128','if r>=2147483648 {r=r-4294967296;}','',True,3),
  ('AES-context-capacity-not-wiped','smp_aes128','nb_zero(context,256);','',True,2),
  ('AES-context-left-busy','smp_aes128','esp_smp_crypto_busy=0;','',True,2),
  ('concurrent-AES-admitted','smp_aes128','esp_smp_crypto_busy || ','',False,7),
  ('ISR-AES-admitted','smp_aes128',' || esp32_load32(esp32_state()+16)','',False,9),
  ('context-capacity-off-by-one','esp_smp_crypto_init','capacity<256','capacity<255',False,3),
 ]
 for s3 in [False,True]:
  chip='esp32s3' if s3 else 'esp32'
  runs=[('positive',None,False),('C-error-paths',None,True)]+[(d[0],d,d[4]) for d in defects]
  for label,defect,error in runs:
   name=chip+'-'+label;tree=w/name/'source';shutil.copytree(base,tree)
   if defect:
    _,fn,before,after,_,code=defect;h['change'](tree/'lib/platform/esp32-smp-crypto.flex',fn,lambda body:h['once'](body,before,after))
   fixture=('s3-' if s3 else '')+('smp-crypto-errors-xip.flex' if error else 'smp-crypto-xip.flex')
   peer=(a.s3_errors if s3 else a.errors) if error else (a.s3 if s3 else a.original)
   out=w/name/'run';log=w/name/'execution.log'
   cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',a.s3_prefix if s3 else a.prefix,'--chip',chip,'--extra',peer,'--assembly',a.vectors_object,'--xip','yes','--source',tree/'tests/esp32'/fixture,'--work',out]
   with log.open('w') as stream:q=subprocess.run(list(map(str,cmd)),cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
   text=log.read_text()
   if defect:
    marker=('SMP PROVIDER ERROR FAIL ' if error else 'SMP PROVIDER FAIL ')+f'{code:016x}';assert q.returncode==1 and marker in text,(name,q.returncode,text[-1500:]);assert 'SHUTDOWN' in (out/'qmp-failure.log').read_text()
   else:assert q.returncode==0 and ('PASS: SMP real vendor/C error ABI ' if error else 'PASS: SMP Xtensa real vendor AES, ') in text,(name,q.returncode,text[-1500:])
   cases.append(dict(name=name,defect=bool(defect),log=str(log),log_sha256=sha(log)));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,positive_boots=4,defects=12,cases=cases,source_sha256=manifest,
  tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,a.original,a.s3,a.errors,a.s3_errors,a.vectors_object,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
 print('PASS:both chips actual AES/typed C errors,4 positive boots,12 provider defects detected')
if __name__=='__main__':main()
