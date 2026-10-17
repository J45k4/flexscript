#!/usr/bin/env python3
"""Authorized RAM-only clock probe with full-flash checks and final reset.

No flash-write command is issued. The complete device image must match the
explicitly supplied verified backup before RAM loading can begin.
"""
import argparse, hashlib, json, os, re, subprocess, time
from pathlib import Path
import serial
p = argparse.ArgumentParser(description=__doc__)
for name in ('elf','work','backup'):
    p.add_argument('--'+name, type=Path, required=True)
p.add_argument('--backup-sha256', required=True)
p.add_argument('--port', required=True)
p.add_argument('--marker', default='PASS: ROM PLL,3 CPU/APB ratios and2 WAITI clocks')
a = p.parse_args()
os.umask(0o077)
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
backup = a.backup.read_bytes()
assert len(backup)==4194304 and hashlib.sha256(backup).hexdigest()==a.backup_sha256, 'backup verification'
expected = hashlib.md5(backup).hexdigest()
common = ['--port',a.port,'--chip','esp32','--baud','115200','--non-interactive','--skip-update-check','--no-stub']
report = {'pass':False,'ram_only':True,'flash_write_requested':False,'started_at':time.time(),'ELF_sha256':hashlib.sha256(a.elf.read_bytes()).hexdigest(),'expected_full_flash_MD5':expected,'flash_before_matches':False,'flash_after_matches':False,'final_reset':False,'stages':[]}
path = work/'physical.json'
def save(): path.write_text(json.dumps(report,indent=2)+'\n')
def run(args,label):
    print(label,flush=True)
    report['stages'].append(label)
    save()
    q = subprocess.run(args,capture_output=True,timeout=90)
    (work/(label+'.log')).write_bytes(q.stdout+q.stderr)
    assert q.returncode==0,(label,q.stdout[-1000:],q.stderr[-1000:])
    return (q.stdout+q.stderr).decode(errors='replace')
def same(text):
    return any(int(s,16)==int(expected,16) for s in re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',text))
uart=None
try:
    before=run(['espflash','checksum-md5',*common,'--after','no-reset','0x0','0x400000'],'before')
    report['flash_before_matches']=same(before)
    save()
    assert report['flash_before_matches'],'device differs from verified backup; RAM loading aborted'
    uart=serial.Serial(port=None,baudrate=115200,timeout=.1)
    uart.dtr=False
    uart.rts=False
    uart.port=a.port
    uart.open()
    uart.reset_input_buffer()
    args=['espflash','flash','--ram',*common,'--after','no-reset','--ignore-app-descriptor',str(a.elf.resolve())]
    assert '--ram' in args
    run(args,'RAM-load')
    data=bytearray(uart.read(uart.in_waiting))
    marker=a.marker.encode()
    end=time.monotonic()+30
    while time.monotonic()<end and marker not in data and b' FAIL' not in data:
        data.extend(uart.read(4096))
        (work/'uart.bin').write_bytes(data)
    end=time.monotonic()+1
    while time.monotonic()<end:
        data.extend(uart.read(4096))
    (work/'uart.bin').write_bytes(data)
    report['UART_sha256']=hashlib.sha256(data).hexdigest()
    report['UART']=data.decode(errors='replace')
    report['probe_pass']=marker in data and b' FAIL' not in data
    save()
    print(report['UART'],flush=True)
finally:
    if uart is not None: uart.close()
    try:
        if report['flash_before_matches']:
            after=run(['espflash','checksum-md5',*common,'--after','no-reset','0x0','0x400000'],'after')
            report['flash_after_matches']=same(after)
    finally:
        try:
            run(['espflash','reset',*common],'final-reset')
            report['final_reset']=True
        finally:
            report['finished_at']=time.time()
            report['pass']=report.get('probe_pass',False) and report['flash_before_matches'] and report['flash_after_matches'] and report['final_reset']
            save()
assert report['pass'],'RAM probe or flash/reset verification failed'
print('PASS: physical RAM probe; full4MiB unchanged/reset',flush=True)
