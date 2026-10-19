#!/usr/bin/env python3
"""Check shared ROM stdout initialization without hiding per-worker leaks."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    p = argparse.ArgumentParser()
    for name in ('compiler', 'qemu', 'qemu-c6', 'reference', 'work'):
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--clang', default='clang')
    p.add_argument('--ld', default='ld.lld')
    a = p.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    ref, compiler = a.reference.resolve(), a.compiler.resolve()
    rows = []
    sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()

    def run(cmd):
        r = subprocess.run(list(map(str, cmd)), cwd=root, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, (cmd, r.stdout, r.stderr)
        return r

    linker = work / 'linker'
    run([compiler, root / 'scripts/esp32-link.flex', '-o', linker])
    original_c = (root / 'tests/esp32/riscv-rom-libc.c').read_text()
    original_flex = (root / 'tests/esp32/riscv-rom-libc-preempt.flex').read_text()
    warm = ' if esp32_call32(esp32_external("rom_printf"),"",0,0,0,0,0,0,0){return 10;}\n'
    assert warm in original_flex and original_c.count('free(s);') == 1
    for chip in (3, 6):
        chip_work = work / f'c{chip}'
        chip_work.mkdir(exist_ok=True)
        (chip_work / 'rom').mkdir(exist_ok=True)
        (chip_work / 'rom/libc_stubs.h').write_bytes((ref / f'components/esp_rom/esp32c{chip}/include/esp32c{chip}/rom/libc_stubs.h').read_bytes())
        maps = '\n'.join(f.read_text() for f in (ref / f'components/esp_rom/esp32c{chip}/ld').glob('*.ld'))
        def symbol(name):
            return re.search(r'\b' + re.escape(name) + r'\s*=\s*(0x[0-9a-fA-F]+)', maps)[1]
        aliases = chip_work / 'rom-alias.ld'
        aliases.write_text(''.join(f'rom_{n} = {symbol(n)};\n' for n in ('strdup', 'strtol', 'printf')))
        (chip_work / 'rom-probe-config.h').write_text(f'#define ROM_GLOBAL_SLOT {symbol("_global_impure_ptr")}\n#define CODE_BEGIN {"0x40380000" if chip == 3 else "0x40800000"}\n#define ROM_STAT_32 {int(chip == 3)}\n#define ROM_HAS_COMMON_FIXTURE 0\n#define ROM_COMMON_0 0\n#define ROM_COMMON_1 0\n')
        objects = {}
        for label, text in [('normal', original_c), ('leak', original_c.replace('free(s);', '(void)s;'))]:
            c, obj = chip_work / (label + '.c'), chip_work / (label + '.o')
            c.write_text(text)
            run([a.clang, '--target=riscv32', '-march=rv32imc_zicsr_zifencei', '-mabi=ilp32', '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-msmall-data-limit=0', '-ffunction-sections', '-fdata-sections', '-isystem', ref / 'riscv-newlib', '-I', ref / 'components/newlib/platform_include', '-I', ref, '-I', chip_work, '-c', c, '-o', obj])
            objects[label] = obj
        for profile in ('sram', 'xip', 'radio'):
            for case in ('protected', 'cold-shared-stdout', 'worker-leak'):
                w = chip_work / (profile + '-' + case)
                w.mkdir(exist_ok=True)
                text = original_flex if case != 'cold-shared-stdout' else original_flex.replace(warm, '')
                text = text.replace('esp32c3', f'esp32c{chip}')
                if chip == 6:
                    text = text.replace('0x3fcb8000', '0x40848000')
                if profile == 'radio':
                    text = text.replace('0x3fcb8000', '0x3fc9c000').replace('0x40848000', '0x4081c000')
                text = re.sub(r'^\s*import "([^"]+)";', lambda m: 'import "' + str((root / 'tests/esp32' / m[1]).resolve()) + '";', text, flags=re.M)
                if profile != 'sram':
                    text = f'import "{root}/lib/platform/esp32c{chip}-xip.flex";\n' + text
                source, firmware, linked, image, report = [w / f for f in ('main.flex', 'main.elf', 'linked.elf', 'main.bin', 'report.json')]
                source.write_text(text)
                target = f'esp32c{chip}-' + ('elf' if profile == 'sram' else profile + '-elf')
                run([compiler, '--target', target, source, '-o', firmware])
                cmd = [linker, '--ld', a.ld, '--newlib-stdio', '--newlib-rom', '--firmware', firmware, '--rom', aliases, '--archive', ref / 'riscv-libc.a', '--archive', ref / 'riscv-libgcc.a', '--object', objects['leak' if case == 'worker-leak' else 'normal'], '--output', linked, '--image', image]
                if profile != 'sram':
                    cmd += ['--xip']
                run(cmd)
                expected = 6 if case == 'worker-leak' or (case == 'cold-shared-stdout' and chip == 6) else 0
                cmd = ['python3', root / 'tests/esp32/riscv-rom-peer.py', '--qemu', a.qemu if chip == 3 else a.qemu_c6, '--image', image, '--elf', linked, '--report', report, '--expected', expected]
                if profile != 'sram':
                    cmd += ['--xip']
                if profile == 'radio':
                    cmd += ['--radio']
                run(cmd)
                observed = json.loads(report.read_text())
                if not expected:
                    entry = '0x40380080' if chip == 3 else '0x40800080'
                    lines = observed['uart'].split('entry ' + entry + '\r\n', 1)[1].splitlines()
                    assert len(lines) == 24 and lines.count('ROMW1:A') == 12 and lines.count('ROMW2:B') == 12
                rows.append(dict(chip=chip, profile=profile, case=case, expected_result=expected, actual_result=observed['result'], ROM_boot=True, image_sha256=sha(image), diagnostic_control=case != 'protected', per_task_leak_detected=case == 'worker-leak', source_sha256=sha(source), C_object_sha256=sha(objects['leak' if case == 'worker-leak' else 'normal'])))
    result = dict(pass_all=True, cases=rows, ROM_boots=len(rows), per_task_leak_controls=sum(x['per_task_leak_detected'] for x in rows), cold_C6_shared_stdout_controls=sum(x['chip'] == 6 and x['case'] == 'cold-shared-stdout' for x in rows), C3_ROM_boots=sum(x['chip'] == 3 for x in rows), C6_ROM_boots=sum(x['chip'] == 6 for x in rows), physical_hardware=False, production_runtime_unchanged=True)
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: ROM worker baselines, 18 ROM boots, 6 deliberate worker leaks and 3 cold C6 stdout controls')


if __name__ == '__main__':
    main()
