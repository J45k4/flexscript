#!/usr/bin/env python3
"""Stock C3 ROM verifies SPI guards/timeouts/ISR exclusion, not SPI wire data."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 def run(args):
  r=subprocess.run(list(map(str,args)),cwd=root,text=True,capture_output=True,timeout=60);assert r.returncode==0,(args,r.stdout,r.stderr);return r
 for name in ('riscv-spi-timeout','riscv-spi-irq-lock'):
  for chip in (3,6):
   text=(root/'tests/esp32'/(name+'.flex')).read_text().replace('esp32c3','esp32c'+str(chip));text=re.sub(r'^import "([^\"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
   prefix=a.work/(name+f'-c{chip}');source=prefix.with_suffix('.flex');source.write_text(text);image=prefix.with_suffix('.bin');elf=prefix.with_suffix('.elf');report=prefix.with_suffix('.json')
   for suffix,path in [('',image),('-elf',elf)]:run([a.compiler,'--target',f'esp32c{chip}'+suffix,source,'-o',path])
   cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',elf,'--report',report]
   if chip==6 and not a.execute_c6:cmd+=['--validate-only']
   run(cmd);row=json.loads(report.read_text());row.update(case=name,SPI_wire_transfer_verified=False,physical_hardware=False);cases.append(row)
 result=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),SPI_wire_transfer_verified=False,physical_hardware=False,cases=cases,compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest());(a.work/'report.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS: spi',result['C3_ROM_boots'],'C3 boots,',result['C6_ROM_boots'],'C6 boots,',result['C6_package_checks'],'C6 packages; physical pins/bus timing unverified')
if __name__=='__main__':main()
