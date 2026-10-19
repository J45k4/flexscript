#!/usr/bin/env python3
"""Check the IRQ capture validator rejects consistently hashed bad evidence.

All mutations are private copies of supplied captures. No device access.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('manifest', 'backup', 'native', 'native-report', 'drom', 'irom', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--backup-sha256', required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
validator = root / 'tests/esp32/cache-handler-capture.py'


def command(drom, report):
    return ['python3', str(validator), '--manifest', str(a.manifest.resolve()),
            '--backup', str(a.backup.resolve()), '--backup-sha256', a.backup_sha256,
            '--native', str(a.native.resolve()), '--native-report', str(a.native_report.resolve()),
            '--batch', str(drom), '--batch', str(a.irom.resolve()), '--report', str(report)]


q = subprocess.run(command(a.drom.resolve(), work / 'positive.json'), capture_output=True, timeout=10)
assert q.returncode == 0, q.stderr
mutations = [
    ('duplicate-callback', 0, b'SEEN', 2),
    ('wrong-returned-data', 0, b'VALUE', 0xbaadbaad),
    ('unacknowledged-interrupt', 0, b'AFTER', 2),
    ('wrong-interrupt-enable', 0, b'EN', 1 << 14),
    ('EPC-outside-executable-segments', 0, b'PC', 0x4009fff0),
    ('callback-in-negative-case', 3, b'SEEN', 1),
    ('missing-completion', 0, None, None),
    ('wrong-after-flash-digest', None, None, None),
    ('reset-not-completed', None, None, None),
]
controls = []
for label, mode, field, value in mutations:
    directory = work / label
    batch = directory / 'physical'
    assert not batch.exists(), 'use a fresh controls work directory'
    shutil.copytree(a.drom, batch)
    report_path = batch / 'physical.json'
    report = json.loads(report_path.read_text())
    if mode is not None:
        case = next(c for c in report['cases'] if c['bus'] == 0 and c['mode'] == mode)
        uart = batch / f'bus0-mode{mode}.uart'
        data = uart.read_bytes()
        if field is not None:
            data, count = re.subn(rb'\b' + field + rb' [0-9a-f]{16}',
                                  field + f' {value:016x}'.encode(), data, count=1)
            assert count == 1
        else:
            assert b'CACHE HANDLER COMPLETE' in data
            data = data.replace(b'CACHE HANDLER COMPLETE', b'CACHE HANDLER OMITTED')
        uart.write_bytes(data)
        case['UART'] = data.decode()
        case['UART_sha256'] = hashlib.sha256(data).hexdigest()
    elif label == 'reset-not-completed':
        report['final_reset'] = False
    else:
        log = batch / 'after.log'
        text = log.read_text()
        text, count = re.subn(r'0x[0-9a-fA-F]{1,32}(?![0-9a-fA-F])', '0x0', text)
        assert count
        log.write_text(text)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    q = subprocess.run(command(batch, directory / 'result.json'), capture_output=True, timeout=10)
    assert q.returncode == 1 and q.stderr.rstrip().endswith(b'AssertionError'), (label, q)
    controls.append({'control': label, 'detected': True})
    print('Capture controls:', len(controls), flush=True)
a.report.write_text(json.dumps({'pass': True, 'physical_hardware': False,
                                'controls': controls}, indent=2) + '\n')
print('PASS:9 consistently hashed bad-capture controls rejected')
