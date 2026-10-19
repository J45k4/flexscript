"""Independent word-IR interpreter and deterministic ARM64 JIT fixtures."""
import argparse
import json
from pathlib import Path
import random
import struct

MASK = (1 << 64) - 1
MIN = -(1 << 63)
OPS = {"+": 43, "-": 45, "*": 42, "/": 47, "%": 37, "&": 38, "|": 124,
       "^": 94, "<<": 265, ">>": 266, "==": 259, "!=": 260, "<": 60, ">": 62, "<=": 261, ">=": 262}


def word(value):
    return ((value + (1 << 63)) & MASK) - (1 << 63)


def heap_hash(heap):
    value = 0
    for byte in heap:
        value = (value * 31 + byte) & 0xffffffff
    return value


def interpret(ir, locals_, heap, fuel, deadline, include_backedges=False):
    locals_ = list(locals_)
    heap = bytearray(heap)
    stack, acc, pc, backedges = [], 0, 1, 0
    def finish(value, error):
        result = (value, error, fuel, heap_hash(heap))
        return (*result, backedges) if include_backedges else result
    while True:
        if fuel <= 0:
            return finish(0, 1)
        fuel -= 1
        op, arg = ir[pc]
        if op == 1: acc = word(arg)
        elif op == 2: stack.append(acc)
        elif op == 3: acc = locals_[arg]
        elif op == 4: locals_[arg] = acc
        elif op in (5, 6, 21, 22):
            if op in (5, 6):
                address, end = arg, arg + 8
            else:
                base, span = arg & 0xffffffff, arg >> 32
                index = acc if op == 21 else stack.pop()
                if index < 0 or index >= span:
                    return finish(0, 3)
                address, end = base + index * 8, base + span * 8
            if end > len(heap):
                return finish(0, 3)
            if op in (5, 21): acc = struct.unpack_from("<q", heap, address)[0]
            else: struct.pack_into("<q", heap, address, acc)
        elif op == 7:
            a, b = stack.pop(), acc
            if arg in (47, 37):
                if b == 0 or (a == MIN and b == -1):
                    return finish(0, 2)
                quotient = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
                acc = quotient if arg == 47 else a - quotient * b
            elif arg == 43: acc = a + b
            elif arg == 45: acc = a - b
            elif arg == 42: acc = a * b
            elif arg == 38: acc = a & b
            elif arg == 124: acc = a | b
            elif arg == 94: acc = a ^ b
            elif arg == 265: acc = a << (b & 63)
            elif arg == 266: acc = a >> (b & 63)
            elif arg == 259: acc = int(a == b)
            elif arg == 260: acc = int(a != b)
            elif arg == 60: acc = int(a < b)
            elif arg == 62: acc = int(a > b)
            elif arg == 261: acc = int(a <= b)
            elif arg == 262: acc = int(a >= b)
            acc = word(acc)
        elif op == 9: return finish(acc, 0)
        elif op in (10, 11, 12):
            if arg <= pc * 16:
                backedges += 1
                if deadline < 0 and backedges % 1024 == 0:
                    return finish(0, 8)
            if op == 10 or (op == 11 and not acc) or (op == 12 and acc):
                pc = arg // 16
                continue
        elif op == 13: acc = int(acc != 0)
        elif op == 14: acc = word(-acc)
        elif op == 15: acc = int(acc == 0)
        elif op == 16: acc = word(~acc)
        else: raise AssertionError(op)
        pc += 1


def fixtures():
    cases = []

    def add(name, ir, locals_=(), heap=b"", fuel=100000, deadline=0, compile_status=1):
        if compile_status == 1:
            result = interpret(ir, locals_, heap, fuel, deadline, include_backedges=True)
            expected, backedges = result[:4], result[4]
        else:
            expected, backedges = (0, 0, fuel, heap_hash(heap)), 0
        cases.append({"name": name, "ir": ir, "locals": tuple(locals_), "heap": heap,
                      "fuel": fuel, "deadline": deadline, "compile": compile_status, "expected": expected, "backedges": backedges})

    add("generated return 42", [(18, 0), (1, 42), (9, 0)])
    add("cached return 42", [(18, 0), (1, 42), (9, 0)])
    add("changed bytecode invalidates cache", [(18, 0), (1, 43), (9, 0)])
    values = [MIN, MIN + 1, -65, -1, 0, 1, 63, 64, (1 << 63) - 1]
    rng = random.Random(0xA64C)
    pairs = [(a, b) for a in values for b in values]
    pairs += [(word(rng.getrandbits(64)), word(rng.getrandbits(64))) for _ in range(32)]
    for operator, opcode in OPS.items():
        for i, (a, b) in enumerate(pairs):
            add(f"{operator} full-width pair {i}", [(18, 2), (3, 0), (2, 0), (3, 1), (7, opcode), (9, 0)], (a, b))
    for opcode in (13, 14, 15, 16):
        for value in values:
            add(f"unary {opcode} {value}", [(18, 1), (3, 0), (opcode, 0), (9, 0)], (value,))
    # Immediate lowering and direct destination registers, including spilled
    # left operands and aliases between a source and the following local store.
    literals = (0, 1, 3, 33, 255, 4095, 4096, 65535, (1 << 62) + 1, (1 << 63) - 1, -1, MIN)
    for operator, opcode in OPS.items():
        for literal in literals:
            for left in (MIN, -1, 0, 17, (1 << 63) - 1):
                add(f"immediate {operator} {left} {literal}",
                    [(18, 8), (3, 7), (2, 0), (1, literal), (7, opcode), (4, 0), (3, 0), (9, 0)],
                    [0] * 7 + [left])
        for target in (0, 1):
            for left, right in ((MIN, -1), (17, 33), (-1, 0)):
                add(f"aliased destination {operator} {target} {left} {right}",
                    [(18, 2), (3, 0), (2, 0), (3, 1), (7, opcode), (4, target), (3, target), (9, 0)],
                    (left, right))
    for opcode in (13, 14, 15, 16):
        for value in values:
            add(f"unary direct register {opcode} {value}",
                [(18, 1), (3, 0), (opcode, 0), (4, 0), (3, 0), (9, 0)], (value,))
    # Sum 0..n using locals and a backward jump. Header/local setup precedes loop.
    loop = [(18, 3), (1, 0), (4, 1), (1, 0), (4, 2),
            (3, 1), (2, 0), (3, 0), (7, 60), (11, 23 * 16),
            (3, 2), (2, 0), (3, 1), (7, 43), (4, 2),
            (3, 1), (2, 0), (1, 1), (7, 43), (4, 1), (10, 5 * 16),
            (1, 0), (1, 0), (3, 2), (9, 0)]
    for n in (0, 1, 2, 64, 1025):
        add(f"sum loop {n}", loop, (n, 0, 0), deadline=100000)
    add("sum loop exhausts fuel", loop, (10000, 0, 0), fuel=200)
    add("rotated loop expires before prepaid header", loop, (10000, 0, 0), fuel=100000, deadline=-1)
    # Error refunds in a rotated loop include its prepaid following header.
    def guarded_loop(body):
        ir = [(18, 3), (3, 1), (2, 0), (3, 0), (7, 60), (11, 0)] + body
        ir += [(3, 1), (2, 0), (1, 1), (7, 43), (4, 1), (10, 16)]
        ir[5] = (11, len(ir) * 16)
        ir += [(3, 1), (9, 0)]
        return ir

    declared = (4 << 32) | 16
    array_loop = guarded_loop([(3, 1), (2, 0), (21, declared), (2, 0), (1, 1), (7, 43), (22, declared)])
    division_loop = guarded_loop([(1, 77), (6, 16), (1, MIN), (2, 0), (1, -1), (7, 47)])
    for fuel in [*range(100), 10000]:
        add(f"rotated array loop fuel {fuel}", array_loop, (6, 0, 0), heap=bytes(48), fuel=fuel)
        add(f"rotated division refund fuel {fuel}", division_loop, (6, 0, 0), heap=bytes(48), fuel=fuel)
    # A successful load permits a check to be reused only for the same saved
    # index and declaration. Popping/replacing that slot must invalidate it.
    invalidated = [(18, 0), (1, 0), (2, 0), (21, declared), (7, 43),
                   (1, -1), (2, 0), (1, 42), (22, declared), (9, 0)]
    add("array check reuse invalidated by replacing index slot", invalidated, heap=bytes(48))
    for other in ((2 << 32) | 16, (4 << 32) | 48):
        add(f"array check reuse rejects changed declaration {other}",
            [(18, 0), (1, 3), (2, 0), (21, declared), (22, other), (9, 0)], heap=bytes(48))
    for heap_size in (0, 16, 24, 48, 80):
        add(f"different global extents {heap_size}",
            [(18, 0), (1, 77), (6, 16), (5, 24), (6, 40), (5, 16), (9, 0)], heap=bytes(heap_size))
    wrapping = guarded_loop([(3, 1), (2, 0), (1, 3), (7, 38), (2, 0), (21, declared),
                             (2, 0), (1, 1), (7, 43), (22, declared)])
    for deadline in (0, 100000, -1):
        add(f"rotated checked arrays across clock calls {deadline}", wrapping, (2050, 0, 0),
            heap=bytes(48), fuel=100000, deadline=deadline)
    hash_loop = guarded_loop([(3, 2), (2, 0), (3, 1), (7, 43), (2, 0), (1, 33),
                              (7, 42), (2, 0), (3, 1), (7, 94), (4, 2)])
    hash_loop[-2] = (3, 2)
    trace = len(hash_loop) - 3
    fuels = sorted({0, 1, 4, 5, 6, 1000000} |
                   {5 + trace * k + d for k in (1, 3, 4, 5, 7, 8, 9) for d in (-1, 0, 1)})
    for n in (-1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 33):
        for fuel in fuels:
            for deadline in (0, 100000):
                add(f"unroll hash trip {n} fuel {fuel} deadline {deadline}", hash_loop,
                    (n, 0, 7), fuel=fuel, deadline=deadline)
    for n in (1023, 1024, 1025, 2051):
        add(f"unroll hash counter {n}", hash_loop, (n, 0, 7), fuel=1000000)
    for start, limit in ((-3, 5), (MIN, MIN + 3), ((1 << 63) - 3, (1 << 63) - 1), (MIN, (1 << 63) - 1)):
        for fuel in (5, 100, 300):
            add(f"unroll signed induction {start} {limit} fuel {fuel}", hash_loop,
                (limit, start, 7), fuel=fuel)
    for branch in (11, 12):
        live_result = list(hash_loop)
        if branch == 12:
            live_result[4] = (7, 262)
            live_result[5] = (12, live_result[5][1])
        live_result[-2] = (9, 0)
        for n in range(10):
            add(f"unroll live exit comparison branch {branch} trip {n}", live_result, (n, 0, 7))
    array_trace = len(wrapping) - 3
    array_fuels = sorted({0, 5, 1000000} |
                         {5 + array_trace * k + d for k in (1, 3, 4, 5, 7, 8) for d in (-1, 0, 1)})
    for n in (0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 17):
        for fuel in array_fuels:
            for heap_size in (40, 48):
                add(f"unroll array trip {n} fuel {fuel} heap {heap_size}", wrapping,
                    (n, 0, 0), heap=bytes(heap_size), fuel=fuel)
    for failing_iteration in range(6):
        body = [(3, 1), (6, 16), (1, 100), (2, 0), (3, 1), (2, 0),
                (1, failing_iteration), (7, 45), (7, 47), (4, 2)]
        failure = guarded_loop(body)
        for fuel in (0, 5, 10, 20, 30, 80, 100, 200, 100000):
            add(f"unroll division failure iteration {failing_iteration} fuel {fuel}", failure,
                (10, 0, 0), heap=bytes(48), fuel=fuel)
    for failing_iteration in range(4):
        for fuel in (0, 5, 10, 20, 30, 80, 100, 200, 100000):
            add(f"unroll bounds failure iteration {failing_iteration} fuel {fuel}", array_loop,
                (10, 4 - failing_iteration, 0), heap=bytes(48), fuel=fuel)
    for mask in (0, 1, 3, 4, 15, 0x55, 255, (1 << 63) - 1):
        for value in (MIN, -1, 0, 17, (1 << 63) - 1):
            add(f"index range AND {mask} value {value}",
                [(18, 1), (3, 0), (2, 0), (1, mask), (7, 38), (21, declared), (9, 0)],
                (value,), heap=bytes(48))
    for unary in (13, 14, 15, 16):
        for value in (-1, 0, 1, 4):
            add(f"index range invalidation unary {unary} {value}",
                [(18, 0), (1, value), (unary, 0), (21, declared), (9, 0)], heap=bytes(48))
    for operator in (259, 260, 60, 62, 261, 262):
        for left, right in ((MIN, -1), (-1, 0), (0, 0), (17, 3), ((1 << 63) - 1, -1)):
            for branch in (11, 12):
                add(f"comparison result live after branch {operator} {branch} {left} {right}",
                    [(18, 2), (3, 0), (2, 0), (3, 1), (7, operator), (branch, 8 * 16),
                     (1, 77), (10, 9 * 16), (9, 0), (9, 0)], (left, right))
    add("infinite loop exhausts fuel", [(18, 0), (10, 16), (9, 0)], fuel=73)
    add("expired deadline on loop backedge", [(18, 0), (10, 16), (9, 0)], fuel=100000, deadline=-1)
    add("zero fuel", [(18, 0), (1, 42), (9, 0)], fuel=0)
    add("negative fuel", [(18, 0), (1, 42), (9, 0)], fuel=-1)
    add("minimum signed fuel", [(18, 0), (1, 42), (9, 0)], fuel=MIN)
    add("maximum signed fuel", [(18, 0), (1, 42), (9, 0)], fuel=(1 << 63) - 1)
    # Exhaustion at every instruction around loop entries and both branch arms
    # must retain exact fuel and any guest writes already performed.
    for fuel in range(80):
        add(f"loop fuel boundary {fuel}", loop, (3, 0, 0), fuel=fuel)
    prefix = [(18, 0), (1, 77), (6, 16), (1, 9), (2, 0), (1, 0),
              (7, 47), (1, 99), (6, 24), (9, 0)]
    for fuel in range(12):
        add(f"division error after write fuel {fuel}", prefix, heap=bytes(32), fuel=fuel)
    for opcode, operand in ((5, 32), (6, 32), (21, (2 << 32) | 16), (22, (2 << 32) | 16)):
        body = [(18, 0), (1, 77), (6, 16), (1, -1)]
        if opcode == 22: body += [(2, 0), (1, 99)]
        body += [(opcode, operand), (1, 99), (6, 24), (9, 0)]
        for fuel in range(12):
            add(f"bounds error {opcode} after write fuel {fuel}", body, heap=bytes(32), fuel=fuel)
    for slots in (6, 7, 8, 28, 29, 4096):
        # Exercise register slots, short FP-relative spills, and large spills.
        body = [(18, slots), (3, slots - 1), (2, 0), (1, 7), (7, 43), (4, slots - 1),
                (3, slots - 1), (9, 0)]
        for fuel in (0, 1, 4, 7, 8, 100):
            add(f"register/spill boundary {slots} fuel {fuel}", body, [0] * (slots - 1) + [35], fuel=fuel)
    deep = [(18, 0)]
    for i in range(32): deep += [(1, i), (2, 0)]
    deep += [(1, 0)] + [(7, 43)] * 32 + [(9, 0)]
    for fuel in (0, 15, 50, 80, 97, 98, 1000):
        add(f"deep expression spill fuel {fuel}", deep, fuel=fuel)
    for op in (11, 12):
        for value in (0, -1, 1):
            add(f"conditional {op} {value}", [(18, 0), (1, value), (op, 5 * 16), (1, 17), (10, 6 * 16), (1, 42), (9, 0)])
    add("large local frame", [(18, 4096), (3, 4095), (2, 0), (3, 0), (7, 43), (9, 0)], [1] + [0] * 4094 + [41])
    heap = bytes(16) + struct.pack("<4q", 3, 5, 7, 11) + bytes(16)
    add("guest global load", [(18, 0), (5, 16), (9, 0)], heap=heap)
    add("guest global store", [(18, 0), (1, 42), (6, 16), (5, 16), (9, 0)], heap=heap)
    add("guest global past heap", [(18, 0), (5, 64), (9, 0)], heap=heap)
    span = (4 << 32) | 16
    for index in (0, 3, -1, 4, 1 << 32):
        add(f"guest array load {index}", [(18, 0), (1, index), (21, span), (9, 0)], heap=heap)
        add(f"guest array store {index}", [(18, 0), (1, index), (2, 0), (1, 42), (22, span), (9, 0)], heap=heap)
    add("array declaration exceeds heap", [(18, 0), (1, 0), (21, span), (9, 0)], heap=bytes(32))
    add("raw host syscall falls back", [(18, 0), (17, 6), (9, 0)], compile_status=-1)
    add("function calls fall back", [(18, 0), (8, 0), (9, 0)], compile_status=-1)
    malformed = [
        ("short IR", [(18, 0), (1, 42)]),
        ("wrong header", [(1, 0), (1, 42), (9, 0)]),
        ("invalid slot", [(18, 0), (3, 0), (9, 0)]),
        ("expression underflow", [(18, 0), (7, 43), (9, 0)]),
        ("invalid operator", [(18, 0), (1, 0), (2, 0), (7, 12345), (9, 0)]),
        ("jump into header", [(18, 0), (10, 0), (9, 0)]),
        ("unaligned jump", [(18, 0), (10, 17), (9, 0)]),
        ("fallthrough", [(18, 0), (1, 42), (13, 0)]),
        ("branch stack mismatch", [(18, 0), (10, 64), (2, 0), (1, 0), (7, 43), (9, 0)]),
        ("invalid packed array", [(18, 0), (1, 0), (21, 16), (9, 0)]),
    ]
    for name, ir in malformed: add(name, ir, compile_status=-2)
    # Output size is an optimization detail. Capacity exhaustion is checked
    # directly by jit-buffer-runner.c, rather than assuming this IR must overflow.
    add("largest accepted IR fits optimized code buffer", [(18, 0)] + [(5, 16)] * 8190 + [(9, 0)], heap=heap)
    return cases


def write_cases(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    cases = fixtures()
    data = bytearray(struct.pack("<q", len(cases)))
    for case in cases:
        code = b"".join(struct.pack("<qq", op, word(arg)) for op, arg in case["ir"])
        value, error, fuel, checksum = case["expected"]
        data.extend(struct.pack("<10q", len(code), len(case["locals"]), len(case["heap"]), case["fuel"],
                                case["deadline"], case["compile"], value, error, fuel, checksum))
        data.extend(b"".join(struct.pack("<q", word(value)) for value in case["locals"]))
        data.extend(case["heap"])
        data.extend(code)
    (out / "jit-cases.bin").write_bytes(data)
    (out / "jit-cases.json").write_text(json.dumps({"total": len(cases), "cases": [case["name"] for case in cases], "backedges": [case["backedges"] for case in cases]}, indent=2) + "\n")
    return cases, bytes(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    cases, data = write_cases(args.out)
    print(f"Generated {len(cases)} independent VM/JIT cases ({len(data)} bytes)")
