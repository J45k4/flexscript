#!/usr/bin/env python3
"""Run the authorized32-image IRQ timing matrix in guarded batches of four.

No aggregate timeout kills an active child's cleanup. Signals are forwarded
and the parent waits for the child's checksum/reset finally path to finish.
"""
import argparse
import hashlib
import json
import re
import signal
import subprocess
import time
from pathlib import Path
from elf32_symbols import elf32_symbols, mmu_probe_profile, mmu_paired_matrix

p = argparse.ArgumentParser(description=__doc__)
for name in ('matrix', 'backup', 'espflash', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--port', required=True)
p.add_argument('--family', choices=('latency', 'mmu'), default='latency')
p.add_argument('--unmask-near', type=int, choices=(0, 1, 2), default=0)
p.add_argument('--matched-placement', type=int, choices=(0, 1), default=0)
p.add_argument('--late-op', choices=('ps', 'sar', 'ps-nop', 'rsil'), default='ps')
p.add_argument('--paired-matrix', type=Path)
p.add_argument('--prefix-sync', type=int, choices=(0, 1), default=0)
p.add_argument('--backup-sha256', required=True)
p.add_argument('--first-batch', type=int, default=0)
p.add_argument('--count-batches', type=int)
p.add_argument('--post-kinds', type=int, choices=(0, 1, 2, 3, 4, 5, 6), nargs='+', default=[0, 1])
p.add_argument('--buses', type=int, choices=(0, 1), nargs='+', default=[0, 1])
a = p.parse_args()
assert a.late_op == 'ps' or (a.family == 'mmu' and a.matched_placement and a.unmask_near == 2), 'alternate late op requires matched repeated-write profile'
assert bool(a.paired_matrix) == bool(a.matched_placement), 'matched placement requires an explicit paired matrix'
assert not a.matched_placement or (a.family == 'mmu' and not a.prefix_sync), 'matched placement is a separate MMU experiment'
assert a.unmask_near != 2 or a.matched_placement, 'repeated PS write requires matched placement'
assert not a.unmask_near or (a.family == 'mmu' and not a.prefix_sync), 'unmask-near is a separate MMU experiment'
assert not a.prefix_sync or a.family == 'mmu', 'prefix-sync is an MMU experiment'
assert a.family != 'mmu' or a.post_kinds == [0], 'MMU sweep requires post-kind0'
assert len(set(a.post_kinds))==len(a.post_kinds) and len(set(a.buses))==len(a.buses)
root = Path(__file__).resolve().parents[2]
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert a.backup.stat().st_size == 4194304 and sha(a.backup) == a.backup_sha256
batches = []
for clock in (40, 160):
    for kind in a.post_kinds:
        folder = a.matrix.resolve() / f'clock{clock}-kind{kind}'
        manifest = folder / 'manifest.json'
        cases = json.loads(manifest.read_text())
        native = json.loads((folder / 'native.json').read_text())
        assert native['pass'] and native['probe_family'] == a.family and native['NOR_unchanged']
        assert native['NOR_sha256'] == a.backup_sha256 and native['manifest_sha256'] == sha(manifest)
        assert [(c['bus'], c['mode']) for c in cases] == [(b, m) for b in range(2) for m in range(4)]
        assert len(native['cases']) == 8
        for bus in (0, 1):
            assert {elf32_symbols((folder / c['elf']).read_bytes())['cr_load'] & 3
                    for c in cases if c['bus'] == bus} == {0, 1, 2, 3}
        if kind >= 3:
            for c in cases:
                symbols = elf32_symbols((folder / c['elf']).read_bytes())
                assert symbols['cr_enable'] == symbols['cr_after'] + 24 + (kind >= 5) * 3, 'settled enable edge required'
        if a.matched_placement:
            mmu_paired_matrix(folder, a.paired_matrix.resolve() / folder.name, a.unmask_near, a.backup_sha256, a.late_op)
        for c, n in zip(cases, native['cases']):
            assert c['clock_mhz'] == clock and c['post_kind'] == kind
            if a.family == 'mmu':
                assert c['fault'] == 'mmu-invalid'
                assert c.get('prefix_sync', 0) == a.prefix_sync
                assert c.get('unmask_near', 0) == a.unmask_near
                assert c.get('late_op', 'ps') == a.late_op
                assert c.get('matched_placement', 0) == a.matched_placement
                mmu_probe_profile((folder / c['elf']).read_bytes(), a.prefix_sync, a.unmask_near, a.matched_placement, a.late_op)
            assert sha(folder / c['elf']) == c['sha256'] == n['ELF_sha256'] and n['pass']
            if kind >= 5:
                uart = folder / 'native' / f"bus{c['bus']}-mode{c['mode']}.uart"
                assert sha(uart) == n['UART_sha256']
                stamps = re.findall(rb' STARTCC ([0-9a-f]{16}) IRQCC ([0-9a-f]{16})\r\n', uart.read_bytes())
                assert len(stamps) == 1, 'native timestamp fields required beforedevice access'
                start, interrupt = (int(v, 16) for v in stamps[0])
                assert start <= 0xffffffff and interrupt <= 0xffffffff
                assert 0 < ((interrupt-start)&0xffffffff) < 1000000
        for bus in a.buses:
            batches.append((folder, bus * 4, folder / ('physical-DROM' if bus == 0 else 'physical-IROM')))
if a.count_batches is None:
    a.count_batches = len(batches)-a.first_batch
assert 0 <= a.first_batch < len(batches) and 1 <= a.count_batches <= len(batches)-a.first_batch
selected = batches[a.first_batch:a.first_batch + a.count_batches]
assert all(not destination.exists() for folder, first, destination in selected), 'use fresh batch destinations'
report = {'pass': False, 'ram_only': True, 'flash_write_requested': False,
          'matched_placement': a.matched_placement, 'late_op': a.late_op, 'unmask_near': a.unmask_near,
          'started_at': time.time(), 'first_batch': a.first_batch,
          'count_batches': a.count_batches, 'batches': []}
active = None
stopping = False


def save():
    a.report.write_text(json.dumps(report, indent=2) + '\n')


def interrupted(signum, frame):
    global stopping
    stopping = True
    if active is not None and active.poll() is None:
        active.send_signal(signal.SIGTERM)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    for index, (folder, first, destination) in enumerate(selected, a.first_batch):
        if stopping:
            raise InterruptedError('matrix stopped after child cleanup')
        print(f'BATCH {index + 1}/{len(batches)} {folder.name} first={first}', flush=True)
        command = ['python3', root / 'tests/esp32/cache-handler-physical.py',
                   '--family', a.family, '--manifest', folder / 'manifest.json',
                   '--backup', a.backup.resolve(), '--backup-sha256', a.backup_sha256,
                   '--port', a.port, '--espflash', a.espflash.resolve(),
                   '--first', str(first), '--count', '4', '--work', destination]
        active = subprocess.Popen([str(x) for x in command])
        code = active.wait()
        active = None
        proof = json.loads((destination / 'physical.json').read_text())
        report['batches'].append({'index': index, 'directory': str(destination),
                                  'exit_code': code, 'pass': proof['pass'],
                                  'full4MiB_unchanged': proof['before_matches'] and proof['after_matches'],
                                  'final_reset': proof['final_reset']})
        save()
        assert code == 0 and proof['pass'] and proof['final_reset'], ('batch failed', destination)
finally:
    if active is not None and active.poll() is None:
        active.send_signal(signal.SIGTERM)
        active.wait()
    report['finished_at'] = time.time()
    report['pass'] = (not stopping and len(report['batches']) == a.count_batches and
                      all(b['pass'] and b['full4MiB_unchanged'] and b['final_reset']
                          for b in report['batches']))
    save()
assert report['pass']
print('PASS: selected IRQ timing batches complete;each originalfull4MiB unchanged/reset', flush=True)
