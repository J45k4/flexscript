#!/usr/bin/env python3
"""Pinned C3/C6 OSI typed-C callbacks; C6 execution is opt-in; missing model registers remain explicit packages."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--only-irq',action='store_true');p.add_argument('--only-pmu',action='store_true');p.add_argument('--chip',type=int,choices=(3,6));p.add_argument('--expected',type=int,default=0);p.add_argument('--source-root',type=Path);p.add_argument('--ld',default='ld.lld');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);p.add_argument('--c6-slowclk-store',choices=('require','unavailable'),default='require');a=p.parse_args();root=(a.source_root or Path(__file__).resolve().parents[2]).resolve();assert not (a.only_irq and a.only_pmu);assert not a.expected or (a.only_pmu and a.chip==3);w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();cases=[]
 def run(cmd):
  r=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,text=True,timeout=60);assert r.returncode==0,(cmd,r.stdout,r.stderr);return r
 def boot(tag,fixture,chip,obj):
  source=w/(tag+'.flex');source.write_text((root/fixture).read_text().replace('esp32c3',f'esp32c{chip}').replace('../../lib/',str(root/'lib')+'/'));fw=w/(tag+'.elf');run([compiler,'--target',f'esp32c{chip}-radio-elf',source,'-o',fw]);archives=sorted((ref/f'vendor/esp32c{chip}').glob('*.a'))+[ref/'riscv-libc.a',ref/'riscv-libgcc.a'];defined=set()
  for file in [fw,obj,*archives]:
   for line in run(['llvm-nm','--defined-only','--extern-only','-P',file]).stdout.splitlines():
    parts=line.split()
    if len(parts)>1 and len(parts[1])==1:defined.add(parts[0])
  symbols={}
  for file in sorted((ref/f'components/esp_rom/esp32c{chip}/ld').glob('*.ld')):
   for name,value in re.findall(r'\b([A-Za-z_]\w*)\s*=\s*(0x[0-9a-fA-F]+)',file.read_text()):
    if name not in defined:symbols[name]=value
  rom=w/(tag+'.ld');rom.write_text(''.join(f'PROVIDE({n}={v});\n' for n,v in sorted(symbols.items())));linked=w/(tag+'-linked.elf');image=w/(tag+'.bin');report=w/(tag+'.json');cmd=[w/'linker','--ld',a.ld,'--xip','--newlib-stdio','--newlib-rom','--firmware',fw,'--rom',rom,'--object',obj,'--output',linked,'--image',image]
  for archive in archives:cmd+=['--archive',archive]
  run(cmd);cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--xip','--radio','--image',image,'--elf',linked,'--report',report,'--expected',a.expected]
  known_gap=chip==6 and a.execute_c6 and fixture=='tests/esp32/riscv-osi.flex' and a.c6_slowclk_store=='unavailable'
  execute=chip==3 or (a.execute_c6 and not known_gap)
  if not execute:cmd+=['--validate-only']
  run(cmd);row=json.loads(report.read_text());row.update(case=tag,primary_OSI_fields=(120 if chip==3 else 127),complete_radio_startup=False,PHY_execution=False,expected_main_result=a.expected,known_C6_slowclk_model_gap=known_gap,execution_unverified_reason="Official C6 QEMU ignores LP_AON STORE1 calibration storage" if known_gap else None);cases.append(row)
 provenance=json.loads((ref/'osi-primary/provenance.json').read_text())
 for row in provenance['sources']:
  if 'sha256' in row:assert hashlib.sha256((ref/'osi-primary'/row['path']).read_bytes()).hexdigest()==row['sha256']
 run([compiler,root/'scripts/esp32-link.flex','-o',w/'linker'])
 for chip in ([a.chip] if a.chip else [3,6]):
  inc=w/f'include-c{chip}';(inc/'soc').mkdir(parents=True,exist_ok=True)
  for folder in ['include/soc','register/soc']:
   for source in (ref/f'components/soc/esp32c{chip}'/folder).glob('*.h'):shutil.copy2(source,inc/'soc'/source.name)
  shutil.copy2(ref/f'osi-primary/idf/components/soc/esp32c{chip}/register/soc/efuse_reg.h',inc/'soc/efuse_reg.h');shutil.copy2(ref/f'osi-primary/idf/components/soc/esp32c{chip}/include/soc/efuse_defs.h',inc/'soc/efuse_defs.h');shutil.copy2(ref/'osi-primary/vendor/c/include/esp_private/wifi_os_adapter.h',inc/'wifi_os_adapter.h');(inc/'sdkconfig.h').write_text(f'#define CONFIG_IDF_TARGET_ESP32C{chip} 1\n#define CONFIG_SOC_WIFI_HE_SUPPORT {int(chip==6)}\n');(inc/'esp_assert.h').write_text('#pragma once\n');(inc/'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
  primary=(ref/f'vendor/esp32c{chip}/include.rs').read_text();fields=re.findall(r'^    pub (\w+):',re.search(r'pub struct wifi_osi_funcs_t \{(.*?)\n\}',primary,re.S)[1],re.M);assert len(fields)==(120 if chip==3 else 127);check=inc/'abi-check.h';check.write_text(''.join(f'_Static_assert(offsetof(wifi_osi_funcs_t,{name})=={i*4},"primary ABI {name}");\n' for i,name in enumerate(fields)))
  ctext=(root/'tests/esp32/riscv-osi.c').read_text().replace('struct osi_guard {','#include "abi-check.h"\nstruct osi_guard {');csource=inc/'peer.c';csource.write_text(ctext)
  for march in ['rv32im_zicsr_zifencei','rv32imc_zicsr_zifencei']:
   for opt in ['-O0','-O2','-Os']:
    if (a.only_irq or a.only_pmu) and (march,opt)!=('rv32imc_zicsr_zifencei','-Os'):continue
    tag=f'c{chip}-{march}{opt}';obj=w/(tag+'.o');cmd=['nice','-n','19',a.clang,'--target=riscv32','-mabi=ilp32','-march='+march,opt,'-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-I',inc]
    if chip==6:cmd+=['-DC6']
    run([*cmd,'-c',csource,'-o',obj]);
    if not a.only_irq and not a.only_pmu:boot(tag,'tests/esp32/riscv-osi.flex',chip,obj)
  if not a.only_pmu:boot(f'c{chip}-IRQ','tests/esp32/riscv-radio-irq.flex',chip,obj)
  if not a.only_irq and not a.only_pmu:boot(f'c{chip}-newlib-order','tests/esp32/riscv-radio-order.flex',chip,obj)
  if not a.only_irq:boot(f'c{chip}-regi2c-guards','tests/esp32/riscv-regi2c-guards.flex',chip,obj)
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),known_C6_slowclk_model_gaps=sum(x['known_C6_slowclk_model_gap'] for x in cases),cases=cases,complete_vendor_radio_startup_verified=False,physical_hardware=False,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest());(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: OSI',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages')
if __name__=='__main__':main()
