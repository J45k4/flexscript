#!/usr/bin/env python3
"""Compare production Flexscript instruction encoders with LLVM's assembler."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import subprocess


def text_section(elf):
    assert elf[:7] == b'\x7fELF\x01\x01\x01'
    sections = struct.unpack_from('<I', elf, 32)[0]
    count, names_id = struct.unpack_from('<HH', elf, 48)
    headers = [struct.unpack_from('<10I', elf, sections + i * 40) for i in range(count)]
    names = elf[headers[names_id][4]:headers[names_id][4] + headers[names_id][5]]
    for h in headers:
        if names[h[0]:].split(b'\0', 1)[0] == b'.text':
            return elf[h[4]:h[4] + h[5]]
    raise AssertionError('LLVM object lacks .text')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--clang', default='clang')
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[2]
    # Import the actual compiler/encoders, renaming only its command entrypoint.
    compiler_source = (root / 'compiler/main.flex').read_text()
    compiler_source = compiler_source.replace('fn main(argc, argv)', 'fn encoder_compiler_main(argc, argv)')
    compiler_source = compiler_source.replace('fn main(argc,argv)', 'fn encoder_compiler_main(argc,argv)')
    # Keep original import resolution without writing in the compiler directory.
    import re
    compiler_source = re.sub(r'^import "([^"]+)";', lambda m: f'import "{(root / "compiler" / m[1]).resolve()}";', compiler_source, flags=re.M)
    imported = args.work / 'compiler-encoders.flex'
    imported.write_text(compiler_source)
    lines, flex = ['.option norvc', '.option norelax', '.text'], []
    rng = random.Random(0xC3C600)
    for f3, f7, name in [(0, 0, 'add'), (0, 32, 'sub'), (1, 0, 'sll'), (2, 0, 'slt'),
                         (3, 0, 'sltu'), (4, 0, 'xor'), (5, 0, 'srl'), (5, 32, 'sra'),
                         (6, 0, 'or'), (7, 0, 'and'), (0, 1, 'mul'), (3, 1, 'mulhu')]:
        for _ in range(16):
            d, s, t = [rng.randrange(32) for _ in range(3)]
            lines.append(f'{name} x{d},x{s},x{t}')
            flex.append(f'rv_r({f3},{f7},{d},{s},{t});')
    for n in (-2048, -1024, -1, 0, 1, 1023, 2047):
        for op, f3, name in [(0x13, 0, 'addi'), (0x13, 4, 'xori'), (0x13, 7, 'andi')]:
            d, s = rng.randrange(32), rng.randrange(32)
            lines.append(f'{name} x{d},x{s},{n}')
            flex.append(f'rv_i({op},{f3},{d},{s},{n});')
        for f3, name in ((2, 'sw'), (0, 'sb')):
            t, s = rng.randrange(32), rng.randrange(32)
            lines.append(f'{name} x{t},{n}(x{s})')
            flex.append(f'rv_store({f3},{t},{s},{n});')
        for f3, name in ((2, 'lw'), (4, 'lbu')):
            d, s = rng.randrange(32), rng.randrange(32)
            lines.append(f'{name} x{d},{n}(x{s})')
            flex.append(f'rv_i(3,{f3},{d},{s},{n});')
    for n in (0, 1, 15, 31):
        for name in ('slli', 'srli', 'srai'):
            lines.append(f'{name} x10,x12,{n}')
            flex.append(f'rv_{name}(10,12,{n});')
    for n in (-4096, -4, 0, 4, 4094):
        for f3, name in ((0, 'beq'), (1, 'bne'), (4, 'blt'), (5, 'bge'), (6, 'bltu'), (7, 'bgeu')):
            lines.append(f'{name} x10,x12,{n}')
            flex.append(f'at=rv_branch({f3},10,12);rv_patch_branch(at,at+({n}));')
    for csr in (0x300, 0x304, 0x305, 0x341, 0xC00):
        lines.append(f'csrrs x10,{csr},x0')
        flex.append(f'rv_csr(2,10,{csr},0);')
    # RV32C encodings used by the compact emitter, across all legal registers.
    lines.append('.option rvc')
    compressed = 0
    for d in range(1, 32):
        for value in range(-32, 32):
            lines.append(f'c.li x{d},{value}')
            flex.append(f'rv_imm({d},{value});')
            compressed += 1
        for source_reg in range(1, 32):
            lines.append(f'c.mv x{d},x{source_reg}')
            flex.append(f'rv_mov({d},{source_reg});')
            compressed += 1
    for d in range(1, 32):
        for value in range(-32, 32):
            if value:
                lines.append(f'c.addi x{d},{value}')
                flex.append(f'rv_addi({d},{d},{value});')
                compressed += 1
        for t in range(1, 32):
            lines.append(f'c.add x{d},x{t}')
            flex.append(f'rv_add({d},{d},{t});')
            compressed += 1
        for offset in range(0, 256, 4):
            lines.append(f'c.lwsp x{d},{offset}(sp)')
            flex.append(f'rv_lw({d},2,{offset});')
            compressed += 1
    for t in range(32):
        for offset in range(0, 256, 4):
            lines.append(f'c.swsp x{t},{offset}(sp)')
            flex.append(f'rv_sw({t},2,{offset});')
            compressed += 1
    for base in range(8, 16):
        for reg in range(8, 16):
            for offset in range(0, 128, 4):
                for mnemonic, helper in [('c.lw', 'rv_lw'), ('c.sw', 'rv_sw')]:
                    lines.append(f'{mnemonic} x{reg},{offset}(x{base})')
                    flex.append(f'{helper}({reg},{base},{offset});')
                    compressed += 1
    lines.append('c.jr ra')
    flex.append('rv_ins16(0x8082);')
    compressed += 1
    lines.append('c.nop')
    flex.append('rv_ins16(1);')
    compressed += 1
    lines.append('.option norvc')
    for offset in [-16384, -2056, -2048, -2040, -8, 0, 16, 2040, 2048, 2064, 16384]:
        for storing in [0, 1]:
            base, actual_offset = 8, offset
            if not -2048 <= offset <= 2043:
                lo = ((offset + 2048) & 4095) - 2048
                hi = ((offset - lo) >> 12) & 1048575
                lines += [f'lui x5,{hi}', f'addi x5,x5,{lo}', 'add x5,x8,x5']
                base, actual_offset = 5, 0
            mnemonic = 'sw' if storing else 'lw'
            for reg, n in [(10, actual_offset), (11, actual_offset + 4)]:
                if base == 8 and 0 <= n <= 124 and n % 4 == 0:
                    lines += ['.option rvc', f'c.{mnemonic} x{reg},{n}(x{base})', '.option norvc']
                    compressed += 1
                else:
                    lines.append(f'{mnemonic} x{reg},{n}(x{base})')
            flex.append(f'rv_frame_pair({offset},{storing});')
    for value in [-2048, -33, -32, -1, 0, 1, 31, 32, 2047, 0x12345678]:
        lo = ((value + 2048) & 4095) - 2048
        hi = ((value - lo) >> 12) & 1048575
        lines += [f'lui x10,{hi}', f'addi x10,x10,{lo}']
        flex.append(f'rv_const(10,{value});')
    for offset in [-2048, -4, 1, 126, 128, 252, 256, 2047]:
        for reg, base in [(0, 2), (7, 8), (16, 8), (10, 3)]:
            for mnemonic, helper in [('lw', 'rv_lw'), ('sw', 'rv_sw')]:
                # x0 is legal for SWSP; the other combinations must stay raw.
                if mnemonic == 'sw' and base == 2 and 0 <= offset <= 252 and offset % 4 == 0:
                    lines += ['.option rvc', f'c.swsp x{reg},{offset}(sp)', '.option norvc']
                    compressed += 1
                else:
                    lines.append(f'{mnemonic} x{reg},{offset}(x{base})')
                flex.append(f'{helper}({reg},{base},{offset});')
    source = args.work / 'encoding.flex'
    source.write_text(f'import "{imported}";fn main(){{output=alloc(131072);output_limit=131072;output_size=0;let at=0;' + ''.join(flex) + 'return !write_all(1,output,output_size);}')
    assembly, obj, binary = args.work / 'reference.S', args.work / 'reference.o', args.work / 'encoders'
    assembly.write_text('\n'.join(lines) + '\n')
    subprocess.run([args.clang, '--target=riscv32', '-march=rv32imc_zicsr', '-mabi=ilp32', '-c', str(assembly), '-o', str(obj)], check=True)
    subprocess.run([args.compiler, str(source), '-o', str(binary)], check=True)
    actual = subprocess.check_output([str(binary)])
    expected = text_section(obj.read_bytes())
    assert actual == expected, next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), (len(actual), len(expected)))
    report = dict(pass_all=True, instructions=(len(expected)-compressed*2)//4+compressed, compressed=compressed, bytes=len(expected), sha256=hashlib.sha256(expected).hexdigest(), reference='LLVM integrated assembler RV32IMC/Zicsr')
    (args.work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS: {report["instructions"]} production RISC-V encodings match LLVM exactly')


if __name__ == '__main__':
    main()
