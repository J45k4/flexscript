#!/usr/bin/env python3
"""Validate independent GNU firmware observations against explicit silicon/QEMU contracts.

No device access. The physical capture must be supplied separately. QEMU is
known to mask reserved FCR/FSR bits; all other state must agree exactly.
"""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('native','qemu','physical','physical-report','elf','report'):
    p.add_argument('--'+name,type=Path,required=True)
a=p.parse_args()
values=[0,0xffffffff]+[2**i for i in range(32)]+[0x80000000,0x7f800000,0xff800000,0x7fc12345,0x7f812345,0x3f800000,0x12345678,0xabcdef01]
assert len(values)==42
checks=0
observations={}
for name in ('native','qemu','physical'):
    raw=getattr(a,name).read_bytes()
    lines=raw.decode('ascii').splitlines()
    assert 'PASS: GNU FPU state and6 disabled exceptions' in lines
    rows=[[int(x,16) for x in line.split()[1:]] for line in lines if line.startswith('STATE ')]
    disabled=[int(line.split()[1],16) for line in lines if line.startswith('CPDIS ')]
    assert len(rows)==42 and disabled==[32]*6
    checks+=7
    for value,row in zip(values,rows):
        assert len(row)==23
        fcr=value if name!='qemu' else value&0x7f
        fsr=value if name!='qemu' else value&0xf80
        expected=[value,fcr,fsr,value,value]+[value^r for r in range(16)]+[fcr,fsr]
        assert row==expected,(name,hex(value),row,expected)
        checks+=23
    start=raw.index(b'START: GNU FPU state')
    observations[name]={'sha256':hashlib.sha256(raw).hexdigest(),'firmware_UART_sha256':hashlib.sha256(raw[start:]).hexdigest(),'cases':42,'state_words':924,'disabled_exceptions':6}
assert a.native.read_bytes()==a.physical.read_bytes(),'complete native UART must equal physical UART'
checks+=1
physical=json.loads(a.physical_report.read_text())
for field in ('pass','ram_only','probe_pass','flash_before_matches','flash_after_matches','final_reset'):
    assert physical[field] is True,field
    checks+=1
sha=hashlib.sha256(a.elf.read_bytes()).hexdigest()
assert physical['ELF_sha256']==sha
checks+=1
r={'pass':True,'scope_complete':False,'checks':checks,'ELF_sha256':sha,'observations':observations,'native_matches_physical':True,'QEMU_difference':'Only FCR/FSR reserved bits: physical/native preserve all32; pinned QEMU masks FCR0x7f/FSR0xf80,including delayed reads.','full_floating_arithmetic_verified':False}
a.report.write_text(json.dumps(r,indent=2)+'\n')
print('PASS: silicon/native raw bits and explicit QEMU difference;',checks,'checks')
