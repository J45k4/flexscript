#!/usr/bin/env python3
"""Check the native C ABI bridge and optional dynamic linking."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(*args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=20, env=env)


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flex ffi-') as temp:
        work = Path(temp)
        c = work / 'library.c'
        c.write_text('''#include <stdint.h>
#include <stdlib.h>
static long state;
long six(long a,long b,long c,long d,long e,long f){return a+2*b+3*c+4*d+5*e+6*f;}
int negative(void){return -17;}
unsigned high(void){return 0xf1234567U;}
uint64_t word(void){return UINT64_C(0xf123456789abcdef);}
void set(long n){state=n;}
long get(void){return state;}
void* same(void* p){return p;}
long aligned(void){uintptr_t p;__asm__("mov %%rsp,%0":"=r"(p));return (p&15)==8;}
''')
        library = work / 'library.so'
        result = run('cc', '-shared', '-fPIC', '-O2', c, '-o', library)
        assert result.returncode == 0, result.stderr

        def check(source, status=0, stdout=b'', dynamic=True, env=None):
            nonlocal count
            path = work / 'test.flex'
            binary = work / 'program'
            path.write_text(source)
            result = run(compiler, path, '-o', binary)
            assert result.returncode == 0, result.stderr
            result = run(binary, env=env)
            assert (result.returncode, result.stdout) == (status, stdout), (result.returncode, result.stdout, result.stderr)
            elf = binary.read_bytes()
            headers = int.from_bytes(elf[56:58], 'little')
            assert headers == (4 if dynamic else 1)
            count += 1

        check('fn main(){return 42;}', 42, dynamic=False)
        check('fn main(){let p=alloc(4096);store8(p,72);store8(p+1,137);store8(p+2,224);'
              'store8(p+3,131);store8(p+4,224);store8(p+5,15);store8(p+6,195);'
              'if syscall(10,p,4096,5,0,0,0)<0 {return 99;}return ffi_call(p,0,0,0,0,0,0);}',
              8, dynamic=False)
        prefix = f'fn main(){{let lib=ffi_open("{library}");if !lib{{return 99;}}'
        check(prefix + 'let f=ffi_symbol(lib,"six");return ffi_call(f,1,2,3,4,5,6);}', 91)
        check(prefix + 'let f=ffi_symbol(lib,"negative");return ffi_call_i32(f,0,0,0,0,0,0)==-17;}', 1)
        check(prefix + 'let f=ffi_symbol(lib,"high");return ffi_call_u32(f,0,0,0,0,0,0)==0xf1234567;}', 1)
        check(prefix + 'let f=ffi_symbol(lib,"word");return ffi_call(f,0,0,0,0,0,0)==0xf123456789abcdef;}', 1)
        check(prefix + 'let f=ffi_symbol(lib,"same");let p=alloc(32);return ffi_call(f,p,0,0,0,0,0)==p;}', 1)
        check(prefix + 'let f=ffi_symbol(lib,"aligned");return 1+ffi_call(f,0,0,0,0,0,0);}', 2)
        check(prefix + 'let f=ffi_symbol(lib,"aligned");return 1+(2+ffi_call(f,0,0,0,0,0,0));}', 4)
        check(prefix + 'let f=ffi_symbol(lib,"aligned");return ffi_call(f,0,0,0,0,0,0)+ffi_call(f,0,0,0,0,0,0);}', 2)
        check(prefix + 'ffi_call(ffi_symbol(lib,"set"),73,0,0,0,0,0);return ffi_call(ffi_symbol(lib,"get"),0,0,0,0,0,0);}', 73)
        check(prefix + 'return ffi_symbol(lib,"missing_symbol")==0;}', 1)
        check('fn main(){return ffi_open("/no/such/library.so")==0;}', 1)
        check('fn main(){let l=ffi_open("libc.so.6");return ffi_call(ffi_symbol(l,"strlen"),"abc",0,0,0,0,0);}', 3)
        env = {**os.environ, 'FLEX_FFI_TEST': 'yes'}
        check('fn main(){let l=ffi_open("libc.so.6");let p=ffi_call(ffi_symbol(l,"getenv"),"FLEX_FFI_TEST",0,0,0,0,0);return load8(p)==121;}', 1, env=env)
        check('fn ffi_open(x){return x+1;} fn main(){return ffi_open(40);}', 41, dynamic=False)
        check('fn ffi_call(p,a,b,c,d,e,f){return a;} fn main(){return ffi_call(0,42,0,0,0,0,0);}', 42, dynamic=False)
        check('import "' + str(ROOT / 'lib/ffi.flex') + '"; fn main(){let l=ffi_open("libc.so.6");return ffi_close(l);}')
        for call in ['ffi_open()', 'ffi_open(1,2)', 'ffi_symbol(1)', 'ffi_call(1,2)',
                     'ffi_call_i32(1,2)', 'ffi_call_u32(1,2)']:
            path = work / 'bad.flex'
            path.write_text(f'fn main(){{return {call};}}')
            result = run(compiler, path, '-o', work / 'invalid')
            assert result.returncode == 1 and b'wrong FFI argument count' in result.stderr, result.stderr
            assert not (work / 'invalid').exists()
            count += 1
    print(f'{compiler.name}: {count} FFI checks passed', flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers', nargs='+', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = [{'compiler': str(p), 'checks': suite(p.resolve())} for p in args.compilers]
    total = sum(r['checks'] for r in results)
    if args.report:
        args.report.write_text(json.dumps({'results': results, 'total': total}, indent=2) + '\n')
    print(f'Total: {total} FFI checks passed')


if __name__ == '__main__':
    main()
