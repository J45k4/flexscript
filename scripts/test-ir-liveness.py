#!/usr/bin/env python3
"""Independent CFG liveness oracle and native call-preservation regressions."""
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1


def oracle(code, mapping):
    live = [0] * len(code)

    def successors(i):
        op, arg = code[i]
        if op == 9:
            return []
        edges = [] if op == 10 else [i + 1]
        if op in (10, 11, 12):
            edges += [arg // 16]
        return [n for n in edges if n < len(code)]

    changed = True
    while changed:
        changed = False
        for i in range(len(code)-1, -1, -1):
            out = 0
            for n in successors(i):
                out |= live[n]
            op, arg = code[i]
            value = out
            if op == 3:
                value |= mapping[arg]
            elif op == 4:
                value &= ~mapping[arg]
            if value != live[i]:
                changed = True
                live[i] = value
    after = []
    for i in range(len(code)):
        mask = 0
        for n in successors(i):
            mask |= live[n]
        after.append(mask)
    return after


def main():
    compiler = str(Path(os.environ.get('FLEX_COMPILER', 'build/flex')).resolve())
    baseline = os.environ.get('FLEX_BASELINE_COMPILER')
    if baseline:
        baseline = str(Path(baseline).resolve())
    checks = 0
    cases = []

    def case(code, mapping):
        cases.append((code, mapping, oracle(code, mapping)))

    case([(18, 2), (3, 0), (8, 0), (3, 1), (4, 0), (9, 0)], [1, 2])
    case([(18, 2), (8, 0), (11, 80), (3, 0), (10, 96), (3, 1), (9, 0)], [1, 2])
    case([(18, 2), (3, 0), (8, 0), (12, 16), (3, 1), (9, 0)], [1 << 63, 1])
    case([(18, 1), (8, 0), (4, 0), (3, 0), (10, 16)], [1])
    rng = random.Random(9650)
    for _ in range(256):
        slots = rng.randint(1, 12)
        bits = rng.sample(range(64), slots)
        mapping = [1 << bit if rng.randrange(3) else 0 for bit in bits]
        n = rng.randint(3, 75)
        code = [(18, slots)]
        for i in range(1, n-1):
            op = rng.choice([1, 2, 3, 3, 4, 4, 7, 8, 9, 10, 11, 12, 17, 28])
            arg = rng.randrange(slots) if op in (3, 4) else 0
            if op in (10, 11, 12):
                arg = rng.randint(1, n)*16
            code.append((op, arg))
        code.append((9, 0))
        case(code, mapping)
    data = bytearray(struct.pack('<Q', len(cases)))
    for code, mapping, after in cases:
        data += struct.pack('<QQ', len(code), len(mapping))
        data += b''.join(struct.pack('<Q', n) for n in mapping)
        data += b''.join(struct.pack('<QQ', op, arg) for op, arg in code)
        data += b''.join(struct.pack('<Q', n) for n in after)
        checks += len(code)

    with tempfile.TemporaryDirectory(prefix='flex-ir-live-') as temporary:
        work = Path(temporary)
        fixture = work / 'graphs.bin'
        fixture.write_bytes(data)
        source = work / 'test.flex'
        source.write_text(f'import "{ROOT}/scripts/lib/build.flex";import "{ROOT}/compiler/ir-liveness.flex";'
            'fn main(argc,argv){h_environment(argc,argv);let data=h_read(load64(argv+8));let count=load64(data);let p=data+8;let c=0;'
            'while c<count{let n=load64(p);let slots=load64(p+8);let map=p+16;let code=map+slots*8;let gold=code+n*16;'
            'h_assert(ir_live_analyze(code,0,n*16,slots,map),"analysis declined a valid graph");let i=0;'
            'while i<n{h_assert(ir_live_after(i*16)==load64(gold+i*8),h_cat3("liveness case ",h_int(c),h_cat(" instruction ",h_int(i))));i=i+1;}'
            'h_assert(ir_live_after(-1)==il_all,"invalid query must preserve all values");p=gold+n*8;c=c+1;}'
            'let map=h_take(8);store64(map,5);let code=h_take(32);store64(code,18);store64(code+8,1);store64(code+16,10);store64(code+24,17);'
            'h_assert(!ir_live_analyze(code,0,32,1,map) && ir_live_after(16)==5,"unaligned edge fallback");'
            'store64(code+24,64);h_assert(!ir_live_analyze(code,0,32,1,map) && ir_live_after(16)==5,"escaping edge fallback");'
            'store64(code+16,3);store64(code+24,1);h_assert(!ir_live_analyze(code,0,32,1,map) && ir_live_after(16)==5,"invalid slot fallback");'
            'store64(code+16,99);h_assert(!ir_live_analyze(code,0,32,1,map) && ir_live_after(16)==5,"unknown opcode fallback");'
            'h_assert(!ir_live_analyze(code,0,131073*16,1,map) && ir_live_after(16)==5,"bounded scratch fallback");'
            'store64(map,0);h_assert(ir_live_analyze(code,0,32,1,map) && !ir_live_after(16),"empty tracking set");'
            'h_print(1,"CFG liveness oracle and conservative fallbacks pass\\n");return 0;}')
        driver = work / 'oracle'
        subprocess.run([compiler, str(source), '-o', str(driver)], check=True)
        subprocess.run([str(driver), str(fixture)], check=True, timeout=30)
        checks += 6

        helpers = ('global calls=0;fn smash(x){let a=x+1;let b=x+2;let c=x+3;let d=x+4;let e=x+5;let f=x+6;let g=x+7;let h=x+8;let i=0;while i<4{a=a+b;b=b+c;c=c+d;d=d+e;e=e+f;f=f+g;g=g+h;h=h+a;i=i+1;}calls=calls+1;return a+b+c+d+e+f+g+h;}'
                   'fn touch(a,b,c,d,e,f,g,h){calls=calls+1;return a+b+c+d+e+f+g+h;}')
        locals_ = 'let a=x+1;let b=x+2;let c=x+3;let d=x+4;let e=x+5;let f=x+6;let g=x+7;let h=x+8;'
        total = 'a+b+c+d+e+f+g+h'
        call = 'touch(a,b,c,d,e,f,g,h)'
        bodies = [
            (locals_ + f'let n=0;let total=0;while n<4{{smash(n);total=total+{total};n=n+1;}}return total;', lambda x: 32*x+144),
            (locals_ + f'let n=0;let total=0;while n<4{{total=total+{total};smash(n);n=n+1;}}return total;', lambda x: 32*x+144),
            (locals_ + f'let n=0;while n<4{{{call};{call};n=n+1;}}{call};return 42;', lambda x: 42),
            (locals_ + f'let n=0;let total=0;while n<3{{{call};smash(n);if x&1{{total=total+a+b+c+d;}}else{{total=total+e+f+g+h;}}n=n+1;}}return total;', lambda x: 12*x+(30 if x&1 else 78)),
            (locals_ + f'let n=0;let total=0;while n<3{{total=total+{total};smash(n);a=n;b=n+1;c=n+2;d=n+3;e=n+4;f=n+5;g=n+6;h=n+7;n=n+1;}}return total;', lambda x: 8*x+100),
            (locals_ + f'let n=0;while n<3{{{call};n=n+1;}}return a+smash(1)+b+smash(2)+c+d+e+f+g+h;', lambda x: None),
        ]
        for index, (body, expected) in enumerate(bodies):
            for x in (0, 1, 7, 128):
                source.write_text(helpers + f'fn subject(x){{{body}}}fn main(){{let p=alloc(8);store64(p,subject({x}));syscall(1,1,p,8,0,0,0);return 42;}}')
                reference = work / 'reference'
                subprocess.run([baseline or compiler, '--native-pipeline', 'ir' if baseline else 'direct', str(source), '-o', str(reference)], check=True)
                result = subprocess.run([str(reference)], capture_output=True, timeout=10)
                if expected(x) is not None:
                    assert result.returncode == 42 and result.stdout == struct.pack('<Q', expected(x)&MASK), (index, x, result)
                for opt in ('none', 'basic'):
                    binary = work / 'subject'
                    subprocess.run([compiler, '--ir-opt', opt, str(source), '-o', str(binary)], check=True)
                    actual = subprocess.run([str(binary)], capture_output=True, timeout=10)
                    assert (actual.returncode, actual.stdout) == (result.returncode, result.stdout), (index, x, opt, actual, result)
                    checks += 1
        # Compare the very same IR emitter before/after liveness when a
        # baseline compiler is supplied; CI also compares the direct emitter.
        source.write_text(helpers + f'fn subject(x){{{locals_}let n=0;while n<4{{{call};{call};n=n+1;}}{call};return 42;}}fn main(){{return subject(7);}}')
        reference = work / 'size-before'
        actual = work / 'size-after'
        subprocess.run([baseline or compiler, '--native-pipeline', 'ir' if baseline else 'direct', str(source), '-o', str(reference)], check=True)
        subprocess.run([compiler, str(source), '-o', str(actual)], check=True)
        before, after = reference.stat().st_size, actual.stat().st_size
        assert after < before, (before, after)
        checks += 1
    print(f'IR liveness: {checks:,} CFG/oracle, fallback and call-preservation checks pass; call fixture {before} -> {after} bytes')


if __name__ == '__main__':
    main()
