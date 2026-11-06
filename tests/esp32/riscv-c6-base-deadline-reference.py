#!/usr/bin/env python3
"""C6 machine-code recovery checks using explicit clock and MMIO test peers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'qemu-c6', 'work'):
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--baseline-module', type=Path)
    p.add_argument('--lifetime', action='store_true', help='committed lifetime tail recovery with real IRQ/receipt transitions')
    a = p.parse_args()
    compiler, qemu, work = [x.resolve() for x in (a.compiler, a.qemu_c6, a.work)]
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    (work / 'tmp').mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), PYTHONDONTWRITEBYTECODE='1')

    def run(args, label):
        r = subprocess.run(list(map(str, ['nice', '-n', '19', *args])), cwd=ROOT, env=env, capture_output=True, timeout=120)
        (work / (label + '.log')).write_bytes(r.stdout + r.stderr)
        assert r.returncode == 0, (label, r.returncode, r.stderr[-2400:])

    module = (ROOT / 'lib/platform/esp32c6-radio-base.flex').read_text()
    fixture = (ROOT / 'tests/esp32/riscv-c6-base-deadline.flex').read_text()
    if a.lifetime:
        assert not a.baseline_module, 'baseline module has no lifetime-release API'
        seed = 'esp_radio_base_active=1;esp_radio_base_internal=0;'
        assert fixture.count(seed) == 1
        fixture = fixture.replace(seed, seed + 'esp_radio_base_releasing=1;esp_radio_base_configured=1;esp_radio_modem_configured=1;esp_radio_pmu_configured=1;')
        fixture = fixture.replace('esp_radio_c6_base_abort(', 'esp_radio_c6_base_release(')
        fixture = fixture.replace('if esp_radio_base_active ||', 'if esp_radio_base_releasing || esp_radio_base_configured || esp_radio_modem_configured || esp_radio_pmu_configured || esp_radio_base_active ||')
        fixture = fixture.replace('if !esp_radio_base_active ||', 'if !esp_radio_base_releasing || !esp_radio_base_configured || !esp_radio_modem_configured || !esp_radio_pmu_configured || !esp_radio_base_active ||')
    variants = [('protected', module, 0)]
    post = 'if ((esp32_cycles()-start)&0xffffffff)>=cycles{result= -110;}else{matched=observed==esp_radio_base_live;}'
    pre = 'if ((esp32_cycles()-start)&0xffffffff)>=cycles{result= -110;}\n    if !result{'
    assert module.count(post) == module.count(pre) == 1
    variants += [('late-read-accepted', module.replace(post, 'matched=observed==esp_radio_base_live;'), 117),
                 ('expired-read-issued', module.replace(pre, 'if !result{'), 2503)]
    if a.lifetime:
        clear = 'if esp_radio_base_releasing{esp_radio_base_configured=0;'
        result = 'esp_radio_base_internal=0;esp_radio_base_cleanup_error=result;'
        retry = 'if esp_radio_base_active{\n  if !esp_radio_base_releasing'
        assert module.count(clear) == module.count(result) == module.count(retry) == 1
        variants += [('flags-never-cleared', module.replace(clear, 'if 0{esp_radio_base_configured=0;'), 102),
                     ('flags-cleared-early', module.replace(result, 'if esp_radio_base_releasing{esp_radio_base_configured=0;esp_radio_modem_configured=0;esp_radio_pmu_configured=0;esp_radio_base_releasing=0;}' + result), 119),
                     ('retry-denied', module.replace(retry, 'if esp_radio_base_active{esp32_irq_restore(ps);return -16;\n  if !esp_radio_base_releasing'), 101)]
    if a.baseline_module:
        variants.append(('baseline', a.baseline_module.read_text(), 117))
    linker, alias = work / 'linker', work / 'empty.ld'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker], 'linker')
    alias.write_text('/* no external code */\n')
    rows = []
    for name, code, expected in variants:
        directory = work / name
        directory.mkdir()
        # Replace only these two observation boundaries in the real module.
        # All IRQ masking/restoration, guards and receipt updates remain real.
        code = code.replace('esp32_cycles()', 'deadline_cycles()').replace('esp32_load32(', 'deadline_load32(')
        code = re.sub(r'^import "([^"]+)";', lambda m: 'import ' + json.dumps(str(ROOT / 'lib/platform' / m[1])) + ';', code, flags=re.M)
        model_module = directory / 'base.flex'
        model_module.write_text(code)
        source = directory / 'fixture.flex'
        source.write_text('import ' + json.dumps(str(ROOT / 'lib/platform/esp32c6-xip.flex')) + ';\nimport ' + json.dumps(str(model_module)) + ';\n' + fixture)
        for target in ('esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf') if name == 'protected' else ('esp32c6-elf',):
            elf, linked, image, report = [directory / (target + n) for n in ('.elf', '-linked.elf', '.bin', '.json')]
            run([compiler, '--target', target, source, '-o', elf], name + '-' + target + '-build')
            args = [linker, '--ld', 'ld.lld', '--rom', alias, '--firmware', elf, '--output', linked, '--image', image]
            if target != 'esp32c6-elf':
                args += ['--xip']
            run(args, name + '-' + target + '-link')
            args = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', qemu, '--image', image, '--elf', linked, '--expected', expected, '--report', report]
            if target != 'esp32c6-elf':
                args += ['--xip']
            if target == 'esp32c6-radio-elf':
                args += ['--radio']
            run(args, name + '-' + target + '-ROM')
            row = json.loads(report.read_text())
            assert row['result'] == expected and not row['trapped']
            row.update(variant=name, target=target, clock_and_monitor='explicit test boundary', actual_PMU_MMIO=False)
            rows.append(row)
            print('PASS', name, target, expected, flush=True)
    result = dict(pass_all=True, cases=rows, C6_ROM_boots=len(rows), positive_profiles=3, boundary_cases_per_positive_profile=72, committed_lifetime=a.lifetime,
                  physical_hardware=False, silicon_timing=False, actual_PMU_MMIO=False, emulator_implementation_changes=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), production_module_sha256=hashlib.sha256(module.encode()).hexdigest(),
                  fixture_sha256=hashlib.sha256(fixture.encode()).hexdigest())
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS:', len(rows), 'native C6 recovery/profile checks; explicit clock/MMIO peers')


if __name__ == '__main__':
    main()
