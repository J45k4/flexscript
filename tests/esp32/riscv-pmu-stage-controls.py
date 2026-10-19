#!/usr/bin/env python3
"""Actual C3 domain/PHY guards for the shared PMU lease; no C6 MMIO proof."""
import argparse
import hashlib
import json
import runpy
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'qemu', 'reference', 'work']:
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    w = a.work.resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists()
    helper = runpy.run_path(str(ROOT / 'tests/esp32/lifecycle-preempt-reference.py'))
    source = w / 'source'
    manifest = helper['copy_closure'](ROOT / 'tests/esp32/riscv-regi2c-guards.flex', source)
    manifest.update(helper['copy_closure'](ROOT / 'scripts/esp32-link.flex', source))
    for name in ['tests/esp32/riscv-osi.c', 'tests/esp32/riscv-rom-peer.py']:
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    mutations = [
        ('domain-lease-ignored', 'esp32-radio-lifecycle-core.flex', 'esp_radio_resources_ready', 15),
        ('hardware-lease-ignored', 'esp32-riscv-radio-hardware.flex', 'esp_radio_hardware_deinit', 16),
        ('PHY-enable-lease-ignored', 'esp32-riscv-radio-phy.flex', 'esp_radio_phy_enable', 18),
        ('PHY-disable-lease-ignored', 'esp32-riscv-radio-phy.flex', 'esp_radio_phy_disable', 18),
        ('PHY-clock-lease-ignored', 'esp32-riscv-radio-hardware.flex', 'esp_radio_phy_clock', 18),
    ]
    cases = []
    for mutation in [None, *mutations]:
        name = mutation[0] if mutation else 'protected'
        tree = w / name / 'source'
        shutil.copytree(source, tree)
        if mutation:
            _, module, function, expected = mutation
            helper['change'](tree / 'lib/platform' / module, function,
                            lambda body: helper['once'](body, ' || esp_radio_pmu_active', ''))
        else:
            expected = 0
        output = w / name / 'run'
        r = subprocess.run(list(map(str, ['nice', '-n', '19', 'python3', ROOT / 'tests/esp32/riscv-osi-reference.py',
            '--compiler', a.compiler, '--qemu', a.qemu, '--reference', a.reference,
            '--work', output, '--source-root', tree, '--only-pmu', '--chip', 3, '--expected', expected])),
            cwd=ROOT, capture_output=True, timeout=60)
        (w / name / 'execution.log').write_bytes(r.stdout + r.stderr)
        assert r.returncode == 0, (name, r.stdout[-1500:], r.stderr[-2000:])
        row = json.loads((output / 'report.json').read_text())
        assert row['pass_all'] and row['C3_ROM_boots'] == 1
        case = row['cases'][0]
        assert case['result'] == expected
        cases.append(dict(name=name, expected_result=expected, actual_result=case['result'],
                          C3_ROM_boot=True, image_sha256=case['image_sha256']))
        print('PASS:', name, 'C3 terminal result', expected, flush=True)
    report = dict(pass_all=True, C3_ROM_boots=1, C3_deliberate_defect_boots=5,
                  C6_CPU_execution=False, physical_hardware=False, cases=cases,
                  source_sha256=manifest, compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest())
    (w / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
