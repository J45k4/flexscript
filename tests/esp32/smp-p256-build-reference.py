#!/usr/bin/env python3
"""Verify deterministic P-256 packaging and rejected input/output aliases."""
import argparse,hashlib,json,os,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['builder','archive','prefix','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists();source=w/'source';names=['libsmpcurve.a','flexscript-smp-curve.json','LICENSE','p256-m.h','p256-m.README.md'];inputs=['lib/platform/esp32-smp-p256-config.h','tests/esp32/abi-oracle/smp-p256-profile.c']
 for n in inputs:d=source/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,d)
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');archive=Path(a.archive).resolve();builder=Path(a.builder).resolve();rejections=[]
 def command(out,src=archive,chip='esp32'):return [builder,'--archive',src,'--output',out,'--prefix',a.prefix,'--chip',chip]
 def run(cmd,name,expected=0):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=60);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==expected,(name,q.returncode,q.stdout,q.stderr);return (q.stdout+q.stderr).decode()
 good=w/'good';run(command(good),'build');before={n:sha(good/n) for n in names};run(command(good),'repeat');assert all(sha(good/n)==h for n,h in before.items());manifest=json.loads((good/names[1]).read_text());assert manifest['archive_sha256']==sha(good/names[0]) and manifest['namespace']=='smp_curve_vendor_' and manifest['private_bytes']==32 and manifest['public_bytes']==64 and manifest['shared_bytes']==32 and manifest['heap_allocation'] is False
 text=run([a.prefix+'nm','-g','--defined-only',good/names[0]],'defined');defined=re.findall(r'^[0-9a-fA-F]+\s+\w\s+(\S+)$',text,re.M);assert defined and all(x.startswith('smp_curve_vendor_') for x in defined)
 for n in ['p256_gen_keypair','p256_ecdh_shared_secret','p256_public_from_private','p256_validate_pubkey','p256_validate_privkey']:assert 'smp_curve_vendor_'+n in defined,n
 text=run([a.prefix+'nm','-u',good/names[0]],'undefined');undefined=set(re.findall(r'\bU\s+(\S+)',text));assert undefined=={'smp_curve_vendor_mbedtls_platform_zeroize','smp_curve_vendor_psa_generate_random'},undefined
 def reject(out,name,cmd,message):
  out.mkdir(parents=True,exist_ok=True)
  for n in names:
   path=out/n
   if not path.exists():path.write_bytes(b'preserve '+n.encode())
  before={n:sha(out/n) for n in names};text=run(cmd,name,1);assert message in text,(name,text);assert all(sha(out/n)==h for n,h in before.items());rejections.append(name)
 bad=w/'bad.tar.bz2';bad.write_bytes(b'wrong pinned input');reject(w/'bad-source','bad-source',command(w/'bad-source',bad),'pinned official');reject(w/'bad-chip','bad-chip',command(w/'bad-chip',chip='esp32c3'),'chip must be')
 for i,n in enumerate(names):
  for link in ['symlink','hardlink']:
   out=w/f'input-alias-{i}-{link}';out.mkdir();owned=out/'owned.tar.bz2';shutil.copyfile(archive,owned)
   if link=='symlink':(out/n).symlink_to(owned)
   else:os.link(owned,out/n)
   digest=sha(owned);reject(out,out.name,command(out,owned),'output aliases input');assert sha(owned)==digest
 for i in range(len(names)):
  for j in range(i+1,len(names)):
   out=w/f'output-alias-{i}-{j}';out.mkdir();owned=out/'owned';owned.write_bytes(b'preserve output target');(out/names[i]).symlink_to(owned);(out/names[j]).symlink_to(owned);reject(out,out.name,command(out),'outputs alias each other')
 for i,n in enumerate(inputs):
  out=w/f'configuration-alias-{i}';out.mkdir();(out/names[i]).symlink_to(source/n);digest=sha(source/n);reject(out,out.name,command(out),'output aliases input');assert sha(source/n)==digest
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,rejections=rejections,manifest=manifest,defined_symbols=defined,undefined_symbols=sorted(undefined),builder_sha256=sha(builder),input_archive_sha256=sha(archive),source_sha256={n:sha(source/n) for n in inputs}),indent=2)+'\n');print('PASS: deterministic isolated P-256 package;',len(rejections),'rejections preserve all outputs')
if __name__=='__main__':main()
