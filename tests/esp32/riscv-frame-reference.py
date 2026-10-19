#!/usr/bin/env python3
"""Native FIR frame/parameter/CFG checks for the RV32 compact emitter."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1


def fir(path, functions):
    code, records, names = [], [], b''
    for name, arity, slots, body in functions:
        start = len(code) * 16
        offsets, at = {}, start
        for op, arg in body:
            if op == 'label':
                offsets[arg] = at
            else:
                at += 16
        records.append((len(names), len(name), start, arity, slots, 0, 0, 0))
        names += name.encode()
        for op, arg in body:
            if op != 'label':
                code.append((op, offsets[arg] if isinstance(arg, str) else arg))
    raw = b''.join(struct.pack('<QQ', op, arg & MASK) for op, arg in code)
    code_at = 64 + len(records) * 64
    size = code_at + len(raw) + len(names)
    header = (0x31524946, size, len(records), code_at, len(raw), code_at + len(raw), len(names), 0)
    path.write_bytes(struct.pack('<8Q', *header) + b''.join(struct.pack('<8Q', *r) for r in records) + raw + names)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'work', 'qemu-c6']:
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--baseline', type=Path)
    a = p.parse_args()
    work = a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(args):
        r = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, timeout=90)
        assert r.returncode == 0, (args, r.stdout[-1000:], r.stderr[-2000:])
        return r.stdout

    def main_compare(prefix, expected):
        return [(18, 0), (1, 0), *prefix, (2, 0), (1, expected), (7, 259), (15, 0), (9, 0)]

    cases = []
    values = [((i + 1) * 0x100000001) ^ 0x1234567800000000 for i in range(258)]
    body = [(18, 258), (1, 0)]
    for i, value in enumerate(values):
        body += [(1, value), (4, i)]
    body += [(1, 0)]
    for i in range(258):
        body += [(2, 0), (3, i), (7, 43)]
    body += [(2, 0), (1, sum(values) & MASK), (7, 259), (15, 0), (9, 0)]
    cases.append(('large-local-frame-and-fallback', [('main', 0, 258, body)]))
    parameters = values[:257]
    prefix = []
    for value in parameters:
        prefix += [(1, value), (2, 0)]
    prefix += [(8, 1)]
    helper = [(18, 258), (1, 0), (4, 257)]
    for i in range(257):
        helper += [(3, 257), (2, 0), (3, i), (7, 43), (4, 257)]
    helper += [(3, 257), (9, 0)]
    cases.append(('positive-parameter-offset-and-call-cleanup', [('main', 0, 0, main_compare(prefix, sum(parameters) & MASK)), ('sum_parameters', 257, 258, helper)]))
    for kind in ['unconditional', 'conditional', 'loop']:
        slots = 2 if kind == 'loop' else 1
        poison = [(18, slots), (1, 0)]
        for i in range(slots):
            poison += [(1, 0x1122334455667700 + i), (4, i)]
        poison += [(3, 0)]
        if slots == 2:
            poison += [(2, 0), (3, 1), (7, 43)]
        poison += [(9, 0)]
        reader = [(18, slots), (1, 0)]
        if kind == 'unconditional':
            reader += [(10, 'read'), (1, 99), (4, 0), ('label', 'read'), (3, 0), (9, 0)]
            expected = 0
        elif kind == 'conditional':
            reader += [(11, 'read'), (1, 99), (4, 0), ('label', 'read'), (3, 0), (9, 0)]
            expected = 0
        else:
            reader += [(4, 1), ('label', 'body'), (3, 0), (2, 0), (1, 1), (7, 43), (4, 0), (3, 1), (2, 0), (1, 1), (7, 43), (4, 1), (2, 0), (1, 3), (7, 60), (12, 'body'), (3, 0), (9, 0)]
            expected = 3
        cases.append((kind + '-first-read-zero-after-poison', [('main', 0, 0, main_compare([(8, 1), (8, 2)], expected)), ('poison', 0, slots, poison), ('read_default', 0, slots, reader)]))
    linker = work / 'linker'
    run([a.compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    alias = work / 'empty.ld'
    alias.write_text('/* no external code */\n')
    results = []
    for name, functions in cases:
        source = work / (name + '.fir')
        fir(source, functions)
        for target in [f'esp32c{chip}{suffix}' for chip in (3, 6) for suffix in ('-elf', '-xip-elf', '-radio-elf')]:
            for compiler_name, compiler in [('current', a.compiler), *([('baseline', a.baseline)] if a.baseline else [])]:
                stem = work / (name + '-' + target + '-' + compiler_name)
                elf, linked, image = Path(str(stem) + '.elf'), Path(str(stem) + '-linked.elf'), Path(str(stem) + '.bin')
                args = [compiler, '--language', 'ir', '--target', target]
                if target.endswith(('-xip-elf', '-radio-elf')):
                    chip = 3 if target.startswith('esp32c3') else 6
                    args += ['--platform', ROOT / f'lib/platform/esp32c{chip}-xip.flex']
                run([*args, source, '-o', elf])
                payload = elf.read_bytes()
                flags = struct.unpack_from('<I', payload, 36)[0]
                assert not flags & ~1, flags
                if compiler_name == 'current':
                    assert flags & 1, 'compressed code requires EF_RISCV_RVC'
                shoff = struct.unpack_from('<I', payload, 32)[0]
                assert struct.unpack_from('<I', payload, shoff + 40 + 20)[0] % 4 == 0
                args = [linker, '--ld', 'ld.lld', '--rom', alias, '--firmware', elf, '--output', linked, '--image', image]
                if target.endswith(('-xip-elf', '-radio-elf')):
                    args += ['--xip']
                run(args)
                args = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', a.qemu_c6, '--image', image, '--elf', linked, '--report', Path(str(stem) + '.json')]
                if target.endswith(('-xip-elf', '-radio-elf')):
                    args += ['--xip']
                if target.endswith('-radio-elf'):
                    args += ['--radio']
                if target.startswith('esp32c3'):
                    args += ['--validate-only']
                run(args)
                results.append(dict(case=name, target=target, compiler=compiler_name, executed=target.startswith('esp32c6'), expected_main_result=0, ELF_RVC=bool(struct.unpack_from('<I', elf.read_bytes(), 36)[0] & 1), image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, C6_ROM_boots=sum(x['executed'] for x in results), C3_packages=sum(not x['executed'] for x in results), cases=results, physical_hardware=False, compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', report['C6_ROM_boots'], 'C6 native frame boots;', report['C3_packages'], 'C3 packages; no physical claim')


if __name__ == '__main__':main()
