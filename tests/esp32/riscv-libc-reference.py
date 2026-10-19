#!/usr/bin/env python3
"""Pinned vendor newlib execution through emitted C3 firmware, optional C6 execution.

The target headers/archive are explicit inputs; this test never downloads tools.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args()
 root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();archive=ref/'riscv-libc.a';cases=[];maps=[]
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 provenance=json.loads((ref/'riscv-libc-provenance.json').read_text());assert sha(archive)==provenance['selected_newlib_archive']['sha256']
 for path,digest in provenance['target_header_sha256'].items():assert sha(ref/'riscv-newlib'/path)==digest,path
 def run(args):
  result=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60)
  assert result.returncode==0,(args,result.stdout,result.stderr)
  return result
 linker=work/'linker';run(['nice','-n','19',compiler,'scripts/esp32-link.flex','-o',linker])
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-ftls-model=local-exec','-I',ref/'components/newlib/platform_include','-I',ref/'riscv-newlib','-I',ref]
 def boot(name,text,chip,obj,trap=False,poison=False):
  prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json');linkmap=Path(str(prefix)+'.map')
  text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000')
  text=re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M);source.write_text(text)
  run(['nice','-n','19',compiler,'--target',f'esp32c{chip}-elf',source,'-o',elf]);run([linker,'--ld',a.ld,'--firmware',elf,'--object',obj,'--archive',archive,'--output',linked,'--image',image,'--map',linkmap])
  symbols=linkmap.read_text();required=['libc_a-errno.o','libc_a-strtol.o','libc_a-rand.o','libc_a-strtok.o','libc_a-reent.o'];assert all(x in symbols for x in required),name
  assert 'libc_a-mallocr.o' not in symbols and 'libc_a-impure.o' not in symbols,name
  cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if poison:cmd+=['--expect-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':256:0xa5']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,trap_expected=trap,poison_unchanged_checked=poison and (chip==3 or a.execute_c6),vendor_archive_members=required);cases.append(row);maps.append(str(linkmap))
 for march in ('rv32im_zicsr','rv32imc_zicsr'):
  for opt in ('-O0','-O2','-Os'):
   name=march+opt;obj=work/(name+'.o');run(['nice','-n','19',*flags,'-march='+march,opt,'-c',root/'tests/esp32/riscv-libc.c','-o',obj])
   for fixture in ('riscv-libc','riscv-libc-preempt','riscv-libc-allocation'):
    for chip in (3,6):boot(fixture+'-'+name,(root/'tests/esp32'/(fixture+'.flex')).read_text(),chip,obj)
 for chip in (3,6):boot('task-lifecycle-real-IRQ',(root/'tests/esp32/riscv-task-lifecycle-irq.flex').read_text(),chip,obj)
 for chip in (3,6):boot('invalid-task-handles',(root/'tests/esp32/riscv-task-handles.flex').read_text(),chip,obj)
 setup='''import "../../lib/platform/esp32c3-libc.flex";
 fn libc_pause(a,b,c,d,e,f,g,h){return 0;}
 fn main(){let guard=alloc(256);let i=0;while i<256{store8(guard+i,165);i=i+1;}esp32_callback32(libc_pause);
 '''
 init='if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_reent_init()||esp_sdk_task_init(){return 1;}esp_sdk_task_unmask();'
 faults=[('malloc-before-init',0,'0',''),('getreent-before-init',1,'0',''),('invalid-free',2,'guard',init),('null-reent',3,'0',init),('kernel-reent',4,'esp32_state()',init),('invalid-realloc',5,'guard',init),('unaligned-free-r',6,'guard+1',init),('rand-OOM',8,'0',init+'esp_sdk_malloc(esp_sdk_heap_free()-16);'),('strtok-OOM',9,'0',init+'esp_sdk_malloc(esp_sdk_heap_free()-16);')]
 for name,which,address,extra in faults:
  # Keep configuration/imports reachable even in deliberately early calls.
  text=setup+extra+f'let result=esp32_call32(esp32_external("libc_bad"),{which},{address},0,0,0,0,0,0);esp_libc_reent_init();return result;}}'
  for chip in (3,6):boot(name,text,chip,obj,trap=True,poison=True)
 for which in (0,1,7,8,9):
  text='''import "../../lib/platform/esp32c3-irq.flex";
 '''+setup.replace('fn main(){','fn bad_irq(source){return esp32_call32(esp32_external("libc_bad"),'+str(which)+',0,0,0,0,0,0,0);}fn main(){')+init+'esp_irq_software(esp32_callback(bad_irq));esp32_irq_raise(128);esp_irq_enable();return 99;}'
  for chip in (3,6):boot('ISR-libc-'+str(which),text,chip,obj,trap=True,poison=True)
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),physical_hardware=False,feature_complete=False,goal_status='active',ROM_libc_startup_verified=False,stdio_initialized=False,vendor_newlib_stdlib_execution=True,newlib_archive_sha256=sha(archive),compiler_sha256=sha(compiler),cases=cases)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: pinned newlib4.3 task state',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages,',report['C3_poison_unchanged_checks'],'guard checks')
if __name__=='__main__':main()
