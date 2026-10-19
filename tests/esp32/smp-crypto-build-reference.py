#!/usr/bin/env python3
"""Verify pinned AES packaging, namespaces, reproducibility and input aliases."""
import argparse,hashlib,json,os,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['builder','archive','prefix','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp');source=w/'source'
 for n in ['lib/platform/esp32-smp-mbedtls-config.h','tests/esp32/abi-oracle/smp-crypto-profile.c']:
  dest=source/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,dest)
 archive=Path(a.archive).resolve();builder=Path(a.builder).resolve();rejections=[]
 def command(out,archive_path=archive,chip='esp32'):return [builder,'--archive',archive_path,'--output',out,'--prefix',a.prefix,'--chip',chip]
 def run(cmd,name,expected=0):
  q=subprocess.run(list(map(str,cmd)),cwd=source,env=env,capture_output=True,timeout=60);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==expected,(name,q.returncode,q.stdout,q.stderr);return (q.stdout+q.stderr).decode()
 names=['libsmpcrypto.a','flexscript-smp-crypto.json','LICENSE'];good=w/'good';run(command(good),'build')
 before={n:sha(good/n) for n in names};run(command(good),'repeat');assert all(sha(good/n)==v for n,v in before.items())
 manifest=json.loads((good/names[1]).read_text());assert manifest['archive_sha256']==sha(good/names[0]) and manifest['context_size']==184 and manifest['context_alignment']==4 and manifest['context_capacity']==256 and manifest['key_bits']==128 and manifest['namespace']=='smp_vendor_' and manifest['chip']=='esp32'
 symbols=run([a.prefix+'nm','-g','--defined-only',good/names[0]],'symbols');defined=re.findall(r'^[0-9a-fA-F]+\s+\w\s+(\S+)$',symbols,re.M)
 assert defined and all(s.startswith('smp_vendor_') for s in defined)
 assert all('smp_vendor_mbedtls_aes_'+n in defined for n in ['init','free','setkey_enc','crypt_ecb'])
 def reject(out,name,cmd,message):
  out.mkdir(parents=True,exist_ok=True)
  for n in names:
   path=out/n
   if not path.exists():path.write_bytes(b'preserve existing '+n.encode())
  paths=[out/n for n in names];before={str(p):sha(p) for p in paths};text=run(cmd,name,1);assert message in text,(name,text);assert all(sha(p)==v for p,v in before.items());rejections.append(name)
 bad=w/'wrong-source.tar.bz2';bad.write_bytes(b'wrong archive')
 reject(w/'bad-source','bad-source',command(w/'bad-source',bad),'pinned official')
 reject(w/'bad-chip','bad-chip',command(w/'bad-chip',chip='esp32c3'),'chip must be')
 for index,n in enumerate(names):
  for link in ['symlink','hardlink']:
   out=w/('alias-archive-'+str(index)+'-'+link);out.mkdir();owned=out/'source.tar.bz2';shutil.copyfile(archive,owned)
   if link=='symlink':(out/n).symlink_to(owned)
   else:os.link(owned,out/n)
   digest=sha(owned);reject(out,out.name,command(out,owned),'output aliases input');assert sha(owned)==digest
 for left,right in [(0,1),(0,2),(1,2)]:
  out=w/f'alias-outputs-{left}-{right}';out.mkdir();shared=out/'owned.bin';shared.write_bytes(b'preserve shared payload');(out/names[left]).symlink_to(shared);(out/names[right]).symlink_to(shared)
  reject(out,out.name,command(out),'outputs alias each other')
 for index,n in enumerate(['lib/platform/esp32-smp-mbedtls-config.h','tests/esp32/abi-oracle/smp-crypto-profile.c']):
  out=w/f'alias-configuration-{index}';out.mkdir();(out/names[index]).symlink_to(source/n);before=sha(source/n)
  reject(out,out.name,command(out),'output aliases input');assert sha(source/n)==before
 (w/'report.json').write_text(json.dumps(dict(pass_all=True,rejections=rejections,archive_sha256=sha(good/names[0]),manifest=manifest,defined_symbols=defined,input_archive_sha256=sha(archive),builder_sha256=sha(builder),source_sha256={n:sha(source/n) for n in ['lib/platform/esp32-smp-mbedtls-config.h','tests/esp32/abi-oracle/smp-crypto-profile.c']}),indent=2)+'\n')
 print('PASS: deterministic pinned AES package,isolated namespace,13 rejected inputs/aliases preserve every output')
if __name__=='__main__':main()
