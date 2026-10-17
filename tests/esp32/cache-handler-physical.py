#!/usr/bin/env python3
"""Bounded, RAM-only cache-error handler observations on the authorized board.

An explicit espflash executable and complete eight-image manifest are verified
before device access. Full4MiB guards and a final reset surround every batch.
"""
import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path
import serial

p = argparse.ArgumentParser(description=__doc__)
for name in ('manifest', 'backup', 'work', 'espflash'):
    p.add_argument('--' + name, type=Path, required=True)
for name in ('backup-sha256', 'port'):
    p.add_argument('--' + name, required=True)
p.add_argument('--family', choices=('handler', 'restart', 'latency', 'mmu'), default='handler')
p.add_argument('--first', type=int, default=0)
p.add_argument('--count', type=int, default=4)
a = p.parse_args()
assert 0 <= a.first < 8 and 1 <= a.count <= 4 and a.first + a.count <= 8
flash = a.espflash.resolve()
assert flash.is_file() and os.access(flash, os.X_OK)
assert Path(a.port).is_symlink(), 'explicit stable USB serial identity required'
os.umask(0o077)
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
sha = lambda data: hashlib.sha256(data).hexdigest()
backup = a.backup.read_bytes()
assert len(backup) == 4194304 and sha(backup) == a.backup_sha256
md5 = hashlib.md5(backup).hexdigest()
cases = json.loads(a.manifest.read_text())
assert [(c['bus'], c['mode']) for c in cases] == [(b, m) for b in range(2) for m in range(4)]
for c in cases:
    c['elf'] = str((a.manifest.parent / c['elf']).resolve())
    assert sha(Path(c['elf']).read_bytes()) == c['sha256']
selected = cases[a.first:a.first + a.count]
common = ['--port', a.port, '--chip', 'esp32', '--baud', '115200',
          '--non-interactive', '--skip-update-check', '--no-stub']
report = {'pass': False, 'probe_family': a.family, 'ram_only': True, 'flash_write_requested': False,
          'espflash_sha256': sha(flash.read_bytes()),
          'backup_sha256': a.backup_sha256, 'expected_full_flash_MD5': md5,
          'before_matches': False, 'after_matches': False, 'final_reset': False,
          'selection': {'first': a.first, 'count': a.count}, 'cases': [],
          'started_at': time.time()}
report_path = work / 'physical.json'


def save():
    report_path.write_text(json.dumps(report, indent=2) + '\n')


def run(args, label):
    q = subprocess.run([str(x) for x in args], capture_output=True, timeout=90)
    (work / (label + '.log')).write_bytes(q.stdout + q.stderr)
    assert q.returncode == 0, (label, q.stdout[-500:], q.stderr[-500:])
    return (q.stdout + q.stderr).decode(errors='replace')


def checksum(label):
    text = run([flash, 'checksum-md5', *common, '--after', 'no-reset',
                '0x0', '0x400000'], label)
    return any(int(s, 16) == int(md5, 16) for s in
               re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])', text))


def interrupted(signum, frame):
    raise InterruptedError('RAM IRQ batch interrupted by signal ' + str(signum))


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
uart = None
try:
    print('before', flush=True)
    report['before_matches'] = checksum('before')
    save()
    assert report['before_matches'], 'device differs from verified original; abort before RAM load'
    for case in selected:
        label = f"bus{case['bus']}-mode{case['mode']}"
        print(label, flush=True)
        uart = serial.Serial(port=None, baudrate=115200, timeout=.1)
        uart.dtr = False
        uart.rts = False
        uart.port = a.port
        uart.open()
        uart.reset_input_buffer()
        run([flash, 'flash', '--ram', *common, '--after', 'no-reset',
             '--ignore-app-descriptor', case['elf']], label + '-RAM-load')
        marker = f"CACHE {a.family.upper()} COMPLETE {case['bus']:016x} MODE {case['mode']:016x}".encode()
        data = bytearray(uart.read(uart.in_waiting))
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and marker not in data and b' FAIL' not in data:
            data.extend(uart.read(4096))
            (work / (label + '.uart')).write_bytes(data)
        data.extend(uart.read(4096))
        uart.close()
        uart = None
        (work / (label + '.uart')).write_bytes(data)
        record = {**case, 'UART_sha256': sha(data), 'UART': data.decode(errors='replace'),
                  'completed': marker in data, 'final_reset': False}
        report['cases'].append(record)
        save()
        assert record['completed'] and b' FAIL' not in data, (label, 'probe did not complete', record['UART'])
        run([flash, 'reset', *common], label + '-reset')
        record['final_reset'] = True
        save()
        print('completed', flush=True)
finally:
    if uart is not None:
        uart.close()
    try:
        if report['before_matches']:
            print('after', flush=True)
            report['after_matches'] = checksum('after')
    finally:
        try:
            run([flash, 'reset', *common], 'final-reset')
            report['final_reset'] = True
        finally:
            report['finished_at'] = time.time()
            report['pass'] = (report['before_matches'] and report['after_matches'] and
                              report['final_reset'] and len(report['cases']) == a.count and
                              all(c['completed'] and c['final_reset'] for c in report['cases']))
            save()
assert report['pass']
print('PASS: RAM IRQ observations; original full4MiB unchanged/reset', flush=True)
