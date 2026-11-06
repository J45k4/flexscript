#!/usr/bin/env python3
"""Check RV32 branch encoding, relaxation and actual C6 ROM execution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import runpy
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'qemu-c6', 'work'):
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--baseline', type=Path)
    a = p.parse_args()
    compiler, qemu, work = [x.resolve() for x in (a.compiler, a.qemu_c6, a.work)]
    baseline = a.baseline.resolve() if a.baseline else None
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    (work / 'tmp').mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), PYTHONDONTWRITEBYTECODE='1')

    def run(args, label, expected=0):
        r = subprocess.run(list(map(str, ['nice', '-n', '19', *args])), cwd=ROOT, env=env, capture_output=True, timeout=180)
        (work / (label + '.log')).write_bytes(r.stdout + r.stderr)
        assert r.returncode == expected, (label, r.returncode, (r.stdout + r.stderr)[-2200:])
        return r

    # Import the production compiler with only its entry point renamed.
    text = (ROOT / 'compiler/main.flex').read_text()
    text = text.replace('fn main(argc, argv)', 'fn branch_compiler_main(argc, argv)')
    text = text.replace('fn main(argc,argv)', 'fn branch_compiler_main(argc,argv)')
    text = re.sub(r'^import "([^"]+)";', lambda m: 'import ' + json.dumps(str((ROOT / 'compiler' / m[1]).resolve())) + ';', text, flags=re.M)
    imported = work / 'production-compiler.flex'
    imported.write_text(text)

    # Exhaust every C.J immediate and compare independent LLVM output, plus
    # direct-JAL sign boundaries and deterministic full-range random offsets.
    deltas = list(range(-2048, 2048, 2))
    medium = [-1048576, -1048574, -4096, -2050, -2048, -2, 0, 2, 2046, 2048, 4094, 1048572, 1048574]
    rng = random.Random(0xC3C6B)
    medium += [rng.randrange(-524288, 524288) * 2 for _ in range(256)]
    asm = ['.option norelax', '.option rvc', '.text'] + [f'c.j {d}' for d in deltas]
    asm += ['.option norvc'] + [f'jal x0,{d}' for d in medium]
    flex = [f'rv_c_jump({d});' for d in deltas] + [f'rv_medium_jump({d});' for d in medium]
    for delta, form in [(-1048578, 2), (-1048576, 1), (-2050, 1), (-2048, 0), (2046, 0), (2048, 1), (1048574, 1), (1048576, 2)]:
        flex.append(f'if rv_jump_form({delta})!={form}{{return 7;}}')
    source = work / 'encoders.flex'
    source.write_text('import ' + json.dumps(str(imported)) + ';\nfn main(argc,argv){compiler_initialize();output_size=0;' + ''.join(flex) +
                      'let fd=syscall(2,load64(argv+8),577,384,0,0,0);if fd<0||!write_all(fd,output,output_size){return 1;}return syscall(3,fd,0,0,0,0,0)!=0;}\n')
    assembly, obj, exe, encoded = [work / n for n in ('encoders.s', 'encoders.o', 'encoders', 'encoders.bin')]
    assembly.write_text('\n'.join(asm) + '\n')
    run(['clang', '-target', 'riscv32-unknown-elf', '-march=rv32imc_zicsr', '-c', assembly, '-o', obj], 'llvm-encode')
    run([compiler, source, '-o', exe], 'encoder-build')
    run([exe, encoded], 'encoder-run')
    section = runpy.run_path(str(ROOT / 'tests/esp32/riscv-encoding-reference.py'))['text_section']
    assert encoded.read_bytes() == section(obj.read_bytes()), 'production jump bits differ from LLVM'
    rejections = []
    for function, delta, diagnostic in [
        ('rv_c_jump', -2050, 'compressed jump out of range'), ('rv_c_jump', 2048, 'compressed jump out of range'),
        ('rv_c_jump', -1, 'compressed jump out of range'), ('rv_c_jump', 1, 'compressed jump out of range'),
        ('rv_medium_jump', -1048578, 'direct jump out of range'), ('rv_medium_jump', 1048576, 'direct jump out of range'),
        ('rv_medium_jump', -1, 'direct jump out of range'), ('rv_medium_jump', 1, 'direct jump out of range'),
        ('rv_jump_form', -1, 'not halfword aligned'), ('rv_jump_form', 1, 'not halfword aligned'),
    ]:
        label = function + '-' + str(delta)
        reject_source, reject_exe = work / (label + '.flex'), work / label
        reject_source.write_text('import ' + json.dumps(str(imported)) + ';\nfn main(){compiler_initialize();source_path="jump-check";source_size=0;'
                                 f'{function}({delta});return 0;}}\n')
        run([compiler, reject_source, '-o', reject_exe], label + '-build')
        result = run([reject_exe], label + '-reject', expected=1)
        assert diagnostic.encode() in result.stderr
        rejections.append(label)

    # Read the actual compiler's IR edge table after emission. The test wrapper
    # observes production layout; it does not replace any encoder or lowering.
    metadata = work / 'edges.bin'
    source = work / 'observer.flex'
    source.write_text('import ' + json.dumps(str(imported)) + ';\nfn main(argc,argv){let r=branch_compiler_main(argc,argv);if r{return r;}'
        'let out=alloc(rv_ir_size*3+8);let count=0;let i=0;while i<function_count{if load64(rv_seen+i*8){'
        'let pc=load64(functions+i*32+16)+16;let end=rv_end(i);while pc<end{let op=load64(rv_ir+pc);if op>=10&&op<=12{'
        'let edge=load64(rv_jumps+pc/2);let q=out+8+count*48;store64(q,i);store64(q+8,pc);store64(q+16,op);'
        'store64(q+24,edge&4294967295);store64(q+32,load64(rv_map+load64(rv_ir+pc+8)/2));store64(q+40,edge>>32);count=count+1;'
        '}pc=pc+16;}}i=i+1;}store64(out,count);let fd=syscall(2,' + json.dumps(str(metadata)) +
        ',577,384,0,0,0);if fd<0||!write_all(fd,out,8+count*48){return 1;}return syscall(3,fd,0,0,0,0,0)!=0;}\n')
    observer = work / 'observer'
    run([compiler, source, '-o', observer], 'observer-build')
    fir = runpy.run_path(str(ROOT / 'tests/esp32/riscv-frame-reference.py'))['fir']
    cases, helpers, flex_sources = [], {}, {}
    for op, value in [(10, 0), (11, 0), (12, 1 << 32)]:
        cases.append((f'short-{op}', [(18, 0), (1, 0), (1, value), (op, 'ok'), (1, 9), (9, 0), ('label', 'ok'), (1, 0), (9, 0), (10, 'ok')], 0))
    # A false path tests the inverted conditional around a two-byte jump.
    for op, value in [(11, 1 << 32), (12, 0)]:
        cases.append((f'untaken-{op}', [(18, 0), (1, 0), (1, value), (op, 'bad'), (1, 0), (9, 0), ('label', 'bad'), (1, 9), (9, 0)], 0))
    cases.append(('compressed-backward', [(18, 0), (1, 0), (10, 'end'), ('label', 'ok'), (1, 0), (9, 0), ('label', 'end'), (10, 'ok')], 0))
    filler = [(1, 0)] * 600
    cases.append(('medium-forward', [(18, 0), (1, 0), (10, 'ok'), *filler, ('label', 'ok'), (1, 0), (9, 0)], 1))
    cases.append(('medium-backward', [(18, 0), (1, 0), (10, 'end'), ('label', 'ok'), (1, 0), (9, 0), *filler, ('label', 'end'), (10, 'ok')], 1))
    for op, value in [(11, 1 << 32), (12, 0)]:
        cases.append((f'medium-untaken-{op}', [(18, 0), (1, 0), (1, value), (op, 'bad'), (1, 0), (9, 0), *filler, ('label', 'bad'), (1, 9), (9, 0)], 1))
    # Initially A reaches 2046 bytes. Widening B first pushes A to 2048,
    # requiring another layout pass and exact fixup rollback.
    cascade = [(18, 0), (1, 0), (12, 'ok')] + [(1, 0)] * 100 + [(12, 'far')]
    cascade += [(1, 0)] * 407 + [(1, 32), ('label', 'ok'), (1, 0), (9, 0)]
    cascade += [(1, 0)] * 600 + [('label', 'far'), (10, 'ok')]
    cases.append(('cascading-growth', cascade, 1))
    call_body = [(18, 0), (1, 0), (10, 'call'), *filler, ('label', 'call'), (1, 41), (2, 0), (8, 1), (2, 0), (1, 42), (7, 259), (15, 0), (9, 0)]
    cases.append(('call-relocations-after-growth', call_body, 1))
    helpers['call-relocations-after-growth'] = [('increment', 1, 1, [(18, 1), (1, 0), (3, 0), (2, 0), (1, 1), (7, 43), (9, 0)])]
    cases.append(('callback-relocations-after-growth', None, 1))
    flex_sources['callback-relocations-after-growth'] = 'fn increment(n){return n+1;}fn main(){if esp32_state()==0{' + '1;' * 600 + '}let cb=esp32_callback(increment);return esp32_call(cb,41)-42;}\n'
    # A whole function larger than JAL's range must retain AUIPC/JALR.
    long_fill = [(1, 0x1234567887654321)] * 66000
    cases.append(('full-range-forward', [(18, 0), (1, 0), (10, 'ok'), *long_fill, ('label', 'ok'), (1, 0), (9, 0)], 2))
    cases.append(('full-range-backward', [(18, 0), (1, 0), (10, 'end'), ('label', 'ok'), (1, 0), (9, 0), *long_fill, ('label', 'end'), (10, 'ok')], 2))
    for op, value in [(11, 1 << 32), (12, 0)]:
        cases.append((f'full-range-untaken-{op}', [(18, 0), (1, 0), (1, value), (op, 'bad'), (1, 0), (9, 0), *long_fill, ('label', 'bad'), (1, 9), (9, 0)], 2))

    def signed(n, bits):
        return n - (1 << bits) if n >> (bits - 1) else n

    def validate_edges(elf, edge_bytes, minimum):
        shoff = struct.unpack_from('<I', elf, 32)[0]
        section_count = struct.unpack_from('<H', elf, 48)[0]
        sections = [struct.unpack_from('<10I', elf, shoff + i * 40) for i in range(section_count)]
        ram = sections[1]
        flash = sections[8] if section_count == 9 else None
        def address(offset):
            return 0x42000000 + offset - 0x50000 if flash and offset >= 0x50000 else ram[3] + offset
        def read(offset, size):
            part, at = (flash, offset - 0x50000) if flash and offset >= 0x50000 else (ram, offset)
            assert part is not None and 0 <= at <= part[5] - size
            return elf[part[4] + at:part[4] + at + size]
        count = struct.unpack_from('<Q', edge_bytes)[0]
        assert len(edge_bytes) == 8 + count * 48 and count
        forms = []
        for i in range(count):
            _, _, op, at, to, form = struct.unpack_from('<6Q', edge_bytes, 8 + i * 48)
            delta = address(to) - address(at)
            expected = 0 if -2048 <= delta <= 2046 else 1 if -1048576 <= delta <= 1048574 else 2
            assert delta % 2 == 0 and form == expected, (at, to, delta, form, expected)
            width = (2, 4, 8)[form]
            word = int.from_bytes(read(at, width), 'little')
            if form == 0:
                assert word & 0xe003 == 0xa001
                d = ((word >> 12 & 1) << 11) | ((word >> 11 & 1) << 4) | ((word >> 9 & 3) << 8) | ((word >> 8 & 1) << 10)
                d |= ((word >> 7 & 1) << 6) | ((word >> 6 & 1) << 7) | ((word >> 3 & 7) << 1) | ((word >> 2 & 1) << 5)
                actual = address(at) + signed(d, 12)
            elif form == 1:
                assert word & 0xfff == 0x6f
                d = ((word >> 31) << 20) | ((word >> 21 & 1023) << 1) | ((word >> 20 & 1) << 11) | (word & 0xff000)
                actual = address(at) + signed(d, 21)
            else:
                low, high = word & 0xffffffff, word >> 32
                assert low & 0xfff == 0xf97 and high & 0xfffff == 0xf8067
                actual = (address(at) + signed(low & 0xfffff000, 32) + signed(high >> 20, 12)) & 0xfffffffe
            assert actual == address(to), (at, to, form, hex(actual))
            if op != 10:
                branch = int.from_bytes(read(at - 4, 4), 'little')
                d = ((branch >> 31) << 12) | ((branch >> 25 & 63) << 5) | ((branch >> 8 & 15) << 1) | ((branch >> 7 & 1) << 11)
                assert branch & 0x7f == 0x63 and signed(d, 13) == width + 4
            forms.append(form)
        assert forms[0] >= minimum, forms
        return forms

    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker], 'linker-build')
    alias = work / 'empty.ld'
    alias.write_text('/* no external symbols */\n')
    results = []
    for name, body, minimum in cases:
        source = work / (name + ('.fir' if body is not None else '.flex'))
        if body is not None:
            fir(source, [('main', 0, 0, body), *helpers.get(name, [])])
        else:
            source.write_text(flex_sources[name])
        # FIR6 permits the large, otherwise ordinary word-IR function.
        if minimum == 2:
            raw = bytearray(source.read_bytes())
            struct.pack_into('<Q', raw, 0, 0x36524946)
            source.write_bytes(raw)
        for chip in (3, 6):
            suffixes = ('-xip-elf',) if minimum == 2 else ('-elf', '-xip-elf', '-radio-elf')
            for suffix in suffixes:
                target = f'esp32c{chip}' + suffix
                for label, tool in [('current', observer), *([('baseline', baseline)] if baseline else [])]:
                    stem = work / (name + '-' + target + '-' + label)
                    elf, linked, image, report = [Path(str(stem) + n) for n in ('.elf', '-linked.elf', '.bin', '.json')]
                    # Preserve the deliberate edges and padding: this suite tests
                    # backend relaxation, including unreachable and untaken edges.
                    args = [tool, '--ir-opt', 'none', '--language', 'ir' if body is not None else 'flex', '--target', target]
                    cached = suffix != '-elf'
                    if body is None:
                        source = work / (name + '-' + target + '.flex')
                        prefix = 'import ' + json.dumps(str(ROOT / f'lib/platform/esp32c{chip}-xip.flex')) + ';\n' if cached else ''
                        source.write_text(prefix + flex_sources[name])
                    elif cached:
                        args += ['--platform', ROOT / f'lib/platform/esp32c{chip}-xip.flex']
                    run([*args, source, '-o', elf], stem.name + '-build')
                    forms = validate_edges(elf.read_bytes(), metadata.read_bytes(), minimum) if label == 'current' else []
                    if label == 'current' and name == 'cascading-growth':
                        _, _, _, at, to, form = struct.unpack_from('<6Q', metadata.read_bytes(), 8)
                        assert form == 1 and to - at == 2050, (form, to - at)
                    args = [linker, '--ld', 'ld.lld', '--rom', alias, '--firmware', elf, '--output', linked, '--image', image]
                    if cached:
                        args += ['--xip']
                    run(args, stem.name + '-link')
                    args = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', qemu, '--image', image, '--elf', linked, '--report', report]
                    if cached:
                        args += ['--xip']
                    if suffix == '-radio-elf':
                        args += ['--radio']
                    if chip == 3:
                        args += ['--validate-only']
                    run(args, stem.name + '-ROM')
                    result = json.loads(report.read_text())
                    if chip == 6:
                        assert result['result'] == 0 and not result['trapped']
                    results.append(dict(case=name, target=target, compiler=label, executed=chip == 6, forms=forms,
                                        IRAM_bytes=result['segments'][0]['size'], image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
                print('PASS', name, target, flush=True)
    result = dict(pass_all=True, LLVM_jump_encodings=len(deltas) + len(medium), range_rejections=rejections, cases=results,
                  C6_ROM_boots=sum(x['executed'] for x in results), C3_packages=sum(not x['executed'] for x in results),
                  physical_hardware=False, emulator_implementation_changes=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest() if baseline else None)
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS:', result['LLVM_jump_encodings'], 'LLVM encodings;', result['C6_ROM_boots'], 'C6 ROM boots;', result['C3_packages'], 'C3 packages')


if __name__ == '__main__':
    main()
