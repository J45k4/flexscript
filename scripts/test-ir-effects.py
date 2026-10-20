#!/usr/bin/env python3
"""Independent call-graph oracle and effect-aware CSE safety checks."""
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ALL = 2047
MASK = (1 << 64) - 1


def words(values):
    return b''.join(struct.pack('<Q', n & MASK) for n in values)


def graph(rng, n):
    # Compute expectations from graph reachability, independently of the
    # compiler's DFS and reverse worklist implementation.
    choices = [(None, 0), ((5, 0), 4), ((6, 0), 8),
               ((17, 1), 257), ((17, 4), 258), ((17, 5), 272),
               ((17, 6), ALL), ((17, 9), ALL), ((19, 0), 928),
               ((20, 0), 928), ((21, 0), 260), ((22, 0), 264),
               ((7, 47), 256), ((7, 37), 256), ((99, 0), ALL)]
    bodies, direct, calls, overrides = [], [], [], []
    for _ in range(n):
        instruction, effect = rng.choice(choices)
        targets = [rng.randrange(n) for _ in range(rng.randrange(5))]
        override = rng.choice([-1] * 6 + [0, ALL, 64, 128, 257])
        body = [(18, 1)]
        if instruction:
            body += [instruction]
        body += [(8, target) for target in targets]
        loop = rng.randrange(9) == 0
        if loop:
            body += [(10, -1)]  # relocated to the branch's own PC
            effect |= 512
        body += [(1, 0), (9, 0)]
        bodies.append(body)
        direct.append(effect if override == -1 else override)
        calls.append(targets if override == -1 else [])
        overrides.append(override)
    reachable = []
    for i in range(n):
        seen, pending = set(), list(calls[i])
        while pending:
            at = pending.pop()
            if at not in seen:
                seen.add(at)
                pending.extend(calls[at])
        reachable.append(seen)
    gold = []
    for i in range(n):
        effect = direct[i]
        for target in reachable[i]:
            effect |= direct[target]
        if any(t in reachable[t] for t in reachable[i] | {i}):
            effect |= 768  # recursion may overflow the stack or never return
        gold.append(effect)
    code, table = [], []
    for body in bodies:
        table += [0, 0, len(code)*16, 0]
        for op, arg in body:
            if op == 10:
                arg = len(code)*16
            code += [(op, arg)]
    return (words([n, len(code)*16]) + words(overrides) + words(table)
            + words(v for instruction in code for v in instruction) + words(gold)), n


def chain(n, recursive):
    # Long precise graphs exercise propagation without Python/compiler DFS
    # recursion. A cycle in the tail affects every caller, but a leaf read
    # alone must never acquire write, external or synchronization effects.
    code, table = [], []
    for i in range(n):
        table += [0, 0, len(code)*16, 0]
        code += [(18, 0)]
        if i+1 < n:
            code += [(8, i+1)]
        else:
            code += [(5, 0)]
            if recursive:
                code += [(8, n//2)]
        code += [(9, 0)]
    return (words([n, len(code)*16]) + words([-1]*n) + words(table)
            + words(v for instruction in code for v in instruction)
            + words([4 | (768 if recursive else 0)]*n)), n


def main():
    compiler = str(Path(os.environ.get('FLEX_COMPILER', ROOT / 'build/flex')).resolve())
    rng = random.Random(516009)
    cases = [graph(rng, n) for n in [1, 1, 2, 3, 32, 256] + [rng.randint(1, 32) for _ in range(384)]]
    cases += [chain(1536, False), chain(1536, True)]
    checks = sum(n for _, n in cases)
    with tempfile.TemporaryDirectory(prefix='flex-ir-effects-') as temporary:
        work = Path(temporary)
        fixture = work / 'graphs.bin'
        fixture.write_bytes(words([len(cases)]) + b''.join(data for data, _ in cases))
        source = work / 'oracle.flex'
        source.write_text(f'import "{ROOT}/scripts/lib/build.flex";import "{ROOT}/compiler/ir-effects.flex";'
            'fn main(argc,argv){h_environment(argc,argv);let p=h_read(load64(argv+8));let cases=load64(p);p=p+8;let c=0;'
            'while c<cases{let n=load64(p);let size=load64(p+8);let overrides=p+16;let table=overrides+n*8;let code=table+n*32;let gold=code+size;'
            'h_assert(ir_effect_analyze(code,size,table,n,overrides),"analysis declined graph");let i=0;while i<n{'
            'h_assert(ir_effect_get(i)==load64(gold+i*8),h_cat3("effect case ",h_int(c),h_cat(" function ",h_int(i))));i=i+1;}'
            'h_assert(ir_effect_get(-1)==2047 && ir_effect_get(n)==2047,"invalid query");p=gold+n*8;c=c+1;}'
            'let table=h_take(32);let code=h_take(64);let over=h_take(8);store64(table+16,0);store64(table+24,0);'
            'store64(code,18);store64(code+8,1);store64(code+16,8);store64(code+24,1);store64(code+32,9);'
            'h_assert(!ir_effect_analyze(code,48,table,1,0) && ir_effect_get(0)==2047,"unknown call fallback");'
            'store64(code+16,10);store64(code+24,17);h_assert(ir_effect_analyze(code,48,table,1,0) && ir_effect_get(0)==2047,"bad edge conservative");'
            'store64(code+16,3);store64(code+24,1);h_assert(ir_effect_analyze(code,48,table,1,0) && ir_effect_get(0)==2047,"bad local conservative");'
            'store64(table+16,16);h_assert(!ir_effect_analyze(code,48,table,1,0) && ir_effect_get(0)==2047,"bad function table");store64(table+16,0);'
            'h_assert(!ir_effect_analyze(code,47,table,1,0) && ir_effect_get(0)==2047,"bad instruction size");'
            'h_assert(!ir_effect_analyze(code,48,table,65537,0) && ir_effect_get(0)==2047,"bounded node scratch");'
            'h_assert(!ir_effect_analyze(code,1048577*16,table,1,0) && ir_effect_get(0)==2047,"bounded instruction scratch");'
            'store64(over,2048);h_assert(!ir_effect_analyze(code,48,table,1,over) && ir_effect_get(0)==2047,"invalid target override");'
            'h_assert(ir_effect_analyze(code,0,table,0,0) && ir_effect_get(0)==2047,"empty graph");'
            'return 0;}')
        driver = work / 'oracle'
        subprocess.run([compiler, str(source), '-o', str(driver)], check=True)
        subprocess.run([str(driver), str(fixture)], check=True, timeout=30)
        checks += len(cases) + 9

        def execute(text, expected, common=None, extra=()):
            source.write_text(text)
            for mode in ('none', 'basic'):
                for engine in ('--interpret', '--jit'):
                    p = subprocess.run([compiler, 'run', engine, '--restricted', '--stats',
                                        '--ir-opt', mode, *extra, str(source)], capture_output=True, timeout=30)
                    assert p.returncode == expected, (p.returncode, p.stderr)
                    if common is not None and mode == 'basic':
                        assert int(re.search(rb'common expressions: (\d+)', p.stderr)[1]) == common, p.stderr
                    if mode == 'basic':
                        assert b'IR effects:' in p.stderr, p.stderr
            return 4

        pure = 'fn clean(x){return x+1;}fn wrap(x){return clean(x);}fn compute(x,y){let a=x*y;wrap(x);let b=x*y;return a+b;}fn main(){return compute(3,7);}'
        checks += execute(pure, 42, 1)
        # A pending outer operand cannot make a span containing a call removable.
        checks += execute('fn clean(x){return x+1;}fn compute(x,y){let a=x*y;let z=a+(clean(x)+(x*y));return z;}fn main(){return compute(3,7);}', 46, 1)
        checks += execute('global g=0;fn change(){g=g+1;return 0;}fn compute(x,y){let a=x*y;change();let b=x*y;return a+b+g;}fn main(){return compute(3,7);}', 43, 0)
        checks += execute('fn bad(x){return 1/x;}fn main(){bad(0);return 42;}', 70)
        checks += execute('fn again(){return again();}fn main(){again();return 42;}', 70, extra=('--fuel=500',))
        checks += execute('fn spin(){while 1{}return 0;}fn main(){spin();return 42;}', 70, extra=('--fuel=500',))
        # Names never imply purity; this function shadows the usual FFI name.
        checks += execute('global g=0;fn ffi_open(x){g=g+x;return g;}fn compute(x,y){let a=x*y;ffi_open(1);let b=x*y;return a+b+g;}fn main(){return compute(3,7);}', 43, 0)

        source.write_text(pure)
        sizes = {}
        for mode in ('none', 'basic'):
            app = work / ('native-' + mode)
            subprocess.run([compiler, '--ir-opt', mode, str(source), '-o', str(app)], check=True)
            assert subprocess.run([str(app)]).returncode == 42
            sizes[mode] = app.stat().st_size
            wasm = work / (mode + '.wasm')
            subprocess.run([compiler, '--ir-opt', mode, '--target', 'wasm32', str(source), '-o', str(wasm)], check=True)
            checks += 2
        assert sizes['basic'] < sizes['none'], sizes
        checks += 1
        # Registered native code has a pure-looking portable stub; it must
        # nevertheless block CSE. Test the shared adapter in isolation too.
        adapter = work / 'adapter.flex'
        adapter.write_text(f'import "{ROOT}/scripts/lib/build.flex";import "{ROOT}/compiler/ir-effects.flex";import "{ROOT}/compiler/ir-effect-targets.flex";'
            'global functions=0;global function_count=1;global output=0;global output_size=48;global vm_mode=1;'
            'global native_ir_target=0;global cpu_cxx_target=0;global ptx_target=0;global sass_target=0;global hip_target=0;global operation=0;'
            'fn lowering_lookup(a,b,c){if vm_mode{return 0;}return operation;}fn cc_kind(i){return operation;}fn gpu_intrinsic(i){return operation;}'
            'fn check(mask){h_assert(ir_effect_prepare(),"prepare");h_assert(ir_effect_get(0)==mask,"target effect");h_assert(vm_mode==1,"restore parsing mode");return 0;}'
            'fn main(){functions=h_take(32);output=h_take(48);store64(output,18);store64(output+16,1);store64(output+32,9);'
            'check(0);operation=127;check(0);native_ir_target=1;check(2047);operation=100;check(0);operation=120;check(259);'
            'native_ir_target=0;operation=15;hip_target=1;check(2047);hip_target=0;ptx_target=1;check(2047);ptx_target=0;sass_target=1;check(2047);'
            'sass_target=0;cpu_cxx_target=1;operation=85;check(2047);operation=100;check(0);return 0;}')
        subprocess.run([compiler, str(adapter), '-o', str(driver)], check=True)
        subprocess.run([str(driver)], check=True)
        checks += 10
    print(f'IR effects: {checks:,} graph, fallback, call-retention and backend checks pass')


if __name__ == '__main__':
    main()
