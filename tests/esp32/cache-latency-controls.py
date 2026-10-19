#!/usr/bin/env python3
"""Reject consistently hashed bad timing/clock/cleanup captures;no board access."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('matrix', 'backup', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--backup-sha256', required=True)
p.add_argument('--post-kind', type=int, choices=(0, 3), default=0)
p.add_argument('--family', choices=('latency', 'mmu'), default='latency')
p.add_argument('--unmask-near', type=int, choices=(0, 1, 2), default=0)
p.add_argument('--matched-placement', type=int, choices=(0, 1), default=0)
p.add_argument('--late-op', choices=('ps', 'sar', 'ps-nop', 'rsil'), default='ps')
p.add_argument('--paired-matrix', type=Path)
p.add_argument('--prefix-sync', type=int, choices=(0, 1), default=0)
a = p.parse_args()
assert a.late_op == 'ps' or (a.family == 'mmu' and a.matched_placement and a.unmask_near == 2), 'alternate late op requires matched repeated-write profile'
assert bool(a.paired_matrix) == bool(a.matched_placement), 'matched placement requires an explicit paired matrix'
assert not a.matched_placement or (a.family == 'mmu' and not a.prefix_sync), 'matched placement is a separate MMU experiment'
assert a.unmask_near != 2 or a.matched_placement, 'repeated PS write requires matched placement'
assert a.family != 'mmu' or a.post_kind == 0
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
base = work / 'base'
assert not base.exists(), 'use a fresh control work directory'
for clock in (40, 160):
    for kind in ((0,) if a.family == 'mmu' else ((0, 1) if a.post_kind == 0 else (3,))):
        label = f'clock{clock}-kind{kind}'
        destination = base / label
        destination.mkdir(parents=True)
        source = a.matrix.resolve() / label
        for path in source.iterdir():
            if (path.suffix == '.elf' and 'unlinked' not in path.name) or path.name in ('manifest.json', 'native.json', 'native'):
                (destination / path.name).symlink_to(path)
first_group = f'clock40-kind{a.post_kind}'
shutil.copytree(a.matrix / first_group / 'physical-DROM', base / first_group / 'physical-DROM')


def validate(matrix, report):
    command = ['python3', root / 'tests/esp32/cache-latency-capture.py', '--allow-partial',
               '--matrix', matrix, '--backup', a.backup.resolve(),
               '--backup-sha256', a.backup_sha256, '--report', report]
    if a.family == 'mmu':
        command += ['--family', 'mmu', '--prefix-sync', str(a.prefix_sync), '--unmask-near', str(a.unmask_near), '--post-kinds', '0', '--matched-placement', str(a.matched_placement), '--late-op', a.late_op]
        if a.paired_matrix:
            command += ['--paired-matrix', a.paired_matrix.resolve()]
    elif a.post_kind == 3:
        command += ['--post-kinds', '3']
    return subprocess.run([str(x) for x in command], capture_output=True, timeout=10)


q = validate(base, work / 'positive.json')
assert q.returncode == 0, q.stderr
expected_word = int.from_bytes(a.backup.read_bytes()[0x1234:0x1238], 'little') if a.family == 'mmu' else 0xbad00bad
poison_word = next(v for v in (0, 0xffffffff, 0xaaaaaaaa) if v not in (expected_word, 0x13579bdf))
mutations = [
    ('ROM-delay-word-is-not-CPU-MHz', b'ROMTICKS', 40),
    ('LOAD-address-not-in-ELF', b'LOAD', 1),
    ('duplicate-IRQ', b'SEEN', 2),
    ('IRQ-not-acknowledged', b'AFTER', 2),
    ('wrong-enable-bit', b'EN', 1 << 14),
    ('unknown-interrupted-value', b'AR8', poison_word),
    ('wrong-final-progress', b'FINAL9', 9 if a.post_kind == 0 else 2),
    ('missing-completion', None, None),
    ('wrong-after-checksum', None, None),
    ('missing-case-reset-log', None, None),
]
controls = []
for label, field, value in mutations:
    directory = work / label
    shutil.copytree(base, directory, symlinks=True)
    batch = directory / first_group / 'physical-DROM'
    report_path = batch / 'physical.json'
    proof = json.loads(report_path.read_text())
    case = proof['cases'][0]
    uart = batch / 'bus0-mode0.uart'
    data = uart.read_bytes()
    if field is not None:
        first = data.index(('CACHE '+a.family.upper()+' BUS ').encode())
        prefix, body = data[:first], data[first:]
        body, count = re.subn(rb'\b' + field + rb' [0-9a-f]{16}',
                              field + f' {value:016x}'.encode(), body, count=1)
        assert count == 1
        data = prefix + body
    elif label == 'missing-completion':
        data = data.replace(('CACHE '+a.family.upper()+' COMPLETE').encode(), ('CACHE '+a.family.upper()+' OMITTED').encode())
    elif label == 'wrong-after-checksum':
        path = batch / 'after.log'
        text, count = re.subn(r'0x[0-9a-fA-F]{1,32}(?![0-9a-fA-F])', '0x0', path.read_text())
        assert count
        path.write_text(text)
    else:
        (batch / 'bus0-mode0-reset.log').unlink()
    uart.write_bytes(data)
    case['UART'] = data.decode()
    case['UART_sha256'] = hashlib.sha256(data).hexdigest()
    report_path.write_text(json.dumps(proof, indent=2) + '\n')
    q = validate(directory, work / (label + '.json'))
    assert q.returncode == 1 and q.stderr.rstrip().endswith(b'AssertionError'), (label, q.stdout, q.stderr)
    controls.append({'control': label, 'detected': True})
    print('Timing capture controls:', len(controls), flush=True)
a.report.write_text(json.dumps({'pass': True, 'physical_hardware_touched': False,
                                'controls': controls}, indent=2) + '\n')
print('PASS:10 consistently hashed invalid-timing/cleanup controls rejected')
