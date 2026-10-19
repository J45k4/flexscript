#!/usr/bin/env python3
"""Explicit-init UART0/1 stock-ROM data/IRQ checks; clock-gate model is absent."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);p.add_argument('--c6-uart-timeout',choices=('require','unavailable'),default='require');a=p.parse_args();root=Path(__file__).resolve().parents[2];a.work.mkdir(parents=True,exist_ok=True);cases=[]
 def run(args):
  r=subprocess.run(list(map(str,args)),cwd=root,text=True,capture_output=True,timeout=60);assert r.returncode==0,(args,r.stdout,r.stderr);return r
 for bus,baud,threshold,timeout in [(0,115200,1,0),(1,115200,1,0),(0,9600,1,0),(1,1000000,1,0),(1,115200,32,20)]:
  for chip in (3,6):
   pre=(40000000+4095*baud-1)//(4095*baud);div=640000000//(baud*pre);packed=(div>>4)|((div&15)<<20)
   text=(root/'tests/esp32/riscv-uart-config-irq.flex').read_text().replace('esp32c3','esp32c'+str(chip)).replace('global uc_bus=0;',f'global uc_bus={bus};').replace('esp_uart_bus_init(uc_bus,115200,8,0,1)',f'esp_uart_bus_init(uc_bus,{baud},8,0,1)').replace('!=0x30015b',f'!={packed}').replace('esp_uart_bus_irq_thresholds(uc_bus,1,0)',f'esp_uart_bus_irq_thresholds(uc_bus,{threshold},0)').replace('esp_uart_bus_irq_timeout(uc_bus,0)',f'esp_uart_bus_irq_timeout(uc_bus,{timeout})')
   if threshold==32:text=text.replace('if uart_error ||','if uart_rx_timeouts<4 {return 7;}if uart_error ||')
   text=re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
   prefix=a.work/f'uart{bus}-{baud}-rx{threshold}-c{chip}';source=prefix.with_suffix('.flex');source.write_text(text);image=prefix.with_suffix('.bin');elf=prefix.with_suffix('.elf');report=prefix.with_suffix('.json')
   for suffix,path in [('',image),('-elf',elf)]:run([a.compiler,'--target',f'esp32c{chip}'+suffix,source,'-o',path])
   cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',elf,'--report',report]
   execute=chip==3 or (a.execute_c6 and not (threshold==32 and a.c6_uart_timeout=='unavailable'))
   if not execute:cmd+=['--validate-only']
   else:cmd+=['--words','--uart-index',bus]
   run(cmd);row=json.loads(report.read_text());row.update(UART_port=bus,requested_baud=baud,divider_readback_verified=execute,clock_gate_and_source_verified=False,physical_baud_verified=False,physical_hardware=False,UART_RX_and_TX_done_interrupts=execute,RX_timeout_interrupts=execute and threshold==32);row['known_C6_timeout_model_gap']=chip==6 and a.execute_c6 and threshold==32 and a.c6_uart_timeout=='unavailable';row['execution_unverified_reason']='C6 UART timeout registers are not implemented by the inherited C3 QEMU device' if row['known_C6_timeout_model_gap'] else None;cases.append(row)
 result=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),known_C6_timeout_model_gaps=sum(x['known_C6_timeout_model_gap'] for x in cases),C6_RX_timeout_execution_verified=any(x.get('machine')=='esp32c6' and x['RX_timeout_interrupts'] for x in cases),physical_hardware=False,clock_gate_and_source_verified=False,model_limitation='Stock C3 SYSTEM UART gate and C3 UART_CLK_CONF readback are not implemented; primary-header oracle checks those paths',cases=cases,compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest());(a.work/'report.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS: uart-config',result['C3_ROM_boots'],'C3 boots,',result['C6_ROM_boots'],'C6 boots,',result['C6_package_checks'],'C6 packages; physical pins/bus timing unverified')
if __name__=='__main__':main()
