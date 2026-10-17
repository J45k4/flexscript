#!/usr/bin/env python3
"""Replay the exact ECO3 RAM probes against saved silicon UART observations.

Uses an explicit runner, original ROM and read-only NOR backup. No board access.
Blocked cases must produce a blocked-transaction exit, never a timeout or pass.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
for name in ('runner', 'reference', 'rom', 'nor', 'work', 'report'):
    parser.add_argument('--' + name, type=Path, required=True)
parser.add_argument('--nor-sha256', required=True)
a = parser.parse_args()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
ref = a.reference.resolve()
proof = json.loads((ref / 'report.json').read_text())
assert proof['observations_verified'] and proof['all_flash_checks_and_resets_verified']
assert proof['completed'] == 8 and proof['stalled_read_observations'] == 8
assert sha(a.rom) == '9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
assert a.nor.stat().st_size == 4194304 and sha(a.nor) == a.nor_sha256
manifest = json.loads((ref / 'images/manifest.json').read_text())
assert [(v['bus'], v['mode']) for v in manifest] == [(b, m) for b in range(2) for m in range(8)]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
results = []
for item, observed in zip(manifest, proof['cases']):
    bus, mode = item['bus'], item['mode']
    assert (bus, mode) == (observed['bus'], observed['mode'])
    label = f'bus{bus}-mode{mode}'
    elf = ref / 'images' / item['elf']
    assert sha(elf) == item['sha256'] == observed['image_sha256']
    captures = list((ref / 'physical').glob('*/' + label + '.uart'))
    assert len(captures) == 1
    capture = captures[0]
    assert sha(capture) == observed['UART_sha256']
    uart = work / (label + '.uart')
    command = [a.runner.resolve(), elf, uart, '--rom', a.rom.resolve(),
               '--flash-nor', a.nor.resolve(), '--download-clock',
               '--fuel', '200000000']
    q = subprocess.run([str(p) for p in command], capture_output=True, timeout=20)
    (work / (label + '.stdout')).write_bytes(q.stdout)
    (work / (label + '.stderr')).write_bytes(q.stderr)
    if observed['completed']:
        assert q.returncode == 0 and b'PASS board firmware:' in q.stdout and not q.stderr, (label, q)
    else:
        assert q.returncode == 11 and q.stderr == b'Cached read blocked before retirement\n', (label, q)
        assert b'PASS board firmware:' not in q.stdout
    assert uart.read_bytes() == capture.read_bytes(), (label, 'silicon UART mismatch')
    results.append({'bus': bus, 'mode': mode, 'same_physical_ELF': True,
                    'ELF_sha256': sha(elf), 'UART_sha256': sha(uart),
                    'UART_identical_to_silicon': True, 'completed': observed['completed'],
                    'blocked_exit': q.returncode == 11})
    print(label + ': ' + ('complete' if q.returncode == 0 else 'blocked') + ', silicon UART identical', flush=True)
assert sha(a.nor) == a.nor_sha256
report = {'pass': True, 'scope_complete': False, 'physical_hardware_touched': False,
          'cases': results, 'completions': 8, 'blocked_reads': 8,
          'runner_sha256': sha(a.runner), 'rom_sha256': sha(a.rom),
          'NOR_sha256': a.nor_sha256, 'NOR_unchanged': True,
          'limitations': 'RAM-only data-access probes. Actual cache IRQ-handler '
                        'delivery, instruction-error behavior, CPU1, replacement '
                        'and timing remain separate verification gates.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:16 exact firmware/silicon UART comparisons;8 complete,8 blocked')
