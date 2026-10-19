#!/usr/bin/env python3
"""Detect independent SMP crypto packing, cleanup and admission defects."""
import argparse,hashlib,json,os,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','large','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-crypto-native.flex',base)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('CMAC-wrong-polynomial','smp_double','^0x87','^0x1b'),
  ('CMAC-full-block-uses-K2','smp_cmac','if size && last==16','if 0'),
  ('CMAC-missing-padding','smp_cmac','store8(work+64+last,128)','store8(work+64+last,0)'),
  ('f4-public-key-byte-order','smp_f4','smp_reverse(work+112,u,32)','nb_copy(work+112,u,32)'),
  ('f5-wrong-salt','smp_f5','0x38a5f5aa9183886c','0x38a5f5aa9183886d'),
  ('f5-repeated-counter','smp_f5','store8(work+112,1)','store8(work+112,0)'),
  ('f5-wrong-key-length','smp_f5','store8(work+163,1)','store8(work+163,0)'),
  ('f5-key-partially-published','smp_f5','r=smp_cmac(work+256,work+112,53,work+288','smp_reverse(out,work+272,16);r=smp_cmac(work+256,work+112,53,work+288'),
  ('f6-IOcap-byte-order','smp_f6','smp_reverse(work+160,io,3)','nb_copy(work+160,io,3)'),
  ('g2-high-instead-of-low-word','smp_g2','smp_reverse(out,work+252,4)','smp_reverse(out,work+240,4)'),
  ('h6-keyID-byte-order','smp_h6','smp_reverse(work+112,id,4)','nb_copy(work+112,id,4)'),
  ('h7-salt-confused-with-key','smp_h7','smp_reverse(work+96,salt,16)','smp_reverse(work+96,key,16)'),
  ('legacy-c1-initiator-type','smp_c1','store8(work+304,load8(a1))','store8(work+304,load8(a2))'),
  ('legacy-c1-responder-address','smp_c1','load8(a2+1+i)','load8(a1+1+i)'),
  ('legacy-s1-wrong-nonce-half','smp_s1','nb_copy(work+304,r2,8)','nb_copy(work+304,r2+8,8)'),
  ('address-hash-wrong-octets','smp_ah','nb_copy(out,work+320,3)','nb_copy(out,work+333,3)'),
  ('derivation-scratch-not-wiped','smp_done','nb_zero(work,512);',''),
  ('scratch-capacity-off-by-one','smp_output','capacity>=512','capacity>=511'),
  ('confirmation-accepts-mismatch','smp_equal','return difference==0;','return 1;'),
  ('legacy-AES-byte-order','smp_e_work','smp_reverse(work+112,input,16)','nb_copy(work+112,input,16)'),
  ('f5-MacKey-LTK-swapped','smp_f5','smp_reverse(out,work+272,16);smp_reverse(out+16,work+288,16);','smp_reverse(out,work+288,16);smp_reverse(out+16,work+272,16);'),
 ]
 cases=[]
 for change in [None]+changes+[('CMAC-error-scratch-not-wiped','smp_cmac',None,None)]:
  name=change[0] if change else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if change:
   _,fn,before,after=change
   if before is None:
    def damage(body):
     old='if r {nb_zero(work,96);return r;}';assert body.count(old)==2;return body.replace(old,'if r {return r;}')
   else:
    def damage(body):return h['once'](body,before,after)
   h['change'](tree/'lib/net/smp-crypto.flex',fn,damage)
  exe=w/name/'native';q=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-crypto-native.flex'),'-o',str(exe)],cwd=ROOT,env=env,capture_output=True,timeout=30)
  (w/name/'compile.log').write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout,q.stderr)
  q=subprocess.run([str(exe),a.vectors,a.large],cwd=ROOT,env=env,capture_output=True,timeout=15);log=w/name/'execution.log';log.write_bytes(q.stdout+q.stderr)
  if change:assert 1<=q.returncode<=10 and b'SMP CRYPTO FAIL case=' in q.stderr,(name,q.returncode,q.stdout,q.stderr)
  else:assert q.returncode==0 and q.stdout==b'PASS: SMP native crypto 1892 checks\n',(name,q.returncode,q.stdout,q.stderr)
  cases.append(dict(name=name,detected=bool(change),exit_code=q.returncode,log_sha256=sha(log)));print(name,flush=True)
 assert all(sha(ROOT/n)==v for n,v in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,checks=1892,defects=len(changes)+1,cases=cases,source_sha256=manifest,compiler_sha256=sha(a.compiler),vectors_sha256=sha(a.vectors),large_vectors_sha256=sha(a.large),physical_hardware=False),indent=2)+'\n')
 print('PASS:1892 independent checks;22 isolated SMP cryptographic/cleanup defects detected')
if __name__=='__main__':main()
