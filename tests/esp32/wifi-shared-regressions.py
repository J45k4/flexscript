#!/usr/bin/env python3
"""Rebuild independent peers and check both existing Xtensa Wi-Fi facades."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'qemu', 'prefix', 's3-prefix', 'include', 'work']:
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    w = Path(a.work).resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists()

    def run(cmd, label):
        r = subprocess.run(list(map(str, cmd)), cwd=ROOT, capture_output=True, timeout=180)
        (w / (label + '.log')).write_bytes(r.stdout + r.stderr)
        assert r.returncode == 0, (label, (r.stdout + r.stderr)[-2000:])
        print(label, 'PASS', flush=True)

    driver = w / 'driver'
    run([a.compiler, ROOT / 'scripts/test-esp32-preempt.flex', '-o', driver], 'driver-build')
    common = ['-Os', '-fno-builtin', '-mlongcalls', '-mtext-section-literals']
    for prefix, source, output, extra in [
        (a.s3_prefix, 's3-wifi-lifecycle-fixture', 's3-peer.o',
         ['-fno-inline', '-fno-optimize-sibling-calls', '-I', a.include,
          '-include', Path(a.include) / 'oracle-types.h']),
        (a.prefix, 'radio-lifecycle-fixture', 'original-peer.o', []),
        (a.prefix, 'masked-waits-fixture', 'masked-peer.o', []),
        (a.prefix, 'wifi-control-fixture', 'control-peer.o', []),
        (a.prefix, 'wifi-ownership-fixture', 'ownership-peer.o', []),
    ]:
        run([prefix + 'gcc', *common, *extra, '-c', ROOT / 'tests/esp32/abi-oracle' / (source + '.c'),
             '-o', w / output], source + '-build')
    base = ['--compiler', a.compiler, '--driver', driver, '--qemu', a.qemu]
    run(['python3', ROOT / 'tests/esp32/s3-wifi-controls.py', *base, '--prefix', a.s3_prefix,
         '--peer', w / 's3-peer.o', '--original-prefix', a.prefix, '--original-peer', w / 'original-peer.o',
         '--work', w / 'station'], 'station')
    for label, script, obj in [
        ('masked', 'masked-waits-controls.py', 'masked-peer.o'),
        ('control', 'wifi-control-controls.py', 'control-peer.o'),
        ('ownership', 'wifi-ownership-controls.py', 'ownership-peer.o'),
    ]:
        run(['python3', ROOT / 'tests/esp32' / script, *base, '--prefix', a.prefix,
             '--c-object', w / obj, '--work', w / label], label)
    reports = {label: json.loads((w / label / 'report.json').read_text())
               for label in ['station', 'masked', 'control', 'ownership']}
    assert all(row['pass_all'] for row in reports.values())
    (w / 'report.json').write_text(json.dumps(dict(pass_all=True, reports=reports,
        physical_hardware=False, emulator_changes=False), indent=2) + '\n')


if __name__ == '__main__':
    main()
