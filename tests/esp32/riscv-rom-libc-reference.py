#!/usr/bin/env python3
"""Pinned ROM C ABI/table/legacy-stat validation; stock C3 execution, optional C6 execution.
C3 common-cell addresses are decoded from the actual checked ROM initializer.
"""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();cases=[];rejections=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 provenance=json.loads((ref/'rom-libc-provenance.json').read_text())
 for row in provenance['sources']:assert sha(ref/row['path'])==row['sha256']
 def run(args,reject=False):
  r=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60);assert (r.returncode!=0 if reject else r.returncode==0),(args,r.stdout,r.stderr);return r
 def symbol(text,name):return int(re.search(r'\b'+re.escape(name)+r'\s*=\s*(0x[0-9a-fA-F]+)',text)[1],16)
 rom=a.qemu.resolve().parent.parent/'share/qemu/esp32c3-rom.bin';data=rom.read_bytes();assert struct.unpack_from('<I',data,16)[0]==5
 w=struct.unpack_from('<I',data,0x350)[0];assert w&0xfff==0x06f;delta=((w>>31)<<20)|(((w>>12)&255)<<12)|(((w>>20)&1)<<11)|(((w>>21)&1023)<<1);delta=delta-(1<<21) if delta&(1<<20) else delta;body=0x350+delta;common=[]
 for at in [body+2,body+12]:
  upper,store=struct.unpack_from('<2I',data,at);assert upper&0xfff==0x7b7 and store&0x1fff07f==0xe7a023;low=((store>>25)<<5)|((store>>7)&31);low=low-4096 if low&2048 else low;common.append((upper&0xfffff000)+low)
 linker=work/'linker';run(['nice','-n','19',compiler,'scripts/esp32-link.flex','-o',linker]);config={}
 for chip in [3,6]:
  name='esp32c'+str(chip);directory=work/name;directory.mkdir(exist_ok=True);(directory/'rom').mkdir(exist_ok=True);header=ref/f'components/esp_rom/{name}/include/{name}/rom/libc_stubs.h';(directory/'rom/libc_stubs.h').write_bytes(header.read_bytes());suffix='.rom.newlib-nano.ld' if chip==3 else '.rom.newlib-normal.ld';ld='\n'.join((ref/f'components/esp_rom/{name}/ld/{name}{s}').read_text() for s in ['.rom.libc.ld','.rom.newlib.ld',suffix]);slots={n:symbol(ld,n) for n in ['syscall_table_ptr','_global_impure_ptr','esp_rom_newlib_init_common_mutexes']};aliases=directory/'rom-alias.ld';aliases.write_text(''.join('rom_'+n+' = '+hex(symbol(ld,n))+';\n' for n in ['strdup','strtol','printf']));(directory/'rom-probe-config.h').write_text(f'#define ROM_GLOBAL_SLOT {slots["_global_impure_ptr"]:#x}\n#define CODE_BEGIN {0x40380000 if chip==3 else 0x40800000:#x}\n#define ROM_STAT_32 {int(chip==3)}\n#define ROM_HAS_COMMON_FIXTURE {int(chip==3)}\n#define ROM_COMMON_0 {common[0] if chip==3 else 0:#x}\n#define ROM_COMMON_1 {common[1] if chip==3 else 0:#x}\n');config[chip]=(directory,aliases,slots)
 def object_table(elf):
  raw=elf.read_bytes();off=struct.unpack_from('<I',raw,32)[0];count=struct.unpack_from('<H',raw,48)[0];sections=[struct.unpack_from('<10I',raw,off+i*40) for i in range(count)];syms={}
  for s in sections:
   if s[1]!=2:continue
   pool_sec=sections[s[6]];pool=raw[pool_sec[4]:pool_sec[4]+pool_sec[5]]
   for at in range(s[4],s[4]+s[5],16):
    n,v,size,info,other,index=struct.unpack_from('<IIIBBH',raw,at);syms[pool[n:pool.index(0,n)].decode()]=(v,size,info,index)
  chip3=syms['syscall_table_ptr'][0]==0x3fcdffe0;assert syms['syscall_table_ptr']==((0x3fcdffe0 if chip3 else 0x4087ffd4),4,17,65521);assert syms['esp_rom_newlib_init_common_mutexes']==((0x40000350 if chip3 else 0x400004a4),0,18,65521)
  value,size,info,index=syms['flex_rom_syscalls'];assert (size,info)==(160,17) and not value%4;s=sections[index];offset=s[4]+value-s[3];table=struct.unpack_from('<40I',raw,offset);assert table[34:36]==(0,0) and table[39]==0xbb10c433
  for i,v in enumerate(table[:39]):
   if i not in (34,35):assert v and v&1==0
  assert table[0]==syms['__getreent'][0] and table[14]==syms['esp_libc_rom_fstat'][0] and table[21]==syms['_write_r'][0] and table[38]==syms['esp_libc_stdio_cleanup'][0]
  return dict(address=value,size=size,callbacks=list(table[:39]),magic=table[39])
 def boot(name,text,chip,objects=(),trap=False,poison=False,words=False):
  directory,aliases,slots=config[chip];prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json');mapping=Path(str(prefix)+'.map');text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000')
  text=re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M);source.write_text(text);run(['nice','-n','19',compiler,'--target',f'esp32c{chip}-elf',source,'-o',elf]);cmd=[linker,'--ld',a.ld,'--newlib-stdio','--newlib-rom','--firmware',elf,'--archive',ref/'riscv-libc.a','--archive',ref/'riscv-libgcc.a','--rom',aliases,'--output',linked,'--image',image,'--map',mapping]
  for obj in objects:cmd+=['--object',obj]
  run(cmd);table=object_table(linked);cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if poison:cmd+=['--expect-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':256:0xa5']
   if words:cmd+=['--words']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,ROM_table=table,trap_expected=trap,poison_unchanged_checked=poison and (chip==3 or a.execute_c6))
  if (chip==3 or a.execute_c6) and name.startswith(('cooperative-','preempt-')):
   lines=row['uart'].split(('entry 0x40380080\r\n' if chip==3 else 'entry 0x40800080\r\n'),1)[1].splitlines();assert len(lines)==24 and lines.count('ROMW1:A')==12 and lines.count('ROMW2:B')==12,row['uart'];row['exact_ROM_output_lines']=24
  cases.append(row);return source,elf
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-I',ref/'components/newlib/platform_include','-I',ref/'riscv-newlib','-I',ref]
 saved={}
 for march in ['rv32im_zicsr','rv32imc_zicsr']:
  for opt in ['-O0','-O2','-Os']:
   for chip in [3,6]:
    directory,aliases,slots=config[chip];tag=f'{march}{opt}-c{chip}';obj=work/(tag+'.o');stat=work/(tag+'-stat.o');run(['nice','-n','19',*flags,'-I',directory,'-march='+march,opt,'-c',root/'tests/esp32/riscv-rom-libc.c','-o',obj]);cmd=['nice','-n','19',*flags,'-I',directory,'-march='+march,opt,'-c',root/'tests/esp32/riscv-rom-libc-stat.c','-o',stat]
    if chip==3:cmd+=['-D_USE_LONG_TIME_T']
    run(cmd);saved[chip]=(obj,stat)
    for case,fixture in [('cooperative','riscv-rom-libc'),('preempt','riscv-rom-libc-preempt')]:boot(case+'-'+march+opt,(root/'tests/esp32'/(fixture+'.flex')).read_text(),chip,[obj,stat])
 for case in ['guards','late']:
  for chip in [3,6]:boot(case,(root/'tests/esp32'/('riscv-rom-libc-'+case+'.flex')).read_text(),chip)
 for chip in [3,6]:
  directory,aliases,slots=config[chip];obj=work/f'peer-c{chip}.o';run(['nice','-n','19',*flags,'-I',directory,'-march=rv32imc_zicsr','-Os','-c',root/'tests/esp32/riscv-rom-libc-peer.c','-o',obj]);boot('table-UART-peer',(root/'tests/esp32/riscv-rom-libc-peer.flex').read_text(),chip,[obj],words=True)
 setup='''import "../../lib/platform/esp32c3-libc-rom.flex";
 fn rom_pause(a,b,c,d,e,f,g,h){return 0;}
 fn main(){let guard=alloc(256);let i=0;while i<256{store8(guard+i,165);i=i+1;}if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init()||esp_libc_rom_init(){return 1;}esp32_callback32(rom_pause);
 '''
 for name,which in [('close-ROM-common',0),('unexpected-ROM-sinit',1),('ROM-raise',2),('ROM-exit',3),('ROM-assert',4)]:
  for chip in ([3] if which==0 else [3,6]):boot(name,setup+f'return esp32_call32(esp32_external("rom_bad"),{which},0,0,0,0,0,0,0);}}',chip,saved[chip],trap=True,poison=True)
 for which in [5,6]:
  text='''import "../../lib/platform/esp32c3-irq.flex";
 '''+setup.replace('fn main(){','fn bad_irq(source){return esp32_call32(esp32_external("rom_bad"),'+str(which)+',0,0,0,0,0,0,0);}fn main(){')+'esp_irq_software(esp32_callback(bad_irq));esp32_irq_raise(128);esp_irq_enable();return 99;}'
  for chip in [3,6]:boot('ISR-ROM-'+str(which),text,chip,saved[chip],trap=True,poison=True)
 # The static table is an explicit profile, never silently supplied for other ELFs.
 source,elf=boot('profile-rejection-base',(root/'tests/esp32/riscv-rom-libc-guards.flex').read_text(),3)
 for name,args in [('missing-ROM-profile',['--newlib-stdio']),('missing-stdio-profile',['--newlib-rom'])]:
  outputs=[work/(name+s) for s in ['.elf','.bin','.map']]
  for f in outputs:f.write_bytes(b'preserve output')
  result=run([linker,'--ld',a.ld,'--firmware',elf,'--archive',ref/'riscv-libc.a','--output',outputs[0],'--image',outputs[1],'--map',outputs[2],*args],reject=True);assert all(f.read_bytes()==b'preserve output' for f in outputs);rejections.append(dict(case=name,preserved_outputs=3,error=result.stderr))
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),C3_ROM_image_sha256=sha(rom),C3_ROM_ECO=struct.unpack_from('<I',data,20)[0],C3_ROM_common_cells=common,C6_ROM_common_cell_fixture_available=False,C3_common_initializer_body_offset=body,physical_hardware=False,feature_complete=False,goal_status='active',cases=cases,rejections=rejections)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: ROM libc',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages,',report['C3_poison_unchanged_checks'],'guards')
if __name__=='__main__':main()
