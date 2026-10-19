#!/usr/bin/env python3
"""Pinned station ABI/lifecycle peers, linked vendor inputs and actual C3 PHY wait.

Synthetic C lifecycle peers verify the facade without RF. The separate real
vendor observation deliberately makes no initialization-success claim.
"""
import argparse
import hashlib
import json
import re
import runpy
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'qemu', 'reference', 'work']:
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--clang', default='clang')
    p.add_argument('--ld', default='ld.lld')
    p.add_argument('--execute-c6', action='store_true')
    p.add_argument('--qemu-c6', type=Path)
    a = p.parse_args()
    w = a.work.resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists(), 'choose a fresh work directory'
    ref, compiler = a.reference.resolve(), a.compiler.resolve()
    primary = ref / 'wifi-primary'
    for row in json.loads((primary / 'provenance.json').read_text()):
        assert sha(primary / row['path']) == row['sha256'], row['path']
    cases, controls, vendor, coefficients = [], [], [], []

    def run(cmd, reject=False):
        r = subprocess.run(list(map(str, cmd)), cwd=ROOT, capture_output=True,
                           text=True, timeout=60)
        assert (r.returncode != 0 if reject else r.returncode == 0), (
            cmd, r.stdout[-2000:], r.stderr[-3000:])
        return r

    linker, builder = w / 'linker', w / 'builder'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    run([compiler, ROOT / 'scripts/build-esp32-radio.flex', '-o', builder])

    def peer(tag, source, chip, obj, expected=0):
        d = w / tag
        d.mkdir()
        fw, linked, image, report = [d / n for n in ['native.elf', 'linked.elf', 'firmware.bin', 'report.json']]
        run([compiler, '--target', f'esp32c{chip}-radio-elf', source, '-o', fw])
        archives = [ref / 'riscv-libc.a', ref / 'riscv-libgcc.a', ref / 'riscv-libm.a']
        defined = set()
        for file in [fw, obj, *archives]:
            for line in run(['llvm-nm', '--defined-only', '--extern-only', '-P', file]).stdout.splitlines():
                parts = line.split()
                if len(parts) > 1 and len(parts[1]) == 1:
                    defined.add(parts[0])
        aliases = {}
        for file in sorted((ref / f'components/esp_rom/esp32c{chip}/ld').glob('*.ld')):
            for name, value in re.findall(r'\b([A-Za-z_]\w*)\s*=\s*(0x[0-9a-fA-F]+)', file.read_text()):
                if name not in defined:
                    aliases[name] = value
        rom = d / 'ROM.ld'
        rom.write_text(''.join(f'PROVIDE({n}={v});\n' for n, v in sorted(aliases.items())))
        cmd = [linker, '--ld', a.ld, '--xip', '--newlib-stdio', '--newlib-rom', '--firmware', fw,
               '--object', obj, '--rom', rom, '--output', linked, '--image', image]
        for archive in archives:
            cmd += ['--archive', archive]
        run(cmd)
        cmd = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', (a.qemu_c6 or a.qemu) if chip == 6 and a.execute_c6 else a.qemu,
               '--xip', '--radio', '--image', image, '--elf', linked, '--report', report,
               '--expected', expected]
        if chip == 6 and not a.execute_c6:
            cmd += ['--validate-only']
        elif chip == 6:
            cmd += ['--uart', 'PASS: C6 typed config/canaries, math and guarded RF refusal; vendor lifecycle gated']
        elif expected:
            cmd += ['--uart', f'RISC-V WIFI FAIL {expected:016x}']
        else:
            cmd += ['--uart', 'PASS: RISC-V typed config/canaries']
        run(cmd)
        row = json.loads(report.read_text())
        row.update(case=tag, synthetic_vendor_peer=True, expected_result=expected, full_vendor_lifecycle_peer_executed=chip == 3, C6_scope="math/config/canaries/context/ownership and -95 refusal; full lifecycle gated" if chip == 6 else None)
        print('PASS:', tag, flush=True)
        return row

    s3 = runpy.run_path(str(ROOT / 'tests/esp32/s3-ftm-reference.py'))
    for chip in [3, 6]:
        inc = w / f'include-c{chip}'
        shutil.copytree(primary / 'wifi-include', inc)
        for file in (primary / 'test-support').iterdir():
            shutil.copy2(file, inc / file.name)
        shutil.copy2(ref / 'osi-primary/vendor/c/include/esp_private/wifi_os_adapter.h', inc / 'wifi_os_adapter.h')
        (inc / 'sdkconfig.h').write_text(f'#define CONFIG_IDF_TARGET_ESP32C{chip} 1\n'
            f'#define CONFIG_SOC_WIFI_SUPPORTED 1\n#define CONFIG_SOC_WIFI_HE_SUPPORT {int(chip == 6)}\n')
        source = w / f'lifecycle-c{chip}.flex'
        source.write_text((ROOT / 'tests/esp32/riscv-wifi-lifecycle.flex').read_text()
            .replace('esp32c3', f'esp32c{chip}').replace('../../lib/', str(ROOT / 'lib') + '/'))
        for march in ['rv32im_zicsr_zifencei', 'rv32imc_zicsr_zifencei']:
            for opt in ['-O0', '-O2', '-Os']:
                tag = f'c{chip}-{march}{opt}'
                obj = w / (tag + '.o')
                run([a.clang, '--target=riscv32', '-mabi=ilp32', '-march=' + march, opt,
                     '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-msmall-data-limit=0',
                     '-include', inc / 'oracle-types.h', '-I', inc, '-isystem', ref / 'riscv-newlib',
                     '-c', ROOT / 'tests/esp32/abi-oracle/riscv-wifi-fixture.c', '-o', obj])
                cases.append(peer(tag, source, chip, obj))
        if chip == 3:
            helpers = runpy.run_path(str(ROOT / 'tests/esp32/lifecycle-preempt-reference.py'))
            closure = w / 'control-source'
            helpers['copy_closure'](ROOT / 'tests/esp32/riscv-wifi-lifecycle.flex', closure)
            defects = [
                ('Xtensa-PS-on-RISC-V', 'esp32-wifi-core.flex', None, 'esp_sdk_irq_blocked(ps)', '(ps&15)', 44),
                ('lock-reset-omitted', 'esp32-riscv-wifi.flex', 'esp_wifi_platform_reset_locks',
                 'esp32_store32(esp32_external("eloop_data_lock"),0);', '', 2),
                ('only-one-IRQ-slot', 'esp32-riscv-wifi.flex', 'esp_wifi_platform_prepare',
                 'esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2))', 'esp_irq_reserve(1)', 36),
                ('crypto-tail-truncated', 'esp32-wifi-core.flex', 'esp_wifi_build_init_config', 'while i<52', 'while i<48', 30),
                ('station-auth-offset', 'esp32-wifi-core.flex', 'esp_wifi_station_config', 'config+120,auth', 'config+124,auth', 32),
                ('WPA3-PMF-omitted', 'esp32-wifi-core.flex', 'esp_wifi_station_config', 'if auth==6', 'if 0', 32),
            ]
            for name, module, fn, before, after, code in defects:
                tree = w / name / 'source'
                shutil.copytree(closure, tree)
                file = tree / 'lib/platform' / module
                if fn:
                    helpers['change'](file, fn, lambda body: helpers['once'](body, before, after))
                else:
                    text = file.read_text()
                    assert text.count(before) == 7
                    file.write_text(text.replace(before, after))
                controls.append(peer('defect-' + name, tree / 'tests/esp32/riscv-wifi-lifecycle.flex', chip, obj, code))

        image = w / f'actual-c{chip}.bin'
        run([builder, '--chip', f'esp32c{chip}', '--kind', 'wifi', '--compiler', compiler,
             '--vendor', ref / f'vendor/esp32c{chip}', '--rom', ref / f'components/esp_rom/esp32c{chip}/ld',
             '--libc', ref / 'riscv-libc.a', '--libgcc', ref / 'riscv-libgcc.a', '--libm', ref / 'riscv-libm.a', '--nm', 'llvm-nm',
             '--objcopy', 'llvm-objcopy', '--ld', a.ld, '--source', ROOT / f'examples/esp32c{chip}-wifi-init.flex',
             '--output', image])
        linked = Path(str(image) + '.elf')
        # Every symbol is checked against values supplied by the pinned C header.
        names = ['est_PHY_' + phase + '_FTM_COMP_' + band + direction + '_MHZ' + suffix
                 for band in ['20_20', '20_40', '40_40'] for phase in ['INIT', 'RESP']
                 for direction in ['U', 'D'] for suffix in ['', '_DIS']]
        provider = (primary / 'ftm-width-provider.rs').read_text()
        assert 'pub static mut $name: u16 = $val;' in provider
        exports = re.findall(r'\b(est_PHY_\w+)\s*=', provider)
        # The provider also contains wider-channel/5 GHz coefficients. C3/C6
        # require this exact 2.4 GHz subset of its uint16 exports.
        relevant = [n for n in exports if re.fullmatch(
            r'est_PHY_(?:INIT|RESP)_FTM_COMP_(?:20_20|20_40|40_40)[UD]_MHZ(?:_DIS)?', n)]
        assert sorted(relevant) == sorted(names)
        oracle = w / f'ftm-c{chip}'
        oracle.mkdir()
        (oracle / 'sdkconfig.h').write_text(f'#define CONFIG_ESP_WIFI_FTM_ENABLE 1\n#define CONFIG_IDF_TARGET_ESP32C{chip} 1\n')
        (oracle / 'values.c').write_text('#include <stdint.h>\n#include ' + json.dumps(str(primary / 'ftm_calibration_data.h')) +
            '\nconst uint16_t ftm_values[]={' + ','.join(n.replace('est_PHY_', 'EST_PHY_') for n in names) + '};\n')
        run([a.clang, '--target=riscv32', '-march=rv32imc', '-mabi=ilp32', '-I', oracle,
             '-c', oracle / 'values.c', '-o', oracle / 'values.o'])
        raw = (oracle / 'values.o').read_bytes()
        values_at, size, _, _ = s3['symbol_table'](raw)['ftm_values']
        assert size == 48
        values = struct.unpack_from('<24H', raw, values_at)
        data = linked.read_bytes()

        def verify_ftm(payload):
            table = s3['symbol_table'](payload)
            for name, value in zip(names, values):
                at, size, info, _ = table[name]
                assert size == 2 and info == 17 and struct.unpack_from('<H', payload, at)[0] == value, name

        verify_ftm(data)
        detected = []
        table = s3['symbol_table'](data)
        for name in names:
            for kind in ['value', 'width']:
                bad = bytearray(data)
                if kind == 'value':
                    bad[table[name][0]] ^= 1
                else:
                    struct.pack_into('<I', bad, table[name][3] + 8, 4)
                try:
                    verify_ftm(bad)
                except AssertionError:
                    detected.append(name + ':' + kind)
                else:
                    raise AssertionError('FTM defect escaped')
        coefficients.append(dict(chip=chip, values=dict(zip(names, values)), detected_defects=detected))
        execute_C6_refusal = chip == 6 and a.execute_c6
        report = w / (f'actual-c{chip}-boot.json' if execute_C6_refusal else f'actual-c{chip}-package.json')
        cmd = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', (a.qemu_c6 or a.qemu) if execute_C6_refusal else a.qemu,
               '--xip', '--radio', '--image', image, '--elf', linked, '--report', report]
        if execute_C6_refusal:
            cmd += ['--expected', -95, '--uart', 'C6 WIFI: initializer returned ffffffffffffffa1 cleanup 0000000000000000']
        else:
            cmd += ['--validate-only']
        run(cmd)
        _, sections = s3['sections'](data)
        row = json.loads(report.read_text())
        row.update(chip=chip, IRAM_bytes=sections['.text'][5], static_DRAM_bytes=sections['.data'][5],
                   real_vendor_archives=True, WiFi_initialization_completed=False, native_C6_hardware_refusal_verified=execute_C6_refusal, actual_vendor_initialization_entered=chip == 3)
        vendor.append(row)
        if chip == 3:
            run(['python3', ROOT / 'tests/esp32/riscv-wifi-startup-observe.py', '--qemu', a.qemu,
                 '--image', image, '--elf', linked, '--work', w / 'actual-startup-observation'])
        print('PASS: full vendor link and primary FTM data c' + str(chip), flush=True)

    report = dict(pass_all=True, C3_ROM_boots=6, C3_deliberate_defect_boots=len(controls),
                  C6_package_checks=sum(not x['ROM_boot'] for x in cases if x['case'].startswith('c6-')) + sum(not x['ROM_boot'] for x in vendor if x['chip']==6), C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in [*cases,*vendor]), cases=cases, controls=controls, vendor=vendor,
                  coefficients=coefficients, newlib_floor_IEEE_vectors=9, actual_C3_startup_observation=json.loads(
                      (w / 'actual-startup-observation/report.json').read_text()),
                  complete_vendor_radio_startup_verified=False, physical_hardware=False,
                  compiler_sha256=sha(compiler))
    (w / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: station lifecycle six C modes, six actual C3 defects, 48 pinned FTM values, full C3/C6 links; C3 PHY wait observed', flush=True)


if __name__ == '__main__':
    main()
