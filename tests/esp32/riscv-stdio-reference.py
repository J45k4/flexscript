#!/usr/bin/env python3
"""Pinned newlib stdio through C3 ROM, exact UART peers and optional C6 execution.
No compiler/library downloads or custom CPU emulation are performed here.
"""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args()
 root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();cases=[];rejections=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 provenance=json.loads((ref/'riscv-libc-provenance.json').read_text());assert sha(ref/'riscv-libc.a')==provenance['selected_newlib_archive']['sha256'];assert sha(ref/'riscv-libgcc.a')==json.loads((ref/'riscv-libgcc-provenance.json').read_text())['sha256']
 for path,digest in provenance['target_header_sha256'].items():assert sha(ref/'riscv-newlib'/path)==digest,path
 def run(args,reject=False):
  r=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60)
  assert (r.returncode!=0 if reject else r.returncode==0),(args,r.stdout,r.stderr)
  return r
 linker=work/'linker';run(['nice','-n','19',compiler,'scripts/esp32-link.flex','-o',linker])
 def objects(elf):
  data=elf.read_bytes();shoff=struct.unpack_from('<I',data,32)[0];count=struct.unpack_from('<H',data,48)[0];sections=[struct.unpack_from('<10I',data,shoff+i*40) for i in range(count)];symbols={}
  for section in sections:
   if section[1]!=2:continue
   strings=sections[section[6]];pool=data[strings[4]:strings[4]+strings[5]]
   for at in range(section[4],section[4]+section[5],16):
    n,value,size,info,other,index=struct.unpack_from('<IIIBBH',data,at);name=pool[n:pool.index(0,n)].decode();symbols[name]=(value,size,info,index)
  names=['_impure_data']+['__lock___'+n+'_mutex' for n in ['sinit_recursive','malloc_recursive','env_recursive','sfp_recursive','atexit_recursive','at_quick_exit','tz','dd_hash','arc4random']]
  for i,name in enumerate(names):
   value,size,info,index=symbols[name];assert size==(240 if i==0 else 84) and info==17 and not value%4 and index>0,(name,symbols[name])
  return {n:symbols[n][:3] for n in names}
 def boot(name,text,chip,obj=None,trap=False,poison=False,words=False):
  prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json');linkmap=Path(str(prefix)+'.map')
  text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000')
  text=re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M);source.write_text(text)
  run(['nice','-n','19',compiler,'--target',f'esp32c{chip}-elf',source,'-o',elf]);cmd=[linker,'--ld',a.ld,'--newlib-stdio','--firmware',elf,'--archive',ref/'riscv-libc.a','--archive',ref/'riscv-libgcc.a','--output',linked,'--image',image,'--map',linkmap]
  if obj:cmd+=['--object',obj]
  run(cmd);definitions=objects(linked);mapping=linkmap.read_text();assert 'libc_a-findfp.o' in mapping and 'libc_a-impure.o' not in mapping
  if name.startswith('format-'):assert 'libc_a-vfprintf.o' in mapping and 'libc_a-svfprintf.o' in mapping
  if name.startswith(('streams-','preempt-')):assert 'libc_a-fmemopen.o' in mapping and 'libc_a-reent.o' in mapping
  cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if poison:cmd+=['--expect-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':256:0xa5']
   if words:cmd+=['--words']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,trap_expected=trap,poison_unchanged_checked=poison and (chip==3 or a.execute_c6),C_data_objects=definitions)
  if (chip==3 or a.execute_c6) and name.startswith('format-'):assert row['uart'].endswith('STDIO: value=-17/1122334455667788/1.25\n'),row['uart']
  if (chip==3 or a.execute_c6) and name.startswith(('streams-','preempt-')):
   lines=row['uart'].split('STREAMS-BEGIN\n',1)[1].split('STREAMS-END\n',1)[0].splitlines();assert len(lines)==24 and lines.count('W1:done')==12 and lines.count('W2:done')==12,row['uart'];row['exact_uninterleaved_lines']=24
  cases.append(row);return source,elf,obj
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-I',ref/'components/newlib/platform_include','-I',ref/'riscv-newlib','-I',ref]
 for march in ('rv32im_zicsr','rv32imc_zicsr'):
  for opt in ('-O0','-O2','-Os'):
   name=march+opt;fmt=work/('format-'+name+'.o');streams=work/('streams-'+name+'.o')
   for fixture,obj in [('format',fmt),('streams',streams)]:run(['nice','-n','19',*flags,'-march='+march,opt,'-c',root/'tests/esp32'/('riscv-stdio-'+fixture+'.c'),'-o',obj])
   for kind,obj in [('format',fmt),('streams',streams),('preempt',streams)]:
    for chip in (3,6):boot(kind+'-'+name,(root/'tests/esp32'/('riscv-stdio-'+kind+'.flex')).read_text(),chip,obj)
 for kind,obj in [('allocation',None),('native-oom',None),('budget',streams),('peer',streams)]:
  for chip in (3,6):sample=boot(kind,(root/'tests/esp32'/('riscv-stdio-'+kind+'.flex')).read_text(),chip,obj,words=kind=='peer')
 setup='''import "../../lib/platform/esp32c3-libc-stdio.flex";
 fn stdio_pause(a,b,c,d,e,f,g,h){return 0;}
 fn main(){let guard=alloc(256);let i=0;while i<256{store8(guard+i,165);i=i+1;}if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init(){return 1;}esp_libc_posix_bind();esp32_callback32(stdio_pause);
 '''
 for name,which,address in [('close-static',0,'0'),('wrong-static-type',1,'0'),('invalid-FILE',2,'guard+1'),('abort',6,'0')]:
  text=setup+f'return esp32_call32(esp32_external("stdio_bad"),{which},{address},0,0,0,0,0,0);}}'
  for chip in (3,6):boot(name,text,chip,streams,trap=True,poison=True)
 for which in (3,4,5):
  text='''import "../../lib/platform/esp32c3-irq.flex";
 '''+setup.replace('fn main(){','fn bad_irq(source){return esp32_call32(esp32_external("stdio_bad"),'+str(which)+',0,0,0,0,0,0,0);}fn main(){')+'esp_irq_software(esp32_callback(bad_irq));esp32_irq_raise(128);esp_irq_enable();return 99;}'
  for chip in (3,6):boot('ISR-stdio-'+str(which),text,chip,streams,trap=True,poison=True)
 late='''import "../../lib/platform/esp32c3-libc-stdio.flex";
 fn main(){if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_reent_init(){return 1;}let before=esp_sdk_heap_free();if esp_libc_stdio_init()!=-16||esp_sdk_heap_free()!=before{return 2;}return 0;}'''
 for chip in (3,6):boot('reject-profile-migration',late,chip)
 # Missing/wrong profile requests preserve every existing output destination.
 for name,target,stdioflag in [('missing-data-profile','esp32c3-elf',False),('wrong-architecture','esp32-elf',True)]:
  source=work/(name+'.flex');source.write_text((root/'tests/esp32/riscv-stdio-allocation.flex').read_text().replace('../../lib/',str(root/'lib')+'/') if not stdioflag else 'fn main(){return 0;}');elf=work/(name+'.elf');run([compiler,'--target',target,source,'-o',elf]);destinations=[work/(name+suffix) for suffix in ['-out.elf','.bin','.map']]
  for dest in destinations:dest.write_bytes(b'preserve existing output')
  cmd=[linker,'--ld',a.ld,'--firmware',elf,'--archive',ref/'riscv-libc.a','--output',destinations[0],'--image',destinations[1],'--map',destinations[2]]
  if stdioflag:cmd+=['--newlib-stdio']
  result=run(cmd,reject=True);assert all(d.read_bytes()==b'preserve existing output' for d in destinations);rejections.append(dict(case=name,outputs_preserved=3,error=result.stderr))
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),physical_hardware=False,feature_complete=False,goal_status='active',ROM_syscall_table_installed=False,ROM_common_mutexes_installed=False,compiler_sha256=sha(compiler),cases=cases,rejections=rejections)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: pinned stdio',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages,',report['C3_poison_unchanged_checks'],'guards')
if __name__=='__main__':main()
