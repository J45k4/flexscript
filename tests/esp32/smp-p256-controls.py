#!/usr/bin/env python3
"""Verify independent P-256 corpus detects wire-order/atomicity/cleanup defects."""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vectors','provider','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();v=Path(a.vectors).resolve();vr=json.loads((v/'report.json').read_text());provider=Path(a.provider).resolve();h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=h['copy_closure'](ROOT/'tests/esp32/smp-p256-native.flex',base);(w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 changes=[
  ('private-scalar-not-reversed','p256_public','p256_reverse(work,private,32);','nb_copy(work,private,32);'),
  ('public-X-not-wire-order','p256_public','p256_reverse(out,work+96,32);','nb_copy(out,work+96,32);'),
  ('public-Y-not-wire-order','p256_public','p256_reverse(out+32,work+128,32);','nb_copy(out+32,work+128,32);'),
  ('peer-X-and-Y-swapped','p256_shared','p256_reverse(work+32,peer,32);p256_reverse(work+64,peer+32,32);','p256_reverse(work+32,peer+32,32);p256_reverse(work+64,peer,32);'),
  ('DHKey-not-wire-order','p256_shared','p256_reverse(out,work+96,32);','nb_copy(out,work+96,32);'),
  ('public-key-check-not-reversed','p256_validate','p256_reverse(work,peer,32);','nb_copy(work,peer,32);'),
  ('generated-private-not-wire-order','p256_keypair','p256_reverse(out,work,32);','nb_copy(out,work,32);'),
  ('generated-public-X-and-Y-swapped','p256_keypair','p256_reverse(out+32,work+32,32);p256_reverse(out+64,work+64,32);','p256_reverse(out+32,work+64,32);p256_reverse(out+64,work+32,32);'),
  ('scratch-not-cleared','p256_finish','nb_zero(work,256);',''),
  ('failed-public-operation-publishes','p256_public','if !r {','if 1 {'),
  ('failed-shared-operation-publishes','p256_shared','if !r {','if 1 {'),
  ('failed-generation-publishes-private','p256_keypair','if !r {','if 1 {'),
  ('scratch-input-alias-accepted','p256_area',' && !p256_overlap(p,n,work,256)',''),
  ('insufficient-scratch-accepted','p256_work','capacity>=256','capacity>=255'),
  ('provider-preflight-skipped','p256_validate','let r=smp_p256_ready(work,256);','let r=0;'),
 ]
 results=[]
 for item in [None]+changes:
  name=item[0] if item else 'protected';tree=w/name/'source';shutil.copytree(base,tree)
  if item:
   _,fn,before,after=item;h['change'](tree/'lib/net/smp-p256.flex',fn,lambda body:h['once'](body,before,after))
  exe=w/name/'native';c=subprocess.run([a.compiler,str(tree/'tests/esp32/smp-p256-native.flex'),'-o',str(exe)],cwd=tree,env=env,capture_output=True,timeout=30);(w/name/'compile.log').write_bytes(c.stdout+c.stderr);assert c.returncode==0,(name,c.stdout,c.stderr);parts=[];detected=False
  for i,part in enumerate(vr['parts']):
   data=v/part['file'];assert sha(data)==part['sha256'];r=subprocess.run([str(exe),str(data),str(provider)],cwd=tree,env=env,capture_output=True,timeout=60);log=w/name/f'part-{i}.log';log.write_bytes(r.stdout+r.stderr);parts.append(dict(part=i,log_sha256=sha(log)))
   if r.returncode:assert item and r.returncode==8 and b'SMP P256 FAIL case=' in r.stderr,(name,r.returncode,r.stdout,r.stderr);detected=True;break
   assert re.fullmatch(rb'PASS: SMP P256 \d+ independent observations\n',r.stdout),(name,r.stdout,r.stderr)
  assert detected==bool(item),name;results.append(dict(name=name,detected=detected,parts=parts));print(name,flush=True)
 assert all(sha(ROOT/n)==h for n,h in manifest.items())
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,defects=len(changes),cases=results,source_sha256=manifest,compiler_sha256=sha(a.compiler),provider_sha256=sha(provider),vectors_sha256=sha(v/'report.json')),indent=2)+'\n');print('PASS:',len(changes),'P-256 wire/cleanup/atomicity defects detected')
if __name__=='__main__':main()
