#!/usr/bin/env python3
"""UART0 RX/TX-done/timeout IRQs against the independent fragmented UART peer."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);p.add_argument('--c6-uart-timeout',choices=('require','unavailable'),default='require');a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 def run(args):
  r=subprocess.run(list(map(str,args)),cwd=root,text=True,capture_output=True,timeout=60);assert r.returncode==0,(args,r.stdout,r.stderr);return r
 for name,threshold,timeout in [('FIFO1',1,0),('FIFO2',2,20),('RX-timeout',32,20)]:
  for chip in (3,6):
   text=(root/'tests/esp32/riscv-uart-irq.flex').read_text().replace('esp32c3','esp32c'+str(chip)).replace('esp_uart_irq_thresholds(1,0)',f'esp_uart_irq_thresholds({threshold},0)').replace('esp_uart_irq_timeout(0)',f'esp_uart_irq_timeout({timeout})')
   if threshold==32:text=text.replace('if uart_error ||','if uart_rx_timeouts<4 {return 7;}if uart_error ||')
   text=re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
   prefix=a.work/f'{name}-c{chip}';source=prefix.with_suffix('.flex');source.write_text(text);image=prefix.with_suffix('.bin');elf=prefix.with_suffix('.elf');report=prefix.with_suffix('.json')
   for suffix,path in [('',image),('-elf',elf)]:run([a.compiler,'--target',f'esp32c{chip}'+suffix,source,'-o',path])
   cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',elf,'--report',report]
   execute=chip==3 or (a.execute_c6 and not (threshold==32 and a.c6_uart_timeout=='unavailable'))
   if not execute:cmd+=['--validate-only']
   else:cmd+=['--words']
   run(cmd);row=json.loads(report.read_text());row.update(case=name,UART_RX_and_TX_done_interrupts=execute,RX_timeout_interrupts=execute and threshold==32,external_pin_hardware=False);row['known_C6_timeout_model_gap']=chip==6 and a.execute_c6 and threshold==32 and a.c6_uart_timeout=='unavailable';row['execution_unverified_reason']='C6 UART timeout registers are not implemented by the inherited C3 QEMU device' if row['known_C6_timeout_model_gap'] else None;cases.append(row)
 result=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),known_C6_timeout_model_gaps=sum(x['known_C6_timeout_model_gap'] for x in cases),C6_RX_timeout_execution_verified=any(x.get('machine')=='esp32c6' and x['RX_timeout_interrupts'] for x in cases),physical_hardware=False,cases=cases,compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest());(a.work/'report.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS: uart',result['C3_ROM_boots'],'C3 boots,',result['C6_ROM_boots'],'C6 boots,',result['C6_package_checks'],'C6 packages; physical pins/bus timing unverified')
if __name__=='__main__':main()
