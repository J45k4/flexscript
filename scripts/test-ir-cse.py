#!/usr/bin/env python3
"""Independent word-oracle and backend checks for local arithmetic CSE."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1


def word(n):
    n &= MASK
    return n - (1 << 64) if n >> 63 else n


def binary(op, a, b):
    if op == '<<':
        return word(a << (b & 63))
    if op == '>>':
        return word(a >> (b & 63))
    return word(int(eval('a ' + op + ' b', {}, dict(a=a, b=b))))


def random_result(a, b, operations):
    for op in operations:
        t = binary(op, a, b)
        a = word(t+t)
        b = word(b^a)
    return word(a^b)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gpu', action='store_true', help='Execute the RDNA corpus on an AMD GPU')
    args = parser.parse_args()
    compiler = str(Path(os.environ.get('FLEX_COMPILER', ROOT / 'build/flex')).resolve())
    checks = 0
    definitions, oracles = [], []

    def case(body, oracle):
        name = 'cse_' + str(len(definitions))
        definitions.append(f'fn {name}(x,y){{{body}}}')
        oracles.append((name, oracle))

    for op in ('+', '-', '*', '&', '|', '^', '<<', '>>', '==', '!=', '<', '>', '<=', '>='):
        case(f'let a=x {op} y;let b=x {op} y;return a+b;',
             lambda x, y, op=op: word(binary(op, x, y) * 2))
    for op in ('+', '*', '&', '|', '^', '==', '!='):
        case(f'let a=x {op} y;let b=y {op} x;return a+b;',
             lambda x, y, op=op: word(binary(op, x, y) * 2))
    case('let a=(x+y)*(x-y);let b=(x+y)*(x-y);return a+b;',
         lambda x, y: word(word(x+y)*word(x-y)*2))
    case('let a=x*y;x=x+1;let b=x*y;return a+b;', lambda x, y: word(x*y+word(x+1)*y))
    case('let a=x*y;a=x+y;let b=x*y;return a+b;', lambda x, y: word(x+y+x*y))
    case('let a=x*y;let b=a;a=0;let c=x*y;return b+c;', lambda x, y: word(x*y*2))
    case('let a=x-y;let b=y-x;return a^b;', lambda x, y: word(word(x-y)^word(y-x)))
    case('let a=x+y;let b=x+y;let c=(x+y)*(x+y);return a+b+c;',
         lambda x, y: word(word(x+y)*2+word(x+y)*word(x+y)))
    case('let a=-x;let b=-x;let c=~y;let d=~y;let e=!x;let f=!x;return a+b+c+d+e+f;',
         lambda x, y: word(-x*2+(~y)*2+int(not x)*2))
    case('let a=x*y;if x&1{a=x+y;}let b=x*y;return a+b;',
         lambda x, y: word((x+y if x&1 else x*y)+x*y))
    case('let a=x*y;let n=0;while n<3{x=x+1;a=x*y;n=n+1;}let b=x*y;return a+b;',
         lambda x, y: word(word(x+3)*y*2))
    case('let a=x+9;let b=x+9;return a+b;', lambda x, y: word((x+9)*2))
    rng = random.Random(3198)
    operations = [rng.choice(('+', '-', '*', '^', '|', '&', '<<', '>>')) for _ in range(80)]
    body = 'let a=x;let b=y;let t=0;let u=0;'
    for op in operations:
        body += f't=a {op} b;u=a {op} b;a=t+u;b=b^a;'
    case(body + 'return a^b;', lambda x, y: random_result(x, y, operations))
    inputs = [(0, 0), (-1, 1), (-(1 << 63), -1), ((1 << 63)-1, 64), (7, 130)]
    inputs += [(word(rng.getrandbits(64)), word(rng.getrandbits(64))) for _ in range(27)]
    expected = [oracle(x, y) & MASK for x, y in inputs for _, oracle in oracles]
    raw = b''.join(struct.pack('<Q', value) for value in expected)
    width = len(oracles)
    kernel = 'fn kernel(i,input,output,count){let x=load64(input+i*16);let y=load64(input+i*16+8);'
    for index, (name, _) in enumerate(oracles):
        kernel += f'store64(output+(i*{width}+{index})*8,{name}(x,y));'
    kernel += 'return 0;}'
    entry = f'fn main(){{let input=alloc({len(inputs)*16});let out=alloc({len(raw)});'
    for index, (x, y) in enumerate(inputs):
        entry += f'store64(input+{index*16},0x{x&MASK:x});store64(input+{index*16+8},0x{y&MASK:x});'
    entry += f'let i=0;while i<{len(inputs)}{{kernel(i,input,out,{len(inputs)});i=i+1;}}'
    entry += f'let sent=0;while sent<{len(raw)}{{let n=syscall(1,1,out+sent,{len(raw)}-sent,0,0,0);if n<=0{{return 9;}}sent=sent+n;}}return 0;}}'
    with tempfile.TemporaryDirectory(prefix='flex-ir-cse-') as temporary:
        work = Path(temporary)
        source = work / 'test.flex'
        source.write_text('\n'.join(definitions + [kernel, entry]))

        def compile_file(path, mode='basic', target=None, src=source):
            command = [compiler, '--ir-opt', mode]
            if target:
                command += ['--target', target]
            subprocess.run(command + [str(src), '-o', str(path)], check=True, timeout=120)

        for mode in ('none', 'basic'):
            for engine in ('--interpret', '--jit'):
                p = subprocess.run([compiler, 'run', engine, '--restricted', '--stats',
                                    '--ir-opt', mode, str(source)], capture_output=True, timeout=60)
                assert p.returncode == 0 and p.stdout == raw, (mode, engine, p.stderr)
                count = int(re.search(rb'common expressions: (\d+)', p.stderr)[1])
                assert count >= 80 if mode == 'basic' else count == 0, (mode, count)
                checks += len(expected)
            app = work / ('native-' + mode)
            compile_file(app, mode)
            p = subprocess.run([str(app)], capture_output=True, timeout=30)
            assert p.returncode == 0 and p.stdout == raw, (mode, p.stderr)
            checks += len(expected)
            wasm = work / ('test-' + mode + '.wasm')
            compile_file(wasm, mode, 'wasm32')
            request = work / 'request.json'
            request.write_text(json.dumps(dict(module=str(wasm))))
            result = json.loads(subprocess.check_output(['bun', str(ROOT / 'scripts/wasm-runner.js'), str(request)]))
            assert result.get('valid') and not result.get('error') and result['stdoutHex'] == raw.hex(), result
            checks += len(expected)
            cxx = work / ('cpu-' + mode + '.cpp')
            compile_file(cxx, mode, 'cpu-cxx')
            library = work / ('cpu-' + mode + '.so')
            subprocess.run(['g++', '-std=c++17', '-O2', '-shared', '-fPIC', str(cxx), '-o', str(library)], check=True)
            fn = ctypes.CDLL(str(library)).flex_kernel
            fn.argtypes = [ctypes.c_uint64] * 4
            fn.restype = ctypes.c_uint64
            data = (ctypes.c_uint64 * (len(inputs)*2))(*(n&MASK for pair in inputs for n in pair))
            out = (ctypes.c_uint64 * len(expected))()
            for index in range(len(inputs)):
                fn(index, ctypes.addressof(data), ctypes.addressof(out), len(inputs))
            assert list(out) == expected
            checks += len(expected)
            for target in ('ptx', 'sass-sm75', 'hip', 'rdna-gfx1201'):
                # The random stress helper stays in host/CPU checks: the direct
                # GPU inliner has a finite register budget, independent of CSE.
                gpu_source = work / 'gpu.flex'
                gpu_source.write_text('\n'.join(definitions[:-1]) + '\n' + kernel.replace(
                    f'store64(output+(i*{width}+{width-1})*8,cse_{width-1}(x,y));', ''))
                image = work / (target + '-' + mode)
                compile_file(image, mode, target, gpu_source)
                checks += 1
                if target == 'rdna-gfx1201' and args.gpu:
                    run_gpu(compiler, work, image, inputs, expected, width)
                    checks += len(inputs)*(width-1)

        source.write_text('global calls=0;fn next(){calls=calls+1;return calls;}fn change(p){store64(p,11);return 0;}fn main(){let p=alloc(8);store64(p,7);let x=load64(p);let a=x*3;store64(p,9);let y=load64(p);let b=y*3;if a!=21 || b!=27{return 1;}change(p);if load64(p)*3!=33{return 2;}let c=next()*2;let d=next()*2;if c!=2 || d!=4{return 3;}let n=0;let total=0;while n<5{let k=n*7;if n&1{k=n+3;}total=total+k+(n*7);n=n+1;}if total!=122{return 4;}return 42;}')
        for mode in ('none', 'basic'):
            for engine in ('--interpret', '--jit'):
                p = subprocess.run([compiler, 'run', engine, '--restricted', '--ir-opt', mode, str(source)], capture_output=True)
                assert p.returncode == 42, p
                checks += 1
            compile_file(work / 'effects', mode)
            assert subprocess.run([str(work / 'effects')]).returncode == 42
            checks += 1
        source.write_text('fn compute(x,y){let a=x/y;y=0;return a+(x/y);}fn main(){return compute(9,3);}')
        for mode in ('none', 'basic'):
            p = subprocess.run([compiler, 'run', '--interpret', '--restricted', '--ir-opt', mode, str(source)], capture_output=True)
            assert p.returncode == 70 and b'integer division trap' in p.stderr, p
            checks += 1
        # Saturate the bounded value table with distinct live holders. Missed
        # opportunities must remain correct and compile in bounded time.
        stress = 'fn stress(x){let total=0;'
        for index in range(1800):
            stress += f'let a{index}=x+{index};let b{index}=x+{index};total=total+a{index}+b{index};'
        stress += 'return total;}fn main(){let p=alloc(8);store64(p,stress(17));syscall(1,1,p,8,0,0,0);return 42;}'
        source.write_text(stress)
        gold = struct.pack('<Q', sum(2*(17+i) for i in range(1800)))
        for mode in ('none', 'basic'):
            p = subprocess.run([compiler, 'run', '--interpret', '--restricted', '--ir-opt', mode, str(source)], capture_output=True, timeout=30)
            assert p.returncode == 42 and p.stdout == gold, p
            compile_file(work / 'stress', mode)
            p = subprocess.run([str(work / 'stress')], capture_output=True, timeout=30)
            assert p.returncode == 42 and p.stdout == gold, p
            checks += 2
        sizes = {}
        for label, body in (('duplicate', 'let a=x*y;let b=x*y;return a+b;'),
                            ('control', 'let a=x*y;let b=a;return a+b;')):
            source.write_text('fn compute(x,y){'+body+'}fn main(argc,argv){return compute(argc,7);}')
            compile_file(work / label)
            sizes[label] = (work / label).stat().st_size
        assert sizes['duplicate'] == sizes['control'], sizes
        checks += 1
    print(f'IR CSE: {checks:,} word-oracle/backend checks pass; native, VM/JIT, Wasm and CPU C++ execute; GPU targets compile'
          + ('; RDNA executes' if args.gpu else ''))


def run_gpu(compiler, work, image, inputs, expected, width):
    data = work / 'input.bin'
    data.write_bytes(b''.join(struct.pack('<Q', n&MASK) for pair in inputs for n in pair))
    words = [n if i%width != width-1 else 0 for i, n in enumerate(expected)]
    gold = work / 'expected.bin'
    gold.write_bytes(b''.join(struct.pack('<Q', n) for n in words))
    host = work / 'gpu-host.flex'
    host.write_text(f'import "{ROOT}/scripts/lib/build.flex";import "{ROOT}/lib/hip.flex";'
                    'fn check(n){h_assert(!n,hip_error());return 0;}'
                    'fn main(argc,argv){h_environment(argc,argv);let ctx=hip_context_device(0);check(hip_status);'
                    f'let input=h_read("{data}");let xp=hip_buffer({len(inputs)*16});check(hip_status);check(hip_upload(xp,input,{len(inputs)*16}));'
                    f'let out=h_take({len(expected)*8});let yp=hip_buffer({len(expected)*8});check(hip_status);check(hip_upload(yp,out,{len(expected)*8}));'
                    f'let module=hip_module(h_read("{image}"));check(hip_status);check(hip_launch(module,xp,yp,{len(inputs)}));check(hip_download(out,yp,{len(expected)*8}));'
                    f'let gold=h_read("{gold}");h_assert(h_bytes(out,gold,{len(expected)*8}),"CSE GPU/oracle mismatch");'
                    'check(hip_free(yp));check(hip_free(xp));check(hip_unload(module));check(hip_close(ctx));return 0;}')
    binary = work / 'gpu-host'
    subprocess.run([compiler, str(host), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == '__main__':
    main()
