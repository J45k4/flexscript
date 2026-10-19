#!/usr/bin/env python3
"""Execute C6 native-heap PMU exhaustion across SRAM and cached profiles.

Uses the supplied existing ROM runner. No PMU/analog or physical-board proof.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'qemu', 'work']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--ld', default='ld.lld')
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    compiler, qemu = args.compiler.resolve(), args.qemu.resolve()

    def run(command):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=60)
        assert result.returncode == 0, (command, result.stdout[-2000:], result.stderr[-2000:])

    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    aliases = work / 'empty.ld'
    aliases.write_text('/* No vendor objects or external imports. */\n')
    original = (ROOT / 'tests/esp32/riscv-pmu-stage-native-oom.flex').read_text()
    original = original.replace('../../lib/', str(ROOT / 'lib') + '/')
    cases = []
    for target in ['esp32c6', 'esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf']:
        cached = '-xip-' in target or '-radio-' in target
        for reserve in [0, 408]:
            name = target + '-' + str(reserve)
            source = work / (name + '.flex')
            text = original.replace('let reserve=0;', 'let reserve=' + str(reserve) + ';')
            if cached:
                text = 'import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\n' + text
            source.write_text(text)
            image = work / (name + '.bin')
            elf = work / (name + '.elf')
            linked = work / (name + '-linked.elf')
            run([compiler, '--target', target, source, '-o', elf if '-elf' in target else image])
            if '-elf' in target:
                command = [linker, '--ld', args.ld, '--rom', aliases, '--firmware', elf,
                           '--output', linked, '--image', image]
                if cached:
                    command += ['--xip']
                run(command)
            report = work / (name + '.json')
            command = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', qemu,
                       '--image', image, '--report', report]
            if '-elf' in target:
                command += ['--elf', linked]
            if cached:
                command += ['--xip']
            if '-radio-' in target:
                command += ['--radio']
            run(command)
            case = json.loads(report.read_text())
            assert case['ROM_boot'] and not case['trapped'] and case['result'] == 0
            cases.append(dict(target=target, remaining_native_heap=reserve, IRQ_modes=2,
                              refusals_per_IRQ_mode=3, image_sha256=case['image_sha256']))
    result = dict(pass_all=True, C6_ROM_boots=len(cases), cases=cases,
                  real_native_heap_exhaustion=True, physical_hardware=False,
                  PMU_analog_operation_verified=False, full_C6_power_clock_startup=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS:', len(cases), 'C6 PMU native-heap exhaustion boots; both IRQ states; no physical/PMU claim')


if __name__ == '__main__':
    main()
