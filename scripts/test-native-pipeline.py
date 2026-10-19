#!/usr/bin/env python3
"""Check native IR/direct parity for static addresses, host ABI and defaults."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    compiler = str(Path(os.environ.get("FLEX_COMPILER", "build/flex")).resolve())
    checks = 0
    cases = [
        ('fn main(){let a="ab\\0cd";let b="ab\\0cd";store8(a,90);if load8(b)!=97{return 1;}if load8(a+2)!=0 || load8(a+3)!=99{return 2;}if a==16 || b==24{return 3;}syscall(1,1,a,6,0,0,0);return 42;}', 42, b'Zb\x00cd\x00'),
        ('global a=0x8000000000000000;global b=-1;global c=0;fn step(){c=c+1;return c;}fn main(){if a+b!=0x7fffffffffffffff{return 1;}let x=step();if x!=1 || c!=1{return 2;}let p=alloc(16);store64(p,a);store64(p+8,b);if load64(p)!=a || load64(p+8)!=b{return 3;}return 42;}', 42, b''),
        ('fn main(argc,argv){if argc!=2{return 1;}let text=load64(argv+8);if load8(text)!=97 || load8(text+1)!=114{return 2;}if load64(argv+argc*8)!=0{return 3;}return 42;}', 42, b''),
        ('fn main(){let c=ffi_open("libc.so.6");if !c{return 1;}let f=ffi_symbol(c,"getpid");if !f{return 2;}if ffi_call(f,0,0,0,0,0,0)!=syscall(39,0,0,0,0,0,0){return 3;}let close=ffi_symbol(c,"close");if ffi_call_i32(close,-1,0,0,0,0,0)!=-1{return 4;}if ffi_call_u32(close,-1,0,0,0,0,0)!=4294967295{return 5;}return 42;}', 42, b''),
        ('fn use(a,b,c,d,e,f,g,h){return a+b+c+d+e+f+g+h;}fn recurse(n){let a=n+1;let b=n+2;let c=n+3;let d=n+4;let e=n+5;let f=n+6;let g=n+7;let h=n+8;if n{let child=recurse(n-1);use(8,7,6,5,4,3,2,1);return a+b+c+d+e+f+g+h+child;}return a+b+c+d+e+f+g+h;}fn main(){return recurse(4);}', 4, b''),
    ]
    with tempfile.TemporaryDirectory(prefix="flex-native-pipeline-") as directory:
        work = Path(directory)
        source = work / "test.flex"
        binary = work / "app"

        def compile_file(mode, opt="basic"):
            args = [compiler]
            if mode is not None:
                args += ["--native-pipeline", mode]
            subprocess.run(args + ["--ir-opt", opt, str(source), "-o", str(binary)], check=True)
            data = binary.read_bytes()
            assert data[:4] == b"\x7fELF"
            return data

        for text, status, stdout in cases:
            source.write_text(text)
            for mode in ("direct", "ir", None):
                for opt in ("none", "basic"):
                    compile_file(mode, opt)
                    p = subprocess.run([str(binary), "argument"], capture_output=True, timeout=10)
                    assert p.returncode == status and p.stdout == stdout, (mode, opt, p)
                    checks += 1
        source.write_text('fn main(){if 0{return ffi_open("unreachable.so");}return (2+3)*(8-1)+7;}')
        reference = compile_file("ir")
        assert b"/lib64/ld-linux-x86-64.so.2" not in reference
        assert compile_file(None) == reference, "native IR is not the default"
        checks += 2
        original = hashlib.sha256(binary.read_bytes()).digest()
        source.write_text('fn unused(){return missing();}fn main(){return 42;}')
        p = subprocess.run([compiler, str(source), "-o", str(binary)], capture_output=True)
        assert p.returncode == 1 and b"undefined function" in p.stderr
        assert hashlib.sha256(binary.read_bytes()).digest() == original
        checks += 2
        for options in (["--native-pipeline", "bad"], ["--native-pipeline", "ir", "--native-pipeline", "direct"],
                        ["--target", "wasm32", "--native-pipeline", "ir"]):
            p = subprocess.run([compiler, *options, str(source), "-o", str(binary)], capture_output=True)
            assert p.returncode == 1
            checks += 1
        # Call-heavy initialization must not save future, undefined cached
        # locals around every earlier call. These are ordinary ABI calls.
        source.write_text('global count=0;fn next(){count=count+1;return count;}fn main(){let a=next();let b=next();let c=next();let d=next();let e=next();let f=next();let g=next();let h=next();let i=0;while i<3 {a=a+b+c+d+e+f+g+h;i=i+1;}return a;}')
        direct = compile_file("direct")
        p = subprocess.run([str(binary)], capture_output=True, timeout=5)
        optimized = compile_file("ir")
        q = subprocess.run([str(binary)], capture_output=True, timeout=5)
        assert p.returncode == q.returncode
        assert len(optimized) <= len(direct), (len(direct), len(optimized))
        checks += 2
    print(f"Native pipeline: {checks} IR/direct/default, mutable binary literals, globals, argc/argv, FFI, recursion, validation and size checks pass")


if __name__ == "__main__":
    main()
