#!/usr/bin/env python3
"""Compare saved machine-code/physical timer-width observations; no device access."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('firmware','physical','report'):p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
physical=json.loads((a.physical/'physical.json').read_text())
for f in ('pass','ram_only','probe_pass','flash_before_matches','flash_after_matches','final_reset'):assert physical[f] is True,f
assert physical['flash_write_requested'] is False
assert physical['ELF_sha256']==sha(a.firmware/'esp32.elf')
rows=[]
for chip,cases in [('esp32',1184),('esp32s3',768)]:
 n=(a.firmware/(chip+'.native.uart')).read_bytes();q=(a.firmware/(chip+'.qemu.uart')).read_bytes()
 expected=f'START: timer width\r\nPASS: timer width cases {cases:016x} alarms 0000000000000020\r\n'.encode()
 assert n==expected and n in q
 if chip=='esp32':assert n==(a.physical/'uart.bin').read_bytes()
 rows.append({'chip':chip,'set_read_cases':cases,'alarm_callbacks':32,'native_matches_QEMU':True,'physical_verified':chip=='esp32','ELF_sha256':sha(a.firmware/(chip+'.elf')),'UART_sha256':hashlib.sha256(n).hexdigest()})
r={'pass':True,'scope_complete':False,'chips':rows,'original_flash_unchanged_and_reset':True,'physical_S3_verified':False}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS: exact original/S3 timer-width UART and verified original physical capture')
