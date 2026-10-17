#!/usr/bin/env python3
"""Verify actual emitted I2C firmware runs against saved physical transcripts.

This tool never accesses hardware and never labels emulator execution as a
new physical test. The exact image, runner and transcript must match their
successful execution records.
"""
import argparse,hashlib,json,re
from pathlib import Path
def require(ok,why):
 if not ok:raise AssertionError(why)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--kind',choices=['peer','fifo','irq'],required=True);p.add_argument('--capture',type=Path,required=True);p.add_argument('--uart',type=Path,required=True);p.add_argument('--elf',type=Path,required=True);p.add_argument('--runner',type=Path,required=True);p.add_argument('--execution',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();run=json.loads(a.execution.read_text());physical=json.loads((a.capture/'physical.json').read_text());data=a.uart.read_bytes()
 require(run['exit_code']==0 and not run['application_failure_seen'] and run['physical_hardware_verified'] is False,'incomplete native execution')
 require(run['image_sha256']==sha(a.elf) and run['runner_sha256']==sha(a.runner) and run['uart_sha256']==sha(a.uart),'native artifact identity')
 require(physical['pass'] and physical['ram_only'] and not physical['flash_write_requested'] and physical['flash_unchanged'] and physical['stages'][-1]=='physical-final-reset','physical cleanup proof')
 require(sha(a.elf)==sha(a.capture/'peer.elf')==physical['image_sha256'],'physical/native image identity')
 require(data==(a.capture/'physical-uart.bin').read_bytes()==physical['uart'].encode(),'native/physical transcript differs')
 require(not any(tag in data for tag in [b'WIRED FAIL',b'I2C IRQ FAIL',b'FIFO FAIL',b'GPIO FAIL']),'application failure')
 report={'pass':True,'kind':a.kind,'machine_code_executed':True,'physical_hardware_verified':False,'saved_physical_capture_compared':True,'byte_identical_physical_uart':True,'image_sha256':sha(a.elf),'runner_sha256':sha(a.runner),'uart_sha256':sha(a.uart),'uart_bytes':len(data)}
 if a.kind=='peer':
  rows=re.findall(rb'I2C MATRIX PASS MASTER ([0-9a-f]{16}) HZ ([0-9a-f]{16}) CASES ([0-9a-f]{16})',data);require(len(rows)==6 and b'PEER PASS\r\n' in data,'incomplete peer matrix')
  for i,(bus,rate,count) in enumerate(rows):require((int(bus,16),int(rate,16),int(count,16))==(i//3,[10000,100000,400000][i%3],29*(i+1)),'peer matrix case/rate order')
  report.update({'cases':174,'master_roles':2,'rates_hz':[10000,100000,400000]})
 elif a.kind=='fifo':
  rows=re.findall(rb'FIFO PASS BUS ([0-9a-f]{16}) BYTES ([0-9a-f]{16})',data);require(len(rows)==12 and b'FIFO STAGE PASS\r\n' in data and b'GPIO STAGE PASS\r\n' in data and b'PEER PASS\r\n' in data,'incomplete FIFO/GPIO matrix')
  for i,(bus,count) in enumerate(rows):require((int(bus,16),int(count,16))==(i//6,[1,2,3,16,31,32][i%6]),'FIFO size/controller order')
  require(len(re.findall(rb'GPIO PULL PASS [0-9a-f]{16}\r\n',data))==5,'incomplete GPIO pull controls');report.update({'FIFO_cases':12,'GPIO_pull_cases':5,'FIFO_sizes':[1,2,3,16,31,32]})
 else:
  require(data==b'PASS: I2C0/1 open-bus FIFO reads,12 native WAITI completion callbacks\r\n','incomplete I2C IRQ fixture');report.update({'callbacks':12,'controllers':2,'rates_hz':[10000,100000,400000]})
 a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));return 0
if __name__=='__main__':raise SystemExit(main())
