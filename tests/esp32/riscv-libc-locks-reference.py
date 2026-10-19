#!/usr/bin/env python3
"""Newlib dynamic-lock ABI and scheduler tests through unmodified C headers.

Stock C3 ROM execution; C6 execution is opt-in. No vendor ROM-libc startup claim.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args()
 root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();ref=a.reference.resolve();cases=[]
 def run(args):
  result=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60)
  assert result.returncode==0,(args,result.stdout,result.stderr)
  return result
 linker=work/'linker';run(['nice','-n','19',compiler,'scripts/esp32-link.flex','-o',linker])
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-I',ref/'components/newlib/platform_include','-I',ref/'newlib','-I',ref]
 def boot(name,text,chip,obj,trap=False,poison=False):
  prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json')
  text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000')
  text=re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M);source.write_text(text)
  run(['nice','-n','19',compiler,'--target',f'esp32c{chip}-elf',source,'-o',elf]);run([linker,'--ld',a.ld,'--firmware',elf,'--object',obj,'--output',linked,'--image',image])
  cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if poison:cmd+=['--expect-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':256:0xa5']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,trap_expected=trap,poison_unchanged_checked=poison and (chip==3 or a.execute_c6));cases.append(row)
 for march in ('rv32im_zicsr','rv32imc_zicsr'):
  for opt in ('-O0','-O2','-Os'):
   name=march+opt;obj=work/(name+'.o');run(['nice','-n','19',*flags,'-march='+march,opt,'-c',root/'tests/esp32/riscv-libc-locks.c','-o',obj])
   for chip in (3,6):
    boot(name,(root/'tests/esp32/riscv-libc-locks.flex').read_text(),chip,obj)
    boot('preempt-'+name,(root/'tests/esp32/riscv-libc-locks-preempt.flex').read_text(),chip,obj)
 setup='''import "../../lib/platform/esp32c3-libc-locks.flex";
 fn libc_probe(a,b,c,d,e,f,g,h){return 0;}
 fn main(){esp_libc_locks_bind();esp32_callback32(libc_probe);let guard=alloc(256);let i=0;while i<256{store8(guard+i,165);i=i+1;}
 '''
 init='if esp_sdk_heap_init(0x3fcb8000,32768)||esp_sdk_task_init(){return 1;}esp_sdk_task_unmask();'
 faults=[('null-legacy',0,'0',''),('unaligned-slot',1,'0',''),('kernel-slot',2,'esp32_state()',''),('past-RAM-slot',2,'0x70000000',''),('null-retarget',3,'0',''),('stale-retarget',4,'0',''),('wrong-recursion',5,'0',''),('release-zero',6,'0',''),('release-unowned',7,'0',''),('close-held',8,'0',''),('masked-self-deadlock',9,'0','esp32_irq_save();'),('allocation-failure',10,'0','esp_sdk_malloc(esp_sdk_heap_free()-16);'),('foreign-object',11,'guard',''),('close-wrong-recursion',12,'0',''),('retarget-release-zero',13,'0',''),('retarget-unaligned-slot',14,'guard+1','')]
 for name,which,address,extra in faults:
  text=setup+init+extra+f'return esp32_call32(esp32_external("libc_lock_bad"),{which},{address},0,0,0,0,0,0);}}'
  for chip in (3,6):boot(name,text,chip,obj,trap=True,poison=True)
 # Explicit init requires an arena even before the scheduler starts.
 for chip in (3,6):boot('init-before-heap',setup+'return esp32_call32(esp32_external("libc_lock_bad"),10,0,0,0,0,0,0,0);}',chip,obj,trap=True,poison=True)
 owner=setup+init+'''esp32_call32(esp32_external("libc_lock_call"),0,0,0,0,0,0,0,0);esp32_call32(esp32_external("libc_lock_call"),2,0,0,0,0,0,0,0);
 let task=esp_sdk_task_create(esp32_external("libc_lock_bad"),13,4096,1);if !task{return 1;}while load64(task+544)!=2{esp_sdk_yield();}return 99;}'''
 for chip in (3,6):boot('release-other-owner',owner,chip,obj,trap=True,poison=True)
 # Exercise the real trap handler: IRQ callers cannot allocate or mutate locks.
 for which in (0,3,10,15):
  text='''import "../../lib/platform/esp32c3-irq.flex";
 '''+setup.replace('fn main(){','fn bad_irq(source){return esp32_call32(esp32_external("libc_lock_bad"),'+str(which)+',0,0,0,0,0,0,0);}fn main(){')+init+'''esp_irq_software(esp32_callback(bad_irq));esp32_irq_raise(128);esp_irq_enable();return 99;}'''
  for chip in (3,6):boot('ISR-'+str(which),text,chip,obj,trap=True,poison=True)
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),physical_hardware=False,feature_complete=False,goal_status='active',ROM_libc_startup_verified=False,static_common_locks_supported=False,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),cases=cases)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: newlib dynamic locks',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages,',report['C3_poison_unchanged_checks'],'guard checks')
if __name__=='__main__':main()
