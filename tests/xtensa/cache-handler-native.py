#!/usr/bin/env python3
"""Run the isolated RAM cache-error handler probes in the native emulator.

Requires explicit immutable probe/ROM/NOR inputs. No hardware access.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('runner', 'manifest', 'rom', 'nor', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--nor-sha256', required=True)
p.add_argument('--family', choices=('handler', 'restart', 'latency', 'mmu'), default='handler')
a = p.parse_args()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(a.rom) == '9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
assert a.nor.stat().st_size == 4194304 and sha(a.nor) == a.nor_sha256
manifest = json.loads(a.manifest.read_text())
assert [(c['bus'], c['mode']) for c in manifest] == [(b, m) for b in range(2) for m in range(4)]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
rows = []
for c in manifest:
    label = f"bus{c['bus']}-mode{c['mode']}"
    elf = (a.manifest.parent / c['elf']).resolve()
    assert sha(elf) == c['sha256']
    uart = work / (label + '.uart')
    command = [a.runner.resolve(), elf, uart, '--rom', a.rom.resolve(),
               '--flash-nor', a.nor.resolve(), '--download-clock', '--fuel', '200000000']
    q = subprocess.run([str(x) for x in command], capture_output=True, timeout=20)
    (work / (label + '.stdout')).write_bytes(q.stdout)
    (work / (label + '.stderr')).write_bytes(q.stderr)
    assert q.returncode == 0 and not q.stderr and b'PASS board firmware:' in q.stdout, (label, q)
    data = uart.read_bytes()
    marker = f"CACHE {a.family.upper()} COMPLETE {c['bus']:016x} MODE {c['mode']:016x}\r\n".encode()
    assert data.endswith(marker) and b' FAIL' not in data
    rows.append({'bus': c['bus'], 'mode': c['mode'], 'pass': True,
                 'ELF_sha256': sha(elf), 'UART_sha256': sha(uart),
                 'stdout_sha256': hashlib.sha256(q.stdout).hexdigest()})
    print(label + ': complete', flush=True)
assert sha(a.nor) == a.nor_sha256
report = {'pass': True, 'probe_family': a.family, 'physical_hardware': False, 'cases': rows,
          'runner_sha256': sha(a.runner), 'ROM_sha256': sha(a.rom),
          'NOR_sha256': a.nor_sha256, 'NOR_unchanged': True,
          'manifest_sha256': sha(a.manifest)}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:8 native cache IRQ probes (' + a.family + ')')
