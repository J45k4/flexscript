#!/usr/bin/env python3
"""Check pinned WPA metadata, primary Wi-Fi section policy and tool preservation."""
import argparse
import hashlib
import json
import os
import re
import runpy
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    ref, w, compiler = a.reference.resolve(), a.work.resolve(), a.compiler.resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists()
    elf = runpy.run_path(str(ROOT / 'tests/esp32/s3-ftm-reference.py'))
    sha = lambda f: hashlib.sha256(Path(f).read_bytes()).hexdigest()

    def run(cmd, reject=False, match=None):
        r = subprocess.run(list(map(str, cmd)), cwd=ROOT, capture_output=True, timeout=60)
        assert (r.returncode != 0 if reject else r.returncode == 0), (cmd, r.stdout[-1500:], r.stderr[-2000:])
        if match:
            assert match.encode() in r.stdout + r.stderr, (match, r.stdout, r.stderr)
        return r.stdout

    builder, linker = w / 'builder', w / 'linker'
    run([compiler, ROOT / 'scripts/build-esp32-radio.flex', '-o', builder])
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    records, rejections, policy = [], [], []
    # Enumerate section families from the independent pinned linker fragment.
    primary = (ref / 'wifi-primary/components-esp_wifi-linker.lf').read_text()
    families = re.findall(r'\[sections:wifi_[^\]]+\]\nentries:\n    (\.\w+iram)\+', primary)
    assert len(families) == 6 and len(set(families)) == 6
    for family in families:
        name = re.search(r'\[sections:(\w+)\]\nentries:\n    ' + re.escape(family) + r'\+', primary)[1]
        assert name + ' -> flash_text' in primary.split('[scheme:wifi_default]')[1].split('[mapping:')[0]
    assert '* (noflash_data)' in (ref / 'wifi-primary/components-esp_phy-linker.lf').read_text()
    for chip in [3, 6]:
        d = w / f'c{chip}'
        d.mkdir()
        archive = ref / f'vendor/esp32c{chip}/libwpa_supplicant.a'
        before = sha(archive)
        transformed = d / 'wpa-lifecycle.a'
        run(['llvm-objcopy', '--globalize-symbol=eloop_data_lock', archive, transformed])
        members = run(['llvm-ar', 't', archive]).decode().splitlines()
        assert len(members) == len(set(members))
        assert members == run(['llvm-ar', 't', transformed]).decode().splitlines()
        allocated = 0
        for member in members:
            original = run(['llvm-ar', 'p', archive, member])
            visible = run(['llvm-ar', 'p', transformed, member])
            def alloc(data):
                _, sections = elf['sections'](data)
                return {n: (s[1:4], s[5], b'' if s[1] == 8 else data[s[4]:s[4] + s[5]])
                        for n, s in sections.items() if s[2] & 2}
            assert alloc(original) == alloc(visible), member
            allocated += len(alloc(original))
        original_symbols = run(['llvm-nm', '--extern-only', '--defined-only', '-P', archive]).decode()
        visible_symbols = run(['llvm-nm', '--extern-only', '--defined-only', '-P', transformed]).decode()
        assert not re.search(r'^eloop_data_lock ', original_symbols, re.M)
        assert re.search(r'^eloop_data_lock [BD] ', visible_symbols, re.M)
        assert sha(archive) == before
        records.append(dict(chip=chip, members=len(members), allocated_sections_preserved=allocated,
                            input_sha256=before, private_mutex_exported=True))

        # Both plain and dotted optional sections must follow flash policy;
        # mandatory .iram1/.phyiram and libphy readonly data keep SRAM placement.
        section_names = [f + tail for f in families for tail in ['', '.probe']]
        csource = d / 'policy.c'
        csource.write_text('#include <stdint.h>\n' + ''.join(
            f'__attribute__((section("{section}"),noinline)) uint32_t optional{i}(void){{return {i};}}\n'
            for i, section in enumerate(section_names)) +
            '__attribute__((section(".iram1.probe"),noinline)) uint32_t mandatory_iram(void){return 7;}\n'
            '__attribute__((section(".phyiram.probe"),noinline)) uint32_t mandatory_phy(void){return 9;}\n'
            'const uint32_t phy_policy_rodata=0x12345678;\n')
        obj = d / 'policy.o'
        run(['clang', '--target=riscv32', '-mabi=ilp32', '-march=rv32imc', '-Os', '-c', csource, '-o', obj])
        libphy = d / 'libphy.a'
        run(['llvm-ar', 'rcs', libphy, obj])
        source = d / 'policy.flex'
        source.write_text(f'import "{ROOT}/lib/platform/esp32c{chip}-radio-os.flex";\nfn main(){{let sum=0;' +
            ''.join(f'sum=sum+esp32_call32(esp32_external("optional{i}"),0,0,0,0,0,0,0,0);' for i in range(12)) +
            'sum=sum+esp32_call32(esp32_external("mandatory_iram"),0,0,0,0,0,0,0,0);' +
            'sum=sum+esp32_call32(esp32_external("mandatory_phy"),0,0,0,0,0,0,0,0);' +
            'return sum+esp32_load32(esp32_external("phy_policy_rodata"));}\n')
        fw, linked = d / 'native.elf', d / 'linked.elf'
        run([compiler, '--target', f'esp32c{chip}-radio-elf', source, '-o', fw])
        run([linker, '--ld', 'ld.lld', '--xip', '--firmware', fw, '--archive', libphy, '--output', linked])
        data = linked.read_bytes()
        table = elf['symbol_table'](data)
        rows, sections = elf['sections'](data)
        def section_for(name):
            at = table[name][3]
            return rows[struct.unpack_from('<H', data, at + 14)[0]]
        assert all(section_for('optional' + str(i)) == sections['.irom'] for i in range(12))
        assert section_for('mandatory_iram') == section_for('mandatory_phy') == sections['.text']
        assert section_for('phy_policy_rodata') == sections['.data']
        policy.append(dict(chip=chip, optional_flash_sections=section_names,
                           mandatory_code_in_IRAM=True, PHY_readonly_data_in_DRAM=True))

        overflow_source = d / 'overflow.flex'
        overflow_source.write_text(source.read_text().replace('return sum+',
            'return esp32_external("overflow")+sum+'))
        overflow_fw = d / 'overflow.elf'
        run([compiler, '--target', f'esp32c{chip}-radio-elf', overflow_source, '-o', overflow_fw])
        for label, section, flags, size, message in [
            ('IRAM', '.iram1.overflow', 'ax', 65536, 'vendor code exceeds available IRAM'),
            ('PHY-DRAM', '.rodata.overflow', 'a', 32768, 'vendor data overlaps reserved SRAM'),
        ]:
            folder = d / label
            folder.mkdir()
            assembly = folder / 'overflow.S'
            assembly.write_text(f'.section {section},"{flags}"\n.global overflow\noverflow:\n.space {size}\n')
            overflow_obj = folder / 'overflow.o'
            run(['clang', '--target=riscv32', '-march=rv32imc', '-mabi=ilp32', '-c', assembly, '-o', overflow_obj])
            bad_phy = folder / 'libphy.a'
            run(['llvm-ar', 'rcs', bad_phy, obj, overflow_obj])
            preserved = [folder / n for n in ['linked.elf', 'firmware.bin', 'linked.map']]
            for file in preserved:
                file.write_bytes(b'preserve existing link output')
            run([linker, '--ld', 'ld.lld', '--xip', '--firmware', overflow_fw, '--archive', bad_phy,
                 '--output', preserved[0], '--image', preserved[1], '--map', preserved[2]], reject=True, match=message)
            assert all(f.read_bytes() == b'preserve existing link output' for f in preserved)
            rejections.append(dict(chip=chip, case=label + '-overflow', preserved_outputs=3))

        protected = d / 'protected.bin'
        outputs = [Path(str(protected) + suffix) for suffix in ['', '.elf', '.map']]
        for file in outputs:
            file.write_bytes(b'preserve existing output')
        base = [builder, '--chip', f'esp32c{chip}', '--kind', 'wifi', '--compiler', compiler,
                '--vendor', ref / f'vendor/esp32c{chip}', '--rom', ref / f'components/esp_rom/esp32c{chip}/ld',
                '--libc', ref / 'riscv-libc.a', '--libgcc', ref / 'riscv-libgcc.a', '--libm', ref / 'riscv-libm.a', '--ld', 'ld.lld',
                '--source', ROOT / f'examples/esp32c{chip}-vendor-probe.flex', '--output', protected]
        wrapped = d / 'custom-symbol-reader'
        wrapped.write_text('#!/bin/sh\nexec llvm-nm "$@"\n')
        wrapped.chmod(0o755)
        run([*base, '--nm', wrapped], reject=True, match='nonstandard nm requires --objcopy PATH')
        assert all(f.read_bytes() == b'preserve existing output' for f in outputs)
        rejections.append(dict(chip=chip, case='nonstandard-nm-needs-objcopy', preserved_outputs=3))
        run([*base, '--nm', 'llvm-nm', '--objcopy', d / 'missing-objcopy'], reject=True)
        assert all(f.read_bytes() == b'preserve existing output' for f in outputs)
        rejections.append(dict(chip=chip, case='missing-objcopy', preserved_outputs=3))
        # Tool paths must not alias any of the three output files, including hardlinks.
        for suffix in ['', '.elf', '.map']:
            tool = d / ('tool' + (suffix or '.bin'))
            shutil.copy2(shutil.which('llvm-objcopy'), tool)
            alias = d / ('alias' + (suffix or '.bin'))
            destination = Path(str(alias) + suffix)
            os.link(tool, destination)
            before_tool = sha(tool)
            cmd = base.copy()
            cmd[cmd.index('--output') + 1] = alias
            run([*cmd, '--nm', 'llvm-nm', '--objcopy', tool], reject=True, match='radio output aliases input')
            assert sha(tool) == sha(destination) == before_tool
            rejections.append(dict(chip=chip, case='objcopy-output-hardlink' + suffix, preserved_tool=True))
        print('PASS: WPA allocated bytes, section policy and objcopy guards c' + str(chip), flush=True)
    report = dict(pass_all=True, WPA=records, linker_policy=policy, rejections=rejections,
                  CPU_execution=False, physical_hardware=False)
    (w / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
