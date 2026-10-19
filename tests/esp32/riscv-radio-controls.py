#!/usr/bin/env python3
"""Radio SRAM boundaries and defect controls. Stock C3 execution only."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();rows=[];boundaries=[]
 def run(cmd):
  r=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,text=True,timeout=60);assert r.returncode==0,(cmd,r.stdout,r.stderr);return r
 manifest=json.loads((ref/'radio-provenance.json').read_text())
 for item in manifest['ROM_maps']:assert hashlib.sha256((ref/item['path']).read_bytes()).hexdigest()==item['sha256']
 for chip in [3,6]:
  name=f'esp32c{chip}';header=(ref/f'components/soc/{name}/include/soc/soc.h').read_text();macro=lambda n:int(re.search(r'#define\s+'+n+r'\s+(0x[0-9A-Fa-f]+)',header)[1],16);low=macro('SOC_DIRAM_DRAM_LOW');high=macro('SOC_DIRAM_DRAM_HIGH');iram=macro('SOC_DIRAM_IRAM_LOW');begin=0x40380000 if chip==3 else 0x40800000;data=0x3fc90000 if chip==3 else 0x40810000;end=data+229376;reserved=0x3fcce710 if chip==3 else 0x4086e610;assert low<=begin-iram+low and begin-iram+low+65536<=data<end<reserved<high
  exports=[]
  for item in manifest['ROM_maps']:
   if name not in item['path']:continue
   for symbol,address in re.findall(r'\b([A-Za-z_]\w*)\s*=\s*(0x[0-9a-fA-F]+)',(ref/item['path']).read_text()):
    value=int(address,16)
    if low<=value<high:assert value>=end,(symbol,hex(value));exports.append(dict(symbol=symbol,address=value,source=item['path']))
  assert exports;boundaries.append(dict(chip=name,profile_end=end,primary_ROM_reserved_start=reserved,exported_ROM_RAM_symbols=len(exports),lowest_exported_ROM_RAM=min(x['address'] for x in exports),physical_hardware=False,controller_hidden_allocations_verified=False))
 snapshot=w/'snapshot'
 for name in ['compiler','lib','vm']:shutil.copytree(root/name,snapshot/name,dirs_exist_ok=True)
 linker=w/'linker';run([compiler,root/'scripts/esp32-link.flex','-o',linker]);aliases=w/'aliases.ld';aliases.write_text('/* No C objects in these boundary fixtures. */\n')
 def boot(name,test,selected,expected=None,guard=False):
  source=w/(name+'.flex');source.write_text((root/'tests/esp32'/test).read_text().replace('../../lib/',str(snapshot/'lib')+'/'));elf=w/(name+'.elf');linked=w/(name+'-linked.elf');image=w/(name+'.bin');report=w/(name+'.json');run([selected,'--target','esp32c3-radio-elf',source,'-o',elf]);run([linker,'--ld','ld.lld','--xip','--rom',aliases,'--firmware',elf,'--output',linked,'--image',image]);cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',a.qemu,'--xip','--radio','--image',image,'--elf',linked,'--report',report]
  if expected is None:cmd+=['--trap']
  else:cmd+=['--expected',expected]
  if guard:cmd+=['--expect-memory','0x3fc98000:256:0xa5']
  run(cmd);result=json.loads(report.read_text());rows.append(dict(case=name,actual_C3_ROM=True,expected_trap=expected is None,result=result['result'],poison_unchanged_checked=guard,defect_detected=name!='PC-positive'))
 boot('PC-positive','riscv-radio-pc-guard.flex',compiler,guard=True)
 backend=snapshot/'compiler/backends/riscv32.flex';old=backend.read_text();needle='rv_imm(28,rv_code_base+rv_code_capacity());rv_guard(6,30,28);';assert needle in old;backend.write_text(old.replace(needle,'rv_imm(28,rv_code_base+131072);rv_guard(6,30,28);'));bad=w/'compiler-PC-bad'
 try:run(['nice','-n','19',compiler,snapshot/'compiler/main.flex','-o',bad]);boot('PC-old128K-bound','riscv-radio-pc-guard.flex',bad,expected=99,guard=True)
 finally:backend.write_text(old)
 defects=[('SDK-arena-size','lib/platform/esp32-sdk-heap.flex','return esp32_state()+180224;','return esp32_state()+131072;',2),('buffer-upper','lib/platform/esp32-riscv-common.flex','rv_hal_ram_top','(rv_hal_ram_top-32768)',3),('TLS-static-upper','lib/platform/esp32-sdk-riscv-tls.flex','esp32_state()+rv_hal_data_size','esp32_state()+65536',10)]
 for name,path,needle,replacement,expected in defects:
  target=snapshot/path;old=target.read_text();assert needle in old,(name,needle);target.write_text(old.replace(needle,replacement))
  try:boot(name,'riscv-radio-profile.flex',compiler,expected=expected)
  finally:target.write_text(old)
 # A mistaken native allocator end expands into the SDK arena.
 old=backend.read_text();needle='rv_imm(12,rv_heap_end());';assert needle in old
 replacement='rv_imm(12,rv_heap_begin()+32768);'
 backend.write_text(old.replace(needle,replacement));bad=w/'compiler-native-heap-bad'
 try:run(['nice','-n','19',compiler,snapshot/'compiler/main.flex','-o',bad]);boot('native-heap-overlap','riscv-radio-profile.flex',bad,expected=4)
 finally:backend.write_text(old)
 report=dict(pass_all=True,primary_memory_boundaries=boundaries,cases=rows,detected_defects=sum(x['defect_detected'] for x in rows),C3_ROM_boots=1,C3_negative_control_boots=5,C6_package_checks=0,C6_CPU_execution=False,physical_hardware=False,complete_vendor_radio_startup_verified=False);(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: radio boundaries and',report['detected_defects'],'actual C3 defect controls')
if __name__=='__main__':main()
