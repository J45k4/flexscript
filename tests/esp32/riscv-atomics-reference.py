#!/usr/bin/env python3
"""Four GNU atomic ABI exports on stock C3; C6 execution is opt-in."""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path

def allocated(path):
 raw=path.read_bytes();off=struct.unpack_from('<I',raw,32)[0];n=struct.unpack_from('<H',raw,48)[0];idx=struct.unpack_from('<H',raw,50)[0];ss=[struct.unpack_from('<10I',raw,off+i*40) for i in range(n)];ns=ss[idx];pool=raw[ns[4]:ns[4]+ns[5]]
 return {pool[x[0]:pool.index(0,x[0])].decode():(x[1],x[5],raw[x[4]:x[4]+x[5]] if x[1]!=8 else b'') for x in ss if x[2]&2}

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();cases=[];controls=[];vendor=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 def run(cmd,reject=False):
  result=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,text=True,timeout=60);assert (result.returncode!=0 if reject else result.returncode==0),(cmd,result.stdout,result.stderr);return result
 provenance=json.loads((ref/'radio-provenance.json').read_text())
 for package in provenance['packages']:
  for row in [package['include'],*package['archives']]:assert sha(ref/row['path'])==row['sha256']
 for row in provenance['atomic_ABI_sources']:assert sha(ref/row['path'])==row['sha256']
 linker=w/'linker';run(['nice','-n','19',compiler,root/'scripts/esp32-link.flex','-o',linker]);aliases={}
 for chip in [3,6]:
  maps='\n'.join(x.read_text() for x in (ref/f'components/esp_rom/esp32c{chip}/ld').glob('*.ld'));alias=w/f'alias-c{chip}.ld';alias.write_text(''.join(n+' = '+re.search(r'\b'+n+r'\s*=\s*(0x[0-9a-fA-F]+)',maps)[1]+';\n' for n in ['Cache_Disable_ICache','Cache_Enable_ICache','memcpy','memset']));aliases[chip]=alias
 def boot(name,text,chip,radio,obj,trap=False,expected=0,guard=False,record=True):
  prefix=w/(name+f'-c{chip}'+('-radio' if radio else '-SRAM'));source=Path(str(prefix)+'.flex');elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json')
  text=text.replace('esp32c3',f'esp32c{chip}');text=re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
  if radio and 'xip.flex' not in text:text=f'import "{root}/lib/platform/esp32c{chip}-xip.flex";\n'+text
  source.write_text(text);run(['nice','-n','19',compiler,'--target',f'esp32c{chip}-'+('radio-elf' if radio else 'elf'),source,'-o',elf]);cmd=[linker,'--ld',a.ld,'--firmware',elf,'--object',obj,'--rom',aliases[chip],'--output',linked,'--image',image]
  if radio:cmd+=['--xip']
  run(cmd);cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',linked,'--report',report]
  if radio:cmd+=['--xip','--radio']
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if expected:cmd+=['--expected',expected]
   if guard:cmd+=['--expect-memory',(('0x3fc98000' if radio else '0x3fcb0000') if chip==3 else ('0x40818000' if radio else '0x40840000'))+':256:0xa5']
  run(cmd);row=json.loads(report.read_text());row.update(case=name,trap_expected=trap,poison_unchanged_checked=guard and (chip==3 or a.execute_c6),cache_disabled_atomic_probe=radio and name.startswith('C-'))
  if record:cases.append(row)
  return row
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections']
 for march in ['rv32im_zicsr_zifencei','rv32imc_zicsr_zifencei']:
  for opt in ['-O0','-O2','-Os']:
   obj=w/(march+opt+'.o');run(['nice','-n','19',*flags,'-march='+march,opt,'-c',root/'tests/esp32/riscv-atomics.c','-o',obj]);names=set(re.findall(r'\bU (__atomic_\w+)',run(['llvm-nm','--undefined-only',obj]).stdout));assert names=={'__atomic_exchange_4','__atomic_fetch_add_4','__atomic_fetch_sub_4','__atomic_compare_exchange_1'},names
   for chip in [3,6]:
    for radio in [False,True]:boot('C-'+march+opt,(root/'tests/esp32/riscv-atomics.flex').read_text(),chip,radio,obj)
 obj=w/'rv32im_zicsr_zifencei-O2.o'
 # Vendor instructions are unchanged. Only three private symbols become global
 # so the actual pinned WPA lifecycle lock can be called across preempting tasks.
 for chip in [3,6]:
  archive=ref/f'vendor/esp32c{chip}/libwpa_supplicant.a';original=w/f'eloop-c{chip}.o';original.write_bytes(subprocess.check_output(['llvm-ar','p',str(archive),'eloop.c.obj']));visible=w/f'eloop-visible-c{chip}.o';cmd=['llvm-objcopy']
  for symbol in ['eloop_lifecycle_lock','eloop_lifecycle_unlock','eloop_lifecycle_busy']:cmd+=['--globalize-symbol',symbol]
  run([*cmd,original,visible]);assert allocated(original)==allocated(visible);vendor.append(dict(chip=chip,archive_sha256=sha(archive),member_sha256=sha(original),allocated_sections_unchanged=True));boot('vendor-WPA-lifecycle',(root/'tests/esp32/riscv-vendor-atomic.flex').read_text(),chip,True,visible)
 for chip in [3,6]:
  for radio in [False,True]:
   state=0x3fc90000 if radio else 0x3fca0000
   if chip==6:state=0x40810000 if radio else 0x40830000
   end=state+(229376 if radio else 196608)
   faults=[('null',0,0),('misaligned',0,state+57),('control',0,state+4),('IRAM',0,0x40380000 if chip==3 else 0x40800000),('end',0,end),('ROM',0,0x3fcdffe0 if chip==3 else 0x4087ffd4),('MMIO',0,0x60000000),('byte-target',1,0),('byte-expected',2,0)]
   for name,which,pointer in faults:
    text='import "../../lib/platform/esp32c3-atomics.flex";fn atom_pause(a,b,c,d,e,f,g,h){return 0;}fn main(){let g=alloc(256);let i=0;while i<256{store8(g+i,165);i=i+1;}esp_atomics_bind();esp32_callback32(atom_pause);esp32_call32(esp32_external("atomic_bad"),'+str(which)+','+str(pointer)+',0,0,0,0,0,0);return 99;}'
    boot('guard-'+name,text,chip,radio,obj,trap=True,guard=True)
 # Accessor-only injection creates a deterministic real software interrupt in
 # the RMW window; omitting IRQ masking must lose the interrupt's increment.
 body=(root/'lib/platform/esp32-riscv-atomics.flex').read_text().replace('esp32_load32(a)','directed_read(a)');shadow=w/'directed-atomics.flex';shadow.write_text(body);text=f'import "{shadow}";\n'+(root/'tests/esp32/riscv-atomics-directed.flex').read_text();boot('directed-IRQ',text,3,True,obj)
 bad=w/'directed-bad.flex';needle='fn __atomic_fetch_add_4(a,b,c,d,e,f,g,h){esp_atomic_pointer(a,4);let ps=esp32_irq_save();';assert needle in body;bad.write_text(body.replace(needle,needle.replace('esp32_irq_save()','0')));row=boot('missing-IRQ-mask',text.replace(str(shadow),str(bad)),3,True,obj,expected=1,record=False);controls.append(dict(defect='missing IRQ exclusion loses directed interrupt increment',detected=True,actual_C3_ROM=True,accessor_instrumentation=True,result=row['result']))
 # Run actual vector firmware against narrowly mutated copies of the module.
 original=(root/'lib/platform/esp32-riscv-atomics.flex').read_text()
 defects=[('wrong-old-value','return old;}','return 0;}'),('wrong-PS-restore','esp32_irq_restore(ps);','esp32_irq_restore(ps|8);'),('missing-CAS-expected-update','store8(b,old);','0;'),('CAS-neighbor-overwrite','store8(a,c&255);','store8(a,c&255);store8(a+1,0);')]
 for name,needle,replacement in defects:
  assert needle in original;module=w/(name+'.flex');module.write_text(original.replace(needle,replacement));wrapper=w/(name+'-wrapper.flex');wrapper.write_text(f'import "{root}/lib/platform/esp32c3.flex";\nimport "{module}";\n');text=(root/'tests/esp32/riscv-atomics.flex').read_text().replace('"../../lib/platform/esp32c3-atomics.flex"','"'+str(wrapper)+'"');row=boot(name,text,3,True,obj,expected=1,record=False);controls.append(dict(defect=name,detected=True,actual_C3_ROM=True,result=row['result']))
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),cases=cases,vendor_members=vendor,negative_controls=controls,atomic_exports=sorted(names),C3_negative_control_boots=len(controls),single_CPU_only=True,full_C11_atomic_library=False,complete_vendor_radio_startup_verified=False,physical_hardware=False,compiler_sha256=sha(compiler));(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: atomics',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages')
if __name__=='__main__':main()
