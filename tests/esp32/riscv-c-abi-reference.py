#!/usr/bin/env python3
"""Independent LLVM ILP32 ABI producer/consumer through stock C3 ROM execution.

This is asset/reference tooling; firmware lowering and linking stay Flexscript.
C6 defaults to package checks; --execute-c6 requires a stock C6 machine.
No physical-hardware proof is claimed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def elf_sections(path):
    raw = Path(path).read_bytes()
    assert raw[:7] == b'\x7fELF\x01\x01\x01'
    assert struct.unpack_from('<HH', raw, 16) == (2, 243)
    start = struct.unpack_from('<I', raw, 32)[0]
    size, count, names_index = struct.unpack_from('<HHH', raw, 46)
    assert size == 40 and count > names_index and start + count * 40 <= len(raw)
    headers = [struct.unpack_from('<10I', raw, start + i * 40) for i in range(count)]
    h = headers[names_index]
    names = raw[h[4]:h[4] + h[5]]
    result = {}
    for h in headers:
        name = names[h[0]:].split(b'\0', 1)[0].decode()
        assert name not in result
        result[name] = (h, raw[h[4]:h[4] + h[5]])
    return raw, result


def symbols(sections):
    names = sections['.strtab'][1]
    data = sections['.symtab'][1]
    result = {}
    assert len(data) % 16 == 0
    for at in range(16, len(data), 16):
        name, value, size, info, other, index = struct.unpack_from('<IIIBBH', data, at)
        result[names[name:].split(b'\0', 1)[0].decode()] = (value, size, info, index)
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--compiler', required=True, type=Path)
    p.add_argument('--qemu', required=True, type=Path)
    p.add_argument('--work', required=True, type=Path)
    p.add_argument('--clang', default='clang')
    p.add_argument('--ld', default='ld.lld')
    p.add_argument('--ar', default='llvm-ar')
    p.add_argument('--reference', type=Path)
    p.add_argument('--execute-c6', action='store_true')
    p.add_argument('--qemu-c6', type=Path)
    args = p.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    compiler = str(args.compiler.resolve())
    checks, boots, cases = [], 0, []

    def run(argv, reject=None):
        result = subprocess.run([str(x) for x in argv], cwd=root, capture_output=True, text=True, timeout=90)
        if reject is None:
            assert result.returncode == 0, (argv, result.stdout, result.stderr)
        else:
            assert result.returncode != 0 and reject in result.stdout + result.stderr, (argv, result.returncode, result.stdout, result.stderr)
        return result

    linker = work / 'linker'
    run([compiler, 'scripts/esp32-link.flex', '-o', linker])
    base = [args.clang, '--target=riscv32', '-mabi=ilp32', '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-msmall-data-limit=0', '-ffunction-sections', '-fdata-sections']
    expected_imports = {'rv_c_mix8', 'rv_c_driver', 'rv_c_narrow8', 'rv_c_acceptance', 'rv_c_enable'}
    for march in ('rv32im_zicsr', 'rv32imc_zicsr'):
        for opt in ('-O0', '-O2', '-Os'):
            stem = march + opt
            c, asm = work / (stem + '.o'), work / (stem + '-asm.o')
            run([*base, '-march=' + march, opt, '-c', 'tests/esp32/riscv-c-abi.c', '-o', c])
            run([*base, '-march=' + march, '-c', 'tests/esp32/riscv-c-abi.S', '-o', asm])
            a, b = work / (stem + '-a.a'), work / (stem + '-b.a')
            run([args.ar, 'rcsD', a, asm])
            run([args.ar, 'rcsD', b, c])
            for chip in (3, 6):
                prefix = work / (stem + f'-c{chip}')
                firmware, linked, image = [Path(str(prefix) + ext) for ext in ('.elf', '-linked.elf', '.bin')]
                run([compiler, '--target', f'esp32c{chip}-elf', 'tests/esp32/riscv-c-abi.flex', '-o', firmware])
                raw, sections = elf_sections(firmware)
                syms = symbols(sections)
                code = 0x40380000 if chip == 3 else 0x40800000
                data = 0x3fca0000 if chip == 3 else 0x40830000
                profile = struct.unpack('<8I', sections['.flex.info'][1])
                assert profile == (1, 5 if chip == 3 else 13, code, data, 0x3fcc0000 if chip == 3 else 0x40850000, 0x3fcc8000 if chip == 3 else 0x40858000, data + 65536, data + 98304)
                imports = {}
                names = sections['.strtab'][1]
                for name, slot in struct.iter_unpack('<II', sections['.flex.imports'][1]):
                    imports[names[name:].split(b'\0', 1)[0].decode()] = slot
                assert set(imports) == expected_imports and 'must_not_be_linked' not in syms
                for name in ('rv_callback', 'rv_iram_callback'):
                    assert syms[name][2:] == (18, 1) and code + 128 < syms[name][0] < code + 131072
                for name in ('rv_calls', 'rv_cookie'):
                    assert syms[name][1:] == (8, 17, 2)
                cmd = [linker, '--ld', args.ld, '--firmware', firmware, '--archive', a, '--archive', b, '--output', linked, '--image', image, '--map', Path(str(prefix) + '.map')]
                run(cmd)
                digest = sha(image), sha(linked)
                run(cmd)
                assert digest == (sha(image), sha(linked)), 'deterministic linked image'
                _, final = elf_sections(linked)
                final_syms = symbols(final)
                for name, slot in imports.items():
                    assert struct.unpack_from('<Q', final['.data'][1], slot - data)[0] == final_syms[name][0]
                report = Path(str(prefix) + '.json')
                cmd = ['python3', 'tests/esp32/riscv-rom-peer.py', '--qemu', (args.qemu_c6 or args.qemu) if chip == 6 and args.execute_c6 else args.qemu, '--image', image, '--elf', linked, '--report', report]
                if chip == 6 and not args.execute_c6:
                    cmd.append('--validate-only')
                elif chip == 3:
                    boots += 1
                run(cmd)
                cases.append(dict(march=march, optimization=opt, chip=chip, executed=chip == 3 or args.execute_c6, image_sha256=sha(image), linked_elf_sha256=sha(linked), imports=imports))
    # Trusted native adapters expose C imports to all supported Seta frontends.
    seta, fir, platform = work / 'adapter.seta', work / 'adapter.fir', work / 'adapter.flex'
    seta.write_text('plugin rv.abi v1 {} extern fn rv_value()->i32 fn main()->i32{return rv_value()}')
    want = ((0x80000000 << 32) + 4) ^ (0xffffffff * 0x100000003) ^ (0x23456789 << 17) ^ (0xdeadbeef << 29) ^ (0xabcdef01 * 19) ^ (0x87654321 << 7) ^ 0xfedcba98
    platform.write_text('global started=0;fn esp_platform_init(){started=17;return 0;}fn rv_value(){if started!=17{return 1;}return esp32_call64(esp32_external("rv_c_mix8"),4,0x80000000,0xffffffff,0x23456789,0xdeadbeef,0xabcdef01,0x87654321,0xfedcba98)^' + hex(want & ((1 << 64)-1)) + ';}')
    run([compiler, '--target', 'ir', seta, '-o', fir])
    for chip in (3, 6):
        for frontend in ('Seta', 'saved-FIR', 'external-FIR'):
            prefix = work / (f'adapter-c{chip}-' + frontend)
            firmware, linked, image, report = [Path(str(prefix) + ext) for ext in ('.elf', '-linked.elf', '.bin', '.json')]
            cmd = [compiler, '--target', f'esp32c{chip}-elf', '--platform', platform]
            if frontend == 'saved-FIR': cmd += ['--language', 'ir']
            if frontend == 'external-FIR': cmd += ['--frontend', 'examples/extensions/seta.flex']
            run([*cmd, fir if frontend == 'saved-FIR' else seta, '-o', firmware])
            run([linker, '--ld', args.ld, '--firmware', firmware, '--archive', b, '--output', linked, '--image', image])
            cmd = ['python3', 'tests/esp32/riscv-rom-peer.py', '--qemu', (args.qemu_c6 or args.qemu) if chip == 6 and args.execute_c6 else args.qemu, '--image', image, '--elf', linked, '--report', report]
            if chip == 6 and not args.execute_c6: cmd += ['--validate-only']
            elif chip == 3: boots += 1
            run(cmd)
            cases.append(dict(frontend=frontend, chip=chip, executed=chip == 3 or args.execute_c6, image_sha256=sha(image), linked_elf_sha256=sha(linked)))
    if args.reference:
        for chip in (3, 6):
            rom = args.reference.resolve() / f'components/esp_rom/esp32c{chip}/ld/esp32c{chip}.rom.ld'
            assert rom.is_file(), rom
            prefix = work / f'ROM-C-ABI-c{chip}'
            source, firmware, linked, image, report = [Path(str(prefix) + ext) for ext in ('.flex', '.elf', '-linked.elf', '.bin', '.json')]
            source.write_text('fn main(){let p="RV32 ROM C ABI\\n";let i=0;while load8(p+i){esp32_call32(esp32_external("uart_tx_one_char"),load8(p+i),0,0,0,0,0,0,0);i=i+1;}while (esp32_load32(0x6000001c)>>16)&255{}return 0;}')
            run([compiler, '--target', f'esp32c{chip}-elf', source, '-o', firmware])
            run([linker, '--ld', args.ld, '--firmware', firmware, '--rom', rom, '--output', linked, '--image', image])
            cmd = ['python3', 'tests/esp32/riscv-rom-peer.py', '--qemu', (args.qemu_c6 or args.qemu) if chip == 6 and args.execute_c6 else args.qemu, '--image', image, '--elf', linked, '--report', report, '--uart', 'RV32 ROM C ABI']
            if chip == 6 and not args.execute_c6: cmd += ['--validate-only']
            elif chip == 3: boots += 1
            run(cmd)
            cases.append(dict(ROM_C_ABI=True, chip=chip, executed=chip == 3 or args.execute_c6, image_sha256=sha(image), linked_elf_sha256=sha(linked), ROM_symbols_sha256=sha(rom)))
    firmware = work / 'negative.elf'
    source = work / 'negative.flex'
    output, image, mapfile = [work / n for n in ('protected.elf', 'protected.bin', 'protected.map')]

    def reject_link(label, message, extra=(), path=firmware):
        for out in (output, image, mapfile):
            out.write_text('preserve ' + out.name)
        before = [sha(out) for out in (output, image, mapfile)]
        cmd = [linker, '--ld', args.ld, '--firmware', path, '--object', c, '--output', output, '--image', image]
        if '--map' not in extra: cmd += ['--map', mapfile]
        run([*cmd, *extra], reject=message)
        assert before == [sha(out) for out in (output, image, mapfile)]
        checks.append(label)

    def compile_text(text, target='esp32c3-elf'):
        source.write_text(text)
        run([compiler, '--target', target, source, '-o', firmware])

    compile_text('fn main(){return esp32_external("missing_vendor");}')
    reject_link('undefined-import', 'undefined symbol')
    compile_text('fn main(){return 0;}')
    reject_link('SRAM-needs-explicit-XIP-profile', 'explicit cached-flash target', ['--xip'])
    original, sections = elf_sections(firmware)
    info = sections['.flex.info'][0][4]
    for offset in (4, 8, 12, 16, 20, 24, 28):
        mutated = bytearray(original)
        mutated[info + offset] ^= 16
        firmware.write_bytes(mutated)
        reject_link(f'profile-{offset}', 'profile')
    mutated = bytearray(original)
    struct.pack_into('<H', mutated, 18, 94)
    firmware.write_bytes(mutated)
    reject_link('wrong-architecture', 'architecture/chip mismatch')
    mutated = bytearray(original)
    struct.pack_into('<I', mutated, 32, 0xfffffff0)
    firmware.write_bytes(mutated)
    reject_link('section-overflow', 'invalid ELF section table')
    firmware.write_bytes(original)
    reject_link('output-input-alias', 'link outputs alias', ['--map', firmware])
    alias = work / 'input-hardlink.elf'
    if alias.exists(): alias.unlink()
    alias.hardlink_to(firmware)
    reject_link('hardlink-alias', 'link outputs alias', ['--map', alias])
    assert firmware.read_bytes() == original
    for kind, text, message in (
        ('code-overflow', 'const unsigned char huge[131072] __attribute__((section(".text.huge")))={1};', 'vendor code exceeds'),
        ('data-overflow', 'unsigned char huge[65536]={1};', 'vendor data overlaps'),
        ('dynamic-TLS', '__thread unsigned int tls=1; unsigned int huge(void){return tls;}', 'undefined symbol'),
    ):
        cf, obj = work / (kind + '.c'), work / (kind + '.o')
        cf.write_text(text)
        extra_flags = ['-fPIC', '-ftls-model=global-dynamic'] if kind == 'dynamic-TLS' else []
        run([*base, '-march=rv32im_zicsr', *extra_flags, '-c', cf, '-o', obj])
        compile_text('fn main(){return esp32_external("huge");}')
        reject_link(kind, message, ['--object', obj])
    for target in ('esp32c3', 'esp32c6', 'esp32c3-elf', 'esp32c6-elf'):
        for label, text, error in (
            ('callback-arity', 'fn cb(a){return a;}fn main(){return esp32_callback32(cb);}', 'wrong function argument count'),
            ('IRAM-callback-arity', 'fn cb(a){return a;}fn main(){return esp32_iram_callback32(cb);}', 'wrong function argument count'),
            ('bad-symbol', 'fn main(){return esp32_external("not-a-symbol");}', 'invalid ESP32 external symbol'),
        ):
            source.write_text(text)
            output.write_text('preserve output')
            run([compiler, '--target', target, source, '-o', output], reject=error)
            assert output.read_text() == 'preserve output'
            checks.append(target + '-' + label)
        if not target.endswith('-elf'):
            source.write_text('fn main(){return esp32_external("missing_vendor");}')
            output.write_text('preserve output')
            run([compiler, '--target', target, source, '-o', output], reject='requires an esp32c3-elf or esp32c6-elf')
            assert output.read_text() == 'preserve output'
            checks.append(target + '-raw-import-rejected')
    report = dict(pass_all=True, C3_ROM_boots=boots, C6_ROM_boots=sum(x['chip']==6 and x['executed'] for x in cases), C6_package_checks=sum(x['chip']==6 and not x['executed'] for x in cases), cases=cases, rejections=checks, compiler_sha256=sha(compiler), physical_hardware=False, SDK_task_contexts_verified_by_this_suite=False, reference='LLVM ILP32 C and assembly; eight uint32 arguments and uint64 result; unmodified stock Espressif QEMU')
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"PASS: RISC-V C ABI {boots} C3 ROM boots, {report['C6_ROM_boots']} C6 ROM boots, {report['C6_package_checks']} C6 linked packages, {len(checks)} rejection checks")


if __name__ == '__main__':
    main()
