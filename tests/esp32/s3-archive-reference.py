#!/usr/bin/env python3
"""Verify the explicit S3 archive builder, real ROM boot and rejected inputs.

Runs only the existing stock QEMU. Alias tests use copied source/manifests;
neither physical devices nor canonical pin files are modified by the tests.
"""
import argparse,hashlib,json,os,re,runpy,shutil,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 for k in ['compiler','vendor','rom','prefix','qemu','work']:p.add_argument('--'+k,required=True)
 a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
 (w/'tmp').mkdir(exist_ok=True);env=os.environ.copy();env['TMPDIR']=str(w/'tmp')
 compiler=Path(a.compiler).resolve();vendor=Path(a.vendor).resolve();rom=Path(a.rom).resolve();qemu=Path(a.qemu).resolve();helper=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));tree=w/'source';manifest={}
 for n in ['scripts/build-esp32-radio.flex','scripts/esp32-link.flex','scripts/esp32-data-object.flex','scripts/lib/esp32-test.flex','examples/esp32s3-vendor-probe.flex']:manifest.update(helper['copy_closure'](ROOT/n,tree))
 for n in ['docs/esp32-vendor-sha256.txt','docs/esp32s3-vendor-sha256.txt','docs/esp32s3-rom-sha256.txt']:
  d=tree/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,d);manifest[n]=sha(d)
 def run(args,name,ok=0,cwd=tree):
  r=subprocess.run(list(map(str,args)),cwd=cwd,env=env,capture_output=True,timeout=60);text=(r.stdout+r.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text);assert r.returncode==ok,(name,r.returncode,text[-2000:]);return text
 builder=w/'build-radio';run([compiler,tree/'scripts/build-esp32-radio.flex','-o',builder],'builder')
 output=w/'probe.bin'
 def args(out=output,vendor_dir=vendor,rom_dir=rom,chip='esp32s3',source=None,exe=compiler,libgcc=None):
  result=[builder,'--chip',chip,'--compiler',exe,'--vendor',vendor_dir,'--rom',rom_dir,'--output',out,'--ld',a.prefix+'ld','--gcc',a.prefix+'gcc']
  if source:result+=['--source',source]
  if libgcc:result+=['--libgcc',libgcc]
  return result
 run(args(),'build-probe');elf=runpy.run_path(str(ROOT/'tests/esp32/s3-sdk-reference.py'))['elf'];data,sections,profile=elf(str(output)+'.elf')
 assert profile==(1,9,0x40380000,0x3fca8000,0x3fcd0000,0x3fcd8000,0x3fcb0000,0x3fcb2000),profile
 assert sections['.text']['address']==profile[2] and sections['.text']['size']<=98304
 assert sections['.data']['address']==profile[3] and sections['.data']['size']<=32768
 assert profile[2]+sections['.text']['size']-0x6f0000<=profile[3]
 assert sections['.irom']['address']==0x42000000 and sections['.irom']['size']<=0x300000
 assert sections['.drom']['address']==0x3c400000 and sections['.drom']['size']<=0x300000
 layout=struct.unpack_from('<4I',data,sections['.flex.xip']['offset']);assert layout[0]==0x30000 and layout[1]==(sections['.irom']['size']+65535)//65536 and layout[2]==layout[0]+layout[1]*65536 and layout[3]==(sections['.drom']['size']+65535)//65536
 image=output.read_bytes();assert len(image)==layout[2]+layout[3]*65536<=0x400000
 # This is the actual builder-created storage symbol, not the C fixture table.
 symbols=run([a.prefix+'nm','-S',str(output)+'.elf'],'symbols');match=re.search(r'^([0-9a-f]+)\s+([0-9a-f]+)\s+D\s+g_wifi_osi_funcs$',symbols,re.M);assert match and int(match[2],16)==480
 table=int(match[1],16);assert profile[3]+24<=table and table+480<=profile[6]
 # The ELF's cached payload must be the bytes appended to the ROM image.
 for name,offset in [('.irom',layout[0]),('.drom',layout[2])]:
  s=sections[name];assert data[s['offset']:s['offset']+s['size']]==image[offset:offset+s['size']]
 # Compile the existing native QMP harness; this executes the actual image.
 runner=w/'run.flex';runner.write_text('import '+json.dumps(str(tree/'scripts/lib/esp32-test.flex'))+';fn main(argc,argv){h_environment(argc,argv);te_init(load64(argv+8));te_qemu=load64(argv+16);te_work=load64(argv+24);te_s3_xip=1;te_xip=1;let serial=te_run(load64(argv+32),0,"PASS: S3 actual vendor");h_save(h_join(te_work,"executed.uart"),serial);h_print(1,serial);return 0;}')
 run([compiler,runner,'-o',w/'run'],'runner');run([w/'run',compiler,qemu,w,output],'boot')
 pins={}
 for line in (tree/'docs/esp32s3-vendor-sha256.txt').read_text().splitlines():
  if line and not line.startswith('#'):
   digest,name=line.split();pins[name]=digest
 selected='core pp net80211 phy coexist wpa_supplicant espnow regulatory printf smartconfig wapi mesh'.split();archive_names=['lib'+x+'.a' for x in selected]
 for n in archive_names:assert sha(vendor/n)==pins[n]
 rom_pins={line.split()[1]:line.split()[0] for line in (tree/'docs/esp32s3-rom-sha256.txt').read_text().splitlines() if line and not line.startswith('#')}
 for n,digest in rom_pins.items():assert sha(rom/n)==digest
 rejections=[]
 def reject(command,name,message,out,existing=None):
  paths=[Path(str(out)+s) for s in ['', '.elf','.map']]
  if existing is None:
   for path in paths:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'preserve '+path.name.encode()+b'\n')
  before={str(path):sha(path) for path in paths};text=run(command,name,1);assert message in text,(name,message,text[-1000:]);assert all(sha(path)==before[str(path)] for path in paths),name;rejections.append(name)
 bad=w/'bad-inputs';bad.mkdir()
 for name in archive_names:
  d=bad/name;d.mkdir()
  for n in archive_names:
   if n==name:(d/n).write_bytes(b'wrong chip or corrupted archive\n')
   else:(d/n).symlink_to(vendor/n)
  dest=d/'preserved.bin';reject(args(dest,vendor_dir=d),'archive-'+name,'vendor archive checksum mismatch',dest)
 for name in rom_pins:
  d=bad/name;d.mkdir()
  for n in rom_pins:
   if n==name:(d/n).write_bytes(b'wrong chip or ROM version\n')
   else:(d/n).symlink_to(rom/n)
  dest=d/'preserved.bin';reject(args(dest,rom_dir=d),'rom-'+name,'S3 ROM checksum mismatch',dest)
 for label,extra,message in [('unsupported-chip',['--chip','esp32c3'],'--chip must be'),('S3-bluetooth',['--kind','bluetooth'],'S3 Bluetooth vendor startup'),('S3-TLS',['--tls','not-a-chip-matched-manifest'],'S3 TLS archives are not yet integrated')]:
  dest=bad/(label+'.bin');command=args(dest,chip='esp32c3') if label=='unsupported-chip' else args(dest)+extra;reject(command,label,message,dest)
 # Use owned copies for every alias target. Even a broken guard cannot damage
 # canonical source, archives, compiler or ROM inputs.
 for chip,inventory in [('esp32','docs/esp32-vendor-sha256.txt'),('esp32s3','docs/esp32s3-vendor-sha256.txt'),('esp32s3','docs/esp32s3-rom-sha256.txt')]:
  for suffix in ['', '.elf','.map']:
   label='alias-'+Path(inventory).stem+('-'+suffix[1:] if suffix else '-bin');dest=bad/(label+'.bin');paths=[Path(str(dest)+s) for s in ['', '.elf','.map']]
   for path in paths:path.write_bytes(b'preserve output\n')
   alias=Path(str(dest)+suffix);alias.unlink();alias.symlink_to(tree/inventory)
   reject(args(dest,chip=chip),label,'radio output aliases input',dest,True)
 # Verify source, compiler, archive, ROM and libgcc alias detection with copies.
 original_lib=Path(subprocess.check_output([a.prefix+'gcc','-print-libgcc-file-name'],text=True).strip());targets=[('source',tree/'examples/esp32s3-vendor-probe.flex'),('archive',vendor/archive_names[0]),('ROM',rom/next(iter(rom_pins))),('compiler',compiler),('libgcc',original_lib)]
 for label,original in targets:
  target=bad/(label+'-input');shutil.copy2(original,target);dest=bad/(label+'-alias.bin');paths=[Path(str(dest)+s) for s in ['', '.elf','.map']]
  for path in paths:path.write_bytes(b'preserve output\n')
  dest.unlink();dest.symlink_to(target)
  if label=='source':command=args(dest,source=target)
  elif label=='compiler':command=args(dest,exe=target)
  elif label=='libgcc':command=args(dest,libgcc=target)
  elif label=='ROM':
   d=bad/'alias-ROM-inputs';d.mkdir()
   for n in rom_pins:(d/n).symlink_to(target if n==next(iter(rom_pins)) else rom/n)
   command=args(dest,rom_dir=d)
  else:
   d=bad/'alias-archive-inputs';d.mkdir()
   for n in archive_names:(d/n).symlink_to(target if n==archive_names[0] else vendor/n)
   command=args(dest,vendor_dir=d)
  reject(command,'input-alias-'+label,'radio output aliases input',dest,True)
 assert all(sha(ROOT/n)==digest for n,digest in manifest.items())
 report=dict(pass_all=True,chip='esp32s3',compiler_sha256=sha(compiler),qemu_sha256=sha(qemu),source_sha256=manifest,selected_archives={n:pins[n] for n in archive_names},ROM_pins=rom_pins,ELF_sha256=sha(str(output)+'.elf'),image_sha256=sha(output),UART_sha256=sha(w/'executed.uart'),image_bytes=len(image),sections={n:sections[n] for n in ['.text','.data','.irom','.drom']},OSI_object_bytes=480,MMU_layout=layout,rejections=rejections,actual_vendor_code_executed=True,vendor_API_init_called=False,controller_reserved_memory_verified=False,physical_hardware=False,RF_verified=False,emulator_implementation_changes=False)
 (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: actual S3 archive code ROM boot;480-byte OSI;{len(rejections)} preserved-output rejections',flush=True)
if __name__=='__main__':main()
