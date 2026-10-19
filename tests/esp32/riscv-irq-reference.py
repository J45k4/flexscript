#!/usr/bin/env python3
"""Independent ILP32 probes and stock-QEMU C3 interrupt/preemption checks.

C6 defaults to package checks; --execute-c6 requires a stock C6 machine.
No physical acceptance is claimed.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args()
 root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();cases=[];rejections=[]
 def run(args,reject=False):
  result=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60)
  assert (result.returncode!=0 if reject else result.returncode==0),(args,result.stdout,result.stderr)
  return result
 linker=work/'linker';run([compiler,'scripts/esp32-link.flex','-o',linker])
 def input_text(text,chip):
  text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000').replace('source!=32','source!=51').replace('esp_irq_detach(32)','esp_irq_detach(51)')
  return re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
 def boot(name,text,chip,objects=(),trap=False,poison=False):
  prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');source.write_text(input_text(text,chip));elf=Path(str(prefix)+'.elf');image=Path(str(prefix)+'.bin')
  run([compiler,'--target',f'esp32c{chip}-elf',source,'-o',elf])
  if objects:
   linked=Path(str(prefix)+'-linked.elf');cmd=[linker,'--ld',a.ld,'--firmware',elf,'--output',linked,'--image',image]
   for obj in objects:cmd+=['--object',obj]
   run(cmd);elf=linked
  else:run([compiler,'--target',f'esp32c{chip}',source,'-o',image])
  report=Path(str(prefix)+'.json');cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',elf,'--report',report]
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if poison:cmd+=['--expect-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':512:0xa5']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,stack_unchanged_checked=poison and (chip==3 or a.execute_c6));cases.append(row)
 for name in ['riscv-irq-software','riscv-irq-timer','riscv-irq-ownership','riscv-preempt','riscv-preempt-resources']:
  for chip in (3,6):boot(name,(root/'tests/esp32'/(name+'.flex')).read_text(),chip)
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections']
 state=work/'irq-state.o';run([*flags,'-march=rv32im_zicsr','-c','tests/esp32/riscv-irq-state.S','-o',state])
 for chip in (3,6):boot('all-GPRs-50-interrupts',(root/'tests/esp32/riscv-irq-state.flex').read_text(),chip,[state])
 for model in ('local-exec','initial-exec'):
  for march in ('rv32im_zicsr','rv32imc_zicsr'):
   for opt in ('-O0','-O2','-Os'):
    name=model+'-'+march+opt;obj=work/(name+'.o');run([*flags,'-march='+march,opt,'-fPIC','-ftls-model='+model,'-c','tests/esp32/riscv-preempt-tls.c','-o',obj])
    for chip in (3,6):boot(name,(root/'tests/esp32/riscv-preempt-tls.flex').read_text(),chip,[obj])
 setup='''import "../../lib/platform/esp32c3-irq.flex";
fn guarded_irq(n){return 0;}
fn esp_irq_epilogue(ps){return 0;}
fn main(){let buffer=alloc(512);let i=0;while i<512{store8(buffer+i,165);i=i+1;}esp_irq_software(esp32_callback(guarded_irq));esp32_irq_raise(128);'''
 for name,sp,floor in [('SP-zero','0','buffer'),('SP-underflow','8','buffer'),('SP-unaligned','buffer+209','buffer'),('SP-short-frame','buffer+200','buffer'),('SP-above-stack','0x70000000','buffer'),('floor-unaligned','buffer+512','buffer+1'),('floor-kernel','buffer+512','esp32_state()'),('floor-above-SP','buffer+512','buffer+1024')]:
  text=setup+f'esp32_call32(esp32_external("irq_bad_stack"),{sp},{floor},esp32_state(),0,0,0,0,0);return 99;}}'
  for chip in (3,6):boot(name,text,chip,[state],trap=True,poison=True)
 for name,code in [('mask-line0','esp32_irq_mask(1);'),('mask-high','esp32_irq_mask(1<<32);'),('raise-other','esp32_irq_raise(2);'),('raise-high','esp32_irq_raise(1<<32);'),('clear-other','esp32_irq_clear(1);'),('allocation-in-IRQ','esp32_irq_raise(128);esp_irq_enable();')]:
  text='import "../../lib/platform/esp32c3-irq.flex";\nfn bad_irq(n){alloc(8);return 0;}fn main(){esp_irq_software(esp32_callback(bad_irq));'+code+'return 99;}'
  for chip in (3,6):boot(name,text,chip,trap=True)
 nested='import "../../lib/platform/esp32c3-irq.flex";\nfn nested_irq(n){esp32_irq_raise(128);esp_irq_enable();return 0;}fn main(){esp_irq_software(esp32_callback(nested_irq));esp32_irq_raise(128);esp_irq_enable();return 99;}'
 for chip in (3,6):boot('nested-entry-failstop',nested,chip,trap=True)
 for name,text in [('dispatch-arity','fn esp_irq_dispatch(){return 0;}fn main(){return 0;}'),('tail-arity','fn esp_irq_dispatch(n){return 0;}fn esp_irq_epilogue(){return 0;}fn main(){return 0;}'),('tail-no-dispatch','fn esp_irq_epilogue(n){return 0;}fn main(){return 0;}')]:
  source=work/(name+'.flex');source.write_text(text)
  for chip in (3,6):
   output=work/(name+f'-c{chip}.bin');output.write_bytes(b'preserve destination');result=run([compiler,'--target',f'esp32c{chip}',source,'-o',output],reject=True);assert output.read_bytes()==b'preserve destination';rejections.append(dict(case=name,chip=chip,error=result.stderr.strip()))
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),physical_hardware=False,feature_complete=False,goal_status='active',stack_unchanged_checks=sum(x['stack_unchanged_checked'] for x in cases),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),cases=cases,rejections=rejections)
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: IRQ/preemption',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 package checks,',report['stack_unchanged_checks'],'unchanged stack guards')
if __name__=='__main__':main()
