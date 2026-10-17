#!/usr/bin/env python3
"""Replay unchanged cached streaming/recovery firmware with its physical wiring.

The checkpoint owns ELF/NOR/capture hashes. This runner supplies the real
GPIO21-GPIO25 jumper as an explicit emulator wire. No physical board is accessed.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('runner', 'checkpoint', 'rom', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
a = p.parse_args()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
base = a.checkpoint.resolve()
proof = json.loads((base / 'report.json').read_text())
assert proof['checkpoint_verified'] and proof['physical_hardware']
artifacts = json.loads((base / 'artifact-sha256.json').read_text())
assert sha(a.rom) == '9115bbcd03da9f54d3baca5ad94d588a43da54ed332347137ba3dc9010df258b'
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
rows = []
runner_hash = sha(a.runner)
for kind in ('stream', 'recovery'):
    elf, nor = base / 'images' / (kind + '.elf'), base / 'images' / (kind + '-NOR.bin')
    reference = base / 'images' / (kind + '.uart')
    physical = base / 'physical' / kind / 'uart.bin'
    physical_proof = json.loads((base / 'physical' / kind / 'physical.json').read_text())
    for path in (elf, nor, reference, physical):
        assert sha(path) == artifacts[str(path.relative_to(base))], path
    assert sha(elf) == proof['firmware'][kind]['ELF_sha256']
    assert sha(reference) == proof['firmware'][kind]['UART_sha256']
    assert physical_proof['pass'] and physical_proof['restored'] and physical_proof['final_reset']
    assert sha(physical) == physical_proof['UART_sha256']
    assert sha(reference) == physical_proof['native_UART_sha256'] and physical_proof['native_UART_matches']
    # Physical capture includes ROM boot/loader output before application entry.
    # Preserve it whole and bind the exact complete application suffix explicitly.
    assert physical.read_bytes().endswith(reference.read_bytes())
    assert physical.read_bytes().count(reference.read_bytes()) == 1
    assert proof['firmware'][kind]['full4MiB_restored_and_verified'] and proof['firmware'][kind]['final_reset']
    uart = work / (kind + '.uart')
    command = [a.runner.resolve(), elf, uart, '21', '25', '--rom', a.rom.resolve(),
               '--flash-nor', nor, '--download-clock', '--fuel', '200000000']
    q = subprocess.run([str(x) for x in command], capture_output=True, timeout=300)
    (work / (kind + '.stdout')).write_bytes(q.stdout)
    (work / (kind + '.stderr')).write_bytes(q.stderr)
    assert q.returncode == 0 and not q.stderr and b'PASS board firmware:' in q.stdout, (kind, q.returncode, q.stdout, q.stderr)
    assert uart.read_bytes() == reference.read_bytes(), (kind, 'complete silicon UART mismatch')
    assert sha(a.runner) == runner_hash and sha(nor) == artifacts[str(nor.relative_to(base))]
    rows.append({'case': kind, 'same_physical_ELF': True, 'ELF_sha256': sha(elf),
                 'NOR_sha256': sha(nor), 'UART_identical_to_saved_silicon': True,
                 'UART_sha256': sha(uart), 'stdout': q.stdout.decode()})
    print(kind + ': ' + q.stdout.decode().strip(), flush=True)
a.report.write_text(json.dumps({'pass': True, 'physical_hardware_touched': False,
    'virtual_wire': [21, 25], 'runner_sha256': runner_hash, 'cases': rows}, indent=2) + '\n')
print('PASS:full continuous-stream and fault-recovery UARTs match silicon')
