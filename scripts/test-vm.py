#!/usr/bin/env python3
"""Differential native/interpreter/JIT and capability tests for Flexscript VM."""
import argparse
import json
import os
from pathlib import Path
import re
import random
import resource
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = json.loads((ROOT / 'tests/cases.json').read_text())
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(*args, input=None, timeout=30):
    return subprocess.run([str(a) for a in args], capture_output=True, input=input,
                          timeout=timeout, env={**os.environ, 'PATH': '/no/executables'})


def check(result, status=0, stdout=None):
    assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
    if stdout is not None:
        assert result.stdout == stdout, (result.stdout, stdout)


def stats(result):
    match = re.search(rb'VM steps: (\d+); JIT compilations: (\d+); JIT calls: (\d+); fuel remaining: (\d+)', result.stderr)
    assert match, result.stderr
    return tuple(map(int, match.groups()))


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flexscript-vm-test-') as temporary:
        work = Path(temporary)
        for case in CASES['valid']:
            if case['source'] == 'valid/file-io.flex':
                continue  # Native fixture creates files, which VM execution cannot do.
            source = ROOT / 'tests' / case['source']
            arguments = [a.replace('{work}', str(work)) for a in case['args']]
            native = work / 'native'
            check(run(compiler, source, '-o', native))
            expected = run(native, *arguments)
            check(expected, case['exit'], case['stdout'].encode())
            measurements = []
            for engine in ['--interpret', '--jit']:
                result = run(compiler, 'run', engine, '--stats', source, *arguments)
                check(result, expected.returncode, expected.stdout)
                measurements.append(stats(result))
                count += 1
            assert measurements[0][0] == measurements[1][0], (source, measurements)
            assert measurements[0][3] == measurements[1][3], (source, measurements)

        for case in CASES['invalid']:
            result = run(compiler, 'run', '--interpret', ROOT / 'tests' / case['source'])
            check(result, 1)
            assert case['error'].encode() in result.stderr, result.stderr
            count += 1

        fixture = work / 'app.flex'

        def program(source):
            fixture.write_text(source)
            return fixture

        def trap(name, source, message, options=()):
            nonlocal count
            program(source)
            for engine in ['--interpret', '--jit']:
                result = run(compiler, 'run', engine, *options, fixture)
                check(result, 70)
                assert message.encode() in result.stderr, (name, result.stderr)
                count += 1

        trap('division-zero', 'fn main(){return 1/0;}', 'division trap')
        trap('division-overflow', 'fn main(){return 0x8000000000000000/-1;}', 'division trap')
        trap('remainder-overflow', 'fn main(){return 0x8000000000000000%-1;}', 'division trap')
        for pointer in ['0', '-1', '0x7ffffffffffffff8', '0x8000000000000000']:
            trap('pointer-' + pointer, f'fn main(){{return load64({pointer});}}', 'out of bounds')
        trap('store-boundary', 'fn main(){let p=alloc(8);store64(p+1,1);return 0;}', 'out of bounds')
        trap('read-boundary', 'fn main(){let p=alloc(8);return load8(p+8);}', 'out of bounds')
        trap('fuel', 'fn main(){while 1 {}return 0;}', 'budget exhausted', ('--fuel=100',))
        trap('fuel-called', 'fn spin(){while 1 {}return 0;}fn main(){return spin();}', 'budget exhausted', ('--fuel=100',))
        trap('deadline', 'fn main(){while 1 {}return 0;}', 'deadline exceeded', ('--fuel=1000000000', '--timeout-ms=10'))
        trap('recursion', 'fn recurse(){return recurse();}fn main(){return recurse();}', 'stack limit')
        trap('open-denied', 'fn main(){return syscall(2,"secret",0,0,0,0,0);}', 'capability denied')
        trap('network-denied', 'fn main(){return syscall(41,2,1,0,0,0,0);}', 'capability denied')
        trap('fork-denied', 'fn main(){return syscall(57,0,0,0,0,0,0);}', 'capability denied')
        trap('mmap-denied', 'fn main(){return syscall(9,0,4096,7,34,-1,0);}', 'capability denied')
        trap('ffi-denied', 'fn main(){return ffi_open("libc.so.6");}', 'capability denied')
        trap('function-pointer-denied', 'fn main(){return ffi_call(1,0,0,0,0,0,0);}', 'capability denied')
        trap('stdin-denied', 'fn main(){let p=alloc(8);return syscall(0,0,p,8,0,0,0);}', 'capability denied')
        trap('output-pointer', 'fn main(){return syscall(1,1,0,8,0,0,0);}', 'out of bounds')
        trap('output-limit', 'fn main(){let p=alloc(1048577);return syscall(1,1,p,1048577,0,0,0);}', 'output limit')
        trap('poll-pointer', 'fn main(){return syscall(7,0,1,0,0,0,0);}', 'out of bounds')
        trap('poll-deadline', 'fn main(){return syscall(7,0,0,-1,0,0,0);}', 'deadline exceeded', ('--timeout-ms=10',))
        trap('poll-events', 'fn main(){let p=alloc(8);store64(p,1|(32768<<32));return syscall(7,p,1,0,0,0,0);}', 'capability denied')

        for descriptor,events,expected in [(1,4,4),(4095,1,32),(-1,1,0)]:
            program(f'fn main(){{let p=alloc(8);store64(p,({descriptor}&0xffffffff)|({events}<<32));'
                    f'let n=syscall(7,p,1,0,0,0,0);return (load64(p)>>48)=={expected};}}')
            check(run(compiler,'run',fixture),1);count+=1
        program('fn main(){return syscall(7,0,68,0,0,0,0)==-22;}')
        check(run(compiler,'run',fixture),1);count+=1

        program('fn main(){let p=alloc(4096);return p==-12;}')
        check(run(compiler, 'run', '--memory=4096', fixture), 1)
        count += 1

        # Guest argv includes the script at argv[0], followed by unmodified arguments.
        program('fn main(argc,argv){let p=load64(argv+16);syscall(1,1,p,3,0,0,0);return argc;}')
        check(run(compiler, 'run', fixture, 'first', 'two'), 3, b'two')
        count += 1
        program('fn main(){let p=alloc(8);let n=syscall(0,0,p,8,0,0,0);syscall(1,1,p,n,0,0,0);return 0;}')
        check(run(compiler, 'run', '--allow-stdin', fixture, input=b'input'), 0, b'input')
        count += 1
        started=time.monotonic()
        process=subprocess.Popen([str(compiler), 'run', '--allow-stdin', '--timeout-ms=20', str(fixture)],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            process.wait(timeout=3)
            _, error=process.communicate()
            assert process.returncode==70 and b'deadline exceeded' in error, error
            assert time.monotonic()-started<3
        finally:
            if process.poll() is None: process.kill();process.communicate()
        count += 1

        allowed=work/'allowed';allowed.mkdir();(allowed/'file').write_text('capability read')
        outside=work/'outside';outside.write_text('secret outside capability')
        (allowed/'escape').symlink_to(outside)
        read=ROOT/'examples/vm-read.flex'
        for path in ['file', str(allowed/'file')]:
            check(run(compiler, 'run', f'--allow-read={allowed}', read, path), 0, b'capability read')
            count += 1
        for path in ['../outside', str(outside), 'escape', '/proc/self/mem']:
            result=run(compiler, 'run', f'--allow-read={allowed}', read, path)
            assert result.returncode in [2,70] and not result.stdout, (path, result)
            count += 1
        os.mkfifo(allowed/'fifo')
        for path in ['fifo','.']:
            result=run(compiler,'run',f'--allow-read={allowed}',read,path,timeout=3)
            check(result,70);assert b'capability denied' in result.stderr;count+=1
        trap('write-denied', 'fn main(){return syscall(2,"file",577,384,0,0,0);}',
             'capability denied', (f'--allow-read={allowed}',))
        assert (allowed/'file').read_text()=='capability read'
        # Inherited host descriptors do not become guest descriptors.
        descriptor=os.open(outside,os.O_RDONLY)
        try:
            program(f'fn main(){{let p=alloc(32);return syscall(0,{descriptor},p,32,0,0,0)==-9;}}')
            result=subprocess.run([str(compiler),'run',str(fixture)],pass_fds=(descriptor,),
                                  capture_output=True,timeout=5)
            check(result,1);count+=1
        finally:os.close(descriptor)

        # Nested interpreter uses the outer read capability and cannot obtain
        # additional kernel or FFI access. No external executable is launched.
        nested=[compiler,'run','--interpret',f'--allow-read={ROOT}','--memory=256m',
                '--fuel=100000000','--timeout-ms=10000',ROOT/'flexvm.flex','run','--interpret']
        check(run(*nested,ROOT/'examples/hello.flex'),0,b'Hello from native Flexscript!\n');count+=1
        program('fn main(){return syscall(41,2,1,0,0,0,0);}')
        # Source must be under the delegated directory for the inner compiler.
        sandbox=work/'nested';sandbox.mkdir()
        from bootstrap import bootstrap_source
        # A flattened VM implementation keeps all nested source reads within
        # the temporary root, without broadening the outer capability.
        (sandbox/'flexvm.flex').write_text(bootstrap_source().split('// Static bootstrap core:')[0])
        (sandbox/'network.flex').write_text(fixture.read_text())
        result=run(compiler,'run','--interpret',f'--allow-read={sandbox}','--memory=256m',
                   '--fuel=100000000','--timeout-ms=10000',sandbox/'flexvm.flex','run',
                   '--interpret',sandbox/'network.flex')
        check(result,70);assert b'capability denied' in result.stderr;count+=1

        # Hot-call tiering, explicit JIT and interpreter produce the same result
        # and exact instruction accounting. No performance timing assertion.
        compute=ROOT/'examples/vm-compute.flex'
        values=[]
        for option in ['--interpret', '--jit', '--stats']:
            result=run(compiler, 'run', option, '--stats', compute)
            assert result.returncode==0, result.stderr
            values.append(stats(result));count+=1
        assert values[0][1:3]==(0,0)
        assert values[1][1]==1 and values[1][2]==40, values
        assert values[2][1]==1 and values[2][2]==25, values
        assert len({(value[0],value[3]) for value in values})==1, values
        def limited_memory():
            resource.setrlimit(resource.RLIMIT_AS,(128*1024*1024,128*1024*1024))
        result=subprocess.run([str(compiler),'run','--jit','--stats',str(compute)],
                              capture_output=True,timeout=10,preexec_fn=limited_memory)
        check(result);assert stats(result)[1:3]==(0,0),result.stderr;count+=1

        # Compare full 64-bit results, not only their low-byte exit statuses.
        randomizer=random.Random(671050)
        operators=['+','-','*','^','&','|','<<','>>','==','!=','<','<=','>','>=']
        words=[0,1,-1,2**63-1,-2**63,0x1122334455667788]
        for index in range(80):
            a=randomizer.choice(words) if index<20 else randomizer.getrandbits(64)
            b=randomizer.choice(words) if index<20 else randomizer.getrandbits(64)
            left=f'(a {randomizer.choice(operators)} b)'
            if index%3==0:left=f'(a {randomizer.choice(["/","%"])} (b|1))'
            expression=f'({left} {randomizer.choice(operators)} ((a>>3) {randomizer.choice(operators)} (b|1)))'
            program(f'fn calculate(a,b){{return {expression};}}fn main(){{let p=alloc(8);'
                    f'store64(p,calculate(0x{a&((1<<64)-1):016x},0x{b&((1<<64)-1):016x}));'
                    'syscall(1,1,p,8,0,0,0);return 0;}')
            native=work/'native';check(run(compiler,fixture,'-o',native))
            expected=run(native)
            # The min-int / -1 case is an intentional division trap.
            if expected.returncode!=0:
                assert expected.returncode==-8,expected
                for engine in ['--interpret','--jit']:
                    result=run(compiler,'run',engine,fixture);check(result,70)
                    assert b'division trap' in result.stderr;count+=1
            else:
                assert len(expected.stdout)==8
                for engine in ['--interpret','--jit']:
                    check(run(compiler,'run',engine,fixture),0,expected.stdout);count+=1

        # Observe generated code mappings while a compiled leaf loop is live.
        program('fn spin(){while 1 {}return 0;}fn main(){return spin();}')
        process=subprocess.Popen([str(compiler),'run','--jit','--fuel=1000000000','--timeout-ms=500',str(fixture)],
                                 stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        observed=False
        try:
            end=time.monotonic()+3
            while process.poll() is None and time.monotonic()<end:
                try:maps=Path(f'/proc/{process.pid}/maps').read_text().splitlines()
                except FileNotFoundError:break
                anonymous=[line.split() for line in maps if len(line.split())==5]
                assert not any('rwx' in fields[1] for fields in anonymous), 'writable executable JIT mapping'
                if any(fields[1].startswith('r-x') for fields in anonymous):observed=True;break
                time.sleep(.005)
            _,error=process.communicate(timeout=3)
            assert observed,'no executable JIT mapping observed'
            assert process.returncode==70 and b'deadline exceeded' in error,error
            count+=1
        finally:
            if process.poll() is None:process.kill();process.communicate()

        for option in ['--fuel=0','--fuel=-1','--memory=1','--timeout-ms=0','--fuel=99999999999999999999','--unknown','--allow-read=']:
            check(run(compiler, 'run', option, compute), 1);count+=1
        check(run(compiler, 'run'),1);count+=1
        check(run(compiler, 'run','--help'));count+=1

    print(f'{compiler.name}: {count} VM checks passed',flush=True)
    return count


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers',nargs='+',type=Path)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    results=[{'compiler':str(p),'checks':suite(p.resolve())} for p in args.compilers]
    total=sum(r['checks'] for r in results)
    if args.report: args.report.write_text(json.dumps({'results':results,'total':total},indent=2)+'\n')
    print(f'Total: {total} VM checks passed')


if __name__=='__main__':main()
