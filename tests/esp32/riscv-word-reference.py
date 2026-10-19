#!/usr/bin/env python3
"""Independent Python-integer word corpus for actual emitted RISC-V code."""
import argparse
from pathlib import Path
import random

MASK = (1 << 64) - 1


def signed(value):
    value &= MASK
    return value - (1 << 64) if value >> 63 else value


def evaluate(a, b, op):
    if op == 0: return a + b
    if op == 1: return a - b
    if op == 2: return a * b
    if op in (3, 4):
        q = abs(a) // abs(b)
        if (a < 0) != (b < 0): q = -q
        return q if op == 3 else a - q * b
    if op == 5: return a & b
    if op == 6: return a | b
    if op == 7: return a ^ b
    if op == 8: return a << (b & 63)
    if op == 9: return a >> (b & 63)
    return (a < b, a > b, a <= b, a >= b, a == b, a != b)[op - 10]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rng = random.Random(0xC3C6)
    rows = []
    for i in range(512):
        a, b, op = signed(rng.getrandbits(64)), signed(rng.getrandbits(64)), i % 16
        if op in (3, 4) and (b == 0 or (a == -(1 << 63) and b == -1)):
            b = 3
        rows.append(''.join(f'{v & MASK:016x}' for v in (a, b, op, evaluate(a, b, op))))
    constants = [0, -1, 0x7ff, 0x800, 0xfffff7ff, 0xfffff800, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000, 0x7fffffffffffffff, 0x8000000000000000, 0x8000000000000001, 0x1234567887654321]
    guards = ''.join(f'if 0x{n & MASK:016x}!=vector_word("{n & MASK:016x}"){{return {513+i};}}' for i,n in enumerate(constants))
    reference = (Path(__file__).parent / 'word-vectors.flex').resolve()
    args.output.write_text(
        f'import "{reference}";\nfn main(){{' + guards + 'let table="' + ''.join(rows) +
        '";let i=0;while i<512{let p=table+i*64;let a=vector_word(p);let b=vector_word(p+16);'
        'let op=vector_word(p+32);let expected=vector_word(p+48);'
        'if vector_op(a,b,op)!=expected{return i+1;}i=i+1;}return 0;}\n')
    print('Generated 512 independent full-width Python reference cases')


if __name__ == '__main__':
    main()
