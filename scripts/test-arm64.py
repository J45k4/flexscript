#!/usr/bin/env python3
"""Execute direct ARM64 output in QEMU and compare against x86/Python/LLVM.

Run from the repository root. QEMU is required; LLVM's assembler/linker are
required for the independent calling-convention oracle. No third-party Python
packages or ARM sysroot are needed. Generated programs use native instructions.
"""
import argparse
import json
import os
from pathlib import Path
import random
import resource
import shutil
import signal
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--qemu", default=shutil.which("qemu-aarch64") or shutil.which("qemu-aarch64-static"))
    parser.add_argument("--report", type=Path, default=Path("build/arm64-tests.json"))
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    assert args.qemu, "Install qemu-user or qemu-user-static (qemu-aarch64)"
    for tool in ("clang", "ld.lld"):
        assert shutil.which(tool), f"{tool} is required for the independent ABI oracle"
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    checks = []

    def run(command, data=b"", timeout=30):
        return subprocess.run([str(x) for x in command], input=data, capture_output=True, timeout=timeout)

    def ok(command):
        result = run(command)
        assert result.returncode == 0, (command, result.returncode, result.stderr.decode(errors="replace"))
        return result

    def passed(name):
        checks.append(name)
        print("PASS", name, flush=True)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="arm64-tests-", dir=args.report.parent.resolve()) as directory:
        work = Path(directory)
        arm = work / "arm"
        native = work / "native"
        fixture = work / "program.flex"

        def compile_arm(source, *options):
            ok([compiler, "--target", "linux-arm64", *options, source, "-o", arm])
            assert os.access(arm, os.X_OK), "ARM64 executable lacks execute permissions"

        def result_is(program, status, stdout=b"", data=b"", argv=()):
            result = run([args.qemu, program, *argv], data)
            assert (result.returncode, result.stdout) == (status, stdout), (
                program, result.returncode, result.stdout[:200], result.stderr[:1000])

        def differential(name, source, expected=None):
            fixture.write_text(source)
            compile_arm(fixture)
            ok([compiler, fixture, "-o", native])
            reference = run([native])
            result = run([args.qemu, arm])
            assert (result.returncode, result.stdout) == (reference.returncode, reference.stdout), (
                name, result, reference)
            if expected is not None:
                assert result.returncode == expected, (name, result)
            passed(name)

        cases = json.loads(Path("tests/cases.json").read_text())
        for case in cases["valid"]:
            # The existing file fixture has the x86 open syscall signature;
            # the ARM64 openat/read/write/close fixture below exercises file I/O.
            if case["source"].endswith("file-io.flex"):
                continue
            text = (Path("tests") / case["source"]).read_text()
            for old, new in ((0, 63), (1, 64), (3, 57)):
                text = text.replace(f"syscall({old},", f"syscall({new},")
            fixture.write_text(text)
            compile_arm(fixture)
            result_is(arm, case["exit"], case["stdout"].encode(), argv=case["args"])
            passed(case["source"])

        for case in cases["invalid"]:
            arm.write_bytes(b"preserve existing output")
            result = run([compiler, "--target", "linux-arm64", Path("tests") / case["source"], "-o", arm])
            assert result.returncode == 1 and case["error"].encode() in result.stderr, (case, result)
            assert arm.read_bytes() == b"preserve existing output"
            passed(case["source"])

        # Independent mathematical oracle, comparing every output bit. Cover
        # boundaries and deterministic random operands for all binary operators.
        rng = random.Random(0xA64)
        mask = (1 << 64) - 1
        minimum = -(1 << 63)

        def signed(value):
            return ((value + (1 << 63)) & mask) - (1 << 63)

        values = [minimum, minimum + 1, -65536, -65, -64, -1, 0, 1, 2, 63, 64, 65, 65535, (1 << 63) - 1]
        pairs = [(a, b) for a in values for b in values]
        pairs += [(signed(rng.getrandbits(64)), signed(rng.getrandbits(64))) for _ in range(128)]
        expressions = []
        expected = bytearray()
        for a, b in pairs:
            operations = {
                "+": a + b, "-": a - b, "*": a * b,
                "&": a & b, "|": a | b, "^": a ^ b,
                "<<": a << (b & 63), ">>": a >> (b & 63),
                "==": int(a == b), "!=": int(a != b), "<": int(a < b),
                ">": int(a > b), "<=": int(a <= b), ">=": int(a >= b),
            }
            if b and (a, b) != (minimum, -1):
                quotient = (abs(a) // abs(b)) * (-1 if (a < 0) != (b < 0) else 1)
                operations.update({"/": quotient, "%": a - quotient * b})
            for operator, value in operations.items():
                expressions.append(f"out(0x{a & mask:x}{operator}0x{b & mask:x});")
                expected.extend(struct.pack("<Q", value & mask))
        body = "fn main(){" + "".join(expressions) + "return 0;}"
        outputs = []
        for target, number, binary in (("linux-arm64", 64, arm), (None, 1, native)):
            fixture.write_text("global buffer=0;fn out(value){if !buffer {buffer=alloc(8);}store64(buffer,value);"
                               f"return syscall({number},1,buffer,8,0,0,0);" + "}" + body)
            options = ["--target", target] if target else []
            ok([compiler, *options, fixture, "-o", binary])
            result = run(([args.qemu] if target else []) + [binary])
            assert result.returncode == 0 and result.stdout == expected, (target, result.returncode, len(result.stdout))
            outputs.append(result.stdout)
        assert outputs[0] == outputs[1]
        passed(f"{len(expressions)} full-width arithmetic results: Python + x86-64 + QEMU")

        for count in (0, 1, 7, 8, 9, 10, 17, 65, 4096):
            params = ",".join(f"a{i}" for i in range(count))
            arguments = ",".join(str(i + 1) for i in range(count))
            total = "+".join(f"a{i}*{i + 1}" for i in range(count)) or "0"
            answer = sum(i * i for i in range(1, count + 1))
            differential(f"AAPCS64 argument count {count}",
                         f"fn f({params}){{return {total};}}fn main(){{return f({arguments})!={answer};}}", 0)

        differential("nested calls retain live expressions and left-to-right side effects",
                     "global n=0;fn next(){n=n+1;return n;}fn sum(a,b,c,d,e,f,g,h,i){return a+b+c+d+e+f+g+h+i;}"
                     "fn main(){return (100+sum(next(),next(),next(),next(),next(),next(),next(),next(),sum(1,2,3,4,5,6,7,8,next()))!=181)||(n!=9);}", 0)
        differential("4096 local frame slots", "fn main(){" + "".join(f"let v{i}={i};" for i in range(4096))
                     + "return (v0+v511+v512+v4095)!=5118;}", 0)
        differential("allocation errors and writable string storage",
                     'fn main(){let s="hello";store8(s+1,97);return (alloc(0)!=-22)||(alloc(-1)!=-12)||(load8(s+1)!=97);}', 0)
        differential("forward and backward branches beyond conditional branch range",
                     "fn main(){let n=0;if 0 {" + "n=n+1;" * 17000
                     + "}while n<1 {" + "n=n+0;" * 17000 + "n=n+1;}return n;}", 1)

        for expression in ("1/0", "1%0", "0x8000000000000000/-1", "0x8000000000000000%-1"):
            fixture.write_text(f"fn main(){{return {expression};}}")
            compile_arm(fixture)
            result = run([args.qemu, arm])
            assert result.returncode == -signal.SIGTRAP, (expression, result)
            passed("arithmetic trap " + expression)

        compile_arm(Path("examples/arm64/hello.flex"))
        result_is(arm, 0, b"Hello from native ARM64 Flexscript!\n")
        passed("imports and ARM64 hello executable")
        compile_arm(Path("tests/arm64/file-io.flex"))
        result_is(arm, 0, b"native arm64\n", argv=[work / "file.txt"])
        assert (work / "file.txt").read_bytes() == b"native arm64\n"
        passed("ARM64 file I/O, mmap/munmap, clock and errno")

        compile_arm(Path("tests/arm64/state.seta"))
        result_is(arm, 1, struct.pack("<qq", 57, 42), struct.pack("<q", 42))
        passed("SetaScript state, checked arrays and word I/O")
        seta = work / "program.seta"
        seta.write_text("plugin arm64.eof v1 {} fn main()->i32 {write_word(read_word()) return 0}")
        compile_arm(seta)
        for data in (b"", b"partial"):
            result_is(arm, 0, struct.pack("<q", -1), data)
        passed("word input EOF and incomplete word return -1")
        for index in (-1, 4):
            for operation in (f"return state.a[{index}]", f"state.a[{index}]=7 return 0"):
                seta.write_text(f"plugin arm64.bounds v1 {{}} state {{a:i32[4]=0}} fn main()->i32 {{{operation}}}")
                compile_arm(seta)
                assert run([args.qemu, arm]).returncode == -signal.SIGTRAP
        passed("array load/store bounds trap for negative and past-end indexes")
        compile_arm(Path("examples/seta/policy.seta"))
        result_is(arm, 42)
        passed("SetaScript control flow")
        seta.write_text("plugin arm64.large v1 {} state {a:i32[1048576]=0} "
                        "fn main()->i32 {state.a[1048575]=42 return state.a[1048575]}")
        compile_arm(seta)
        result_is(arm, 42)
        passed("large FIR state image and array address beyond 8 MiB")
        fir = work / "state.fir"
        ok([compiler, "--target", "ir", "tests/arm64/state.seta", "-o", fir])
        compile_arm(fir, "--language", "ir")
        result_is(arm, 1, struct.pack("<qq", 57, 42), struct.pack("<q", 42))
        passed("serialized FIR input")
        seta.write_text("plugin arm64.host v1 {} extern fn host(a:i32)->i32 fn main()->i32{return host(40)}")
        fixture.write_text('fn host(a){let s="AB";return a+load8(s)-63;}')
        compile_arm(seta, "--platform", fixture)
        result_is(arm, 42)
        passed("SetaScript platform imports and native string pointers")
        compile_arm(Path("examples/transforms/compose.flex"))
        result_is(arm, 42)
        passed("compile-time transformation runs in host VM")
        compile_arm(Path("examples/extensions/answer.postfix"), "--frontend", "examples/extensions/postfix.flex")
        result_is(arm, 42)
        passed("external FIR frontend")
        frontend = work / "source-frontend.flex"
        frontend.write_text('import "' + str(Path("compiler/source-sdk.flex").resolve()) + '";'
                            'fn frontend_compile(text,size,version,path){let s="Q";'
                            'if load8(s)!=81 {return 0;}return frontend_source(text,size);}')
        fixture.write_text('fn main(){let s="A";return load8(s)-23;}')
        compile_arm(fixture, "--frontend", frontend)
        result_is(arm, 42)
        passed("external source frontend: host VM strings and target code generation")

        for source, options, message in (
            ('fn main(){return ffi_open("libc.so");}', [], b"ARM64 dynamic FFI"),
            ('fn main(){return ffi_call(1,0,0,0,0,0,0);}', [], b"ARM64 dynamic FFI"),
            ("fn main(){return 0;}", ["--word-io", "buffered"], b"buffered word I/O"),
        ):
            fixture.write_text(source)
            arm.write_bytes(b"unchanged")
            result = run([compiler, "--target", "linux-arm64", *options, fixture, "-o", arm])
            assert result.returncode == 1 and message in result.stderr, result
            assert arm.read_bytes() == b"unchanged"
        passed("unsupported features fail without overwriting output")

        # Independent assembly caller checks ABI rules rather than trusting a
        # generated caller and callee that could share the same mistake.
        fixture.write_text("fn probe(a,b,c,d,e,f,g,h,i,j){return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j;}fn main(){return 0;}")
        compile_arm(fixture)
        elf = arm.read_bytes()
        assert elf[:7] == b"\x7fELF\x02\x01\x01" and struct.unpack_from("<H", elf, 18)[0] == 183
        phoff = struct.unpack_from("<Q", elf, 32)[0]
        segments = [struct.unpack_from("<IIQQQQQQ", elf, phoff + i * 56) for i in range(3)]
        assert [segment[0] for segment in segments] == [1, 1, 0x6474E551]
        assert [segment[1] for segment in segments] == [5, 6, 6]
        for segment in segments[:2]:
            assert segment[2] % 65536 == segment[3] % 65536 and segment[7] == 65536
            assert segment[2] + segment[5] <= len(elf)
        passed("ELF64 AArch64 headers, RX/RW separation and 64-KiB segment alignment")
        text = work / "generated.bin"
        text.write_bytes(elf[4096:segments[0][5]])
        assembly = work / "abi.s"
        assembly.write_text(f'''
.section .flex,"ax"
.incbin "{text}"
.text
.global _start
_start:
    mov x0,#1
    mov x1,#2
    mov x2,#3
    mov x3,#4
    mov x4,#5
    mov x5,#6
    mov x6,#7
    mov x7,#8
    sub sp,sp,#16
    mov x9,#9
    str x9,[sp]
    mov x9,#10
    str x9,[sp,#8]
    mov x18,#18
''' + "".join(f"    mov x{i},#{i}\n" for i in range(19, 30)) + '''
    ldr x16,=0x401018
    blr x16
    cmp x0,#385
    b.ne failed
''' + "".join(f"    cmp x{i},#{i}\n    b.ne failed\n" for i in range(18, 30)) + '''
    mov x9,sp
    tst x9,#15
    b.ne failed
    ldr x9,[sp]
    cmp x9,#9
    b.ne failed
    ldr x9,[sp,#8]
    cmp x9,#10
    b.ne failed
    add sp,sp,#16
    mov x0,#0
    b done
failed:
    mov x0,#1
done:
    mov x8,#93
    svc #0
''')
        linker = work / "abi.ld"
        linker.write_text("ENTRY(_start)\nSECTIONS { . = 0x401000; .flex : { *(.flex) } . = 0x500000; .text : { *(.text) } }\n")
        obj = work / "abi.o"
        oracle = work / "abi"
        ok(["clang", "--target=aarch64-linux-gnu", "-c", assembly, "-o", obj])
        ok(["ld.lld", "-T", linker, obj, "-o", oracle])
        result_is(oracle, 0)
        passed("LLVM assembly caller: register/stack arguments, preserved x18-x29, stack alignment")

        # Deterministic output and the alias must select exactly the same target.
        original = arm.read_bytes()
        ok([compiler, "--target", "aarch64", fixture, "-o", arm])
        assert arm.read_bytes() == original
        passed("deterministic output and aarch64 alias")

    report = {"compiler": str(compiler), "qemu": ok([args.qemu, "--version"]).stdout.decode().splitlines()[0],
              "checks": checks, "total": len(checks), "arithmetic_results": len(expressions),
              "execution": "QEMU Linux user emulation; no physical ARM64 or Android verification"}
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(checks)} checks passed; report: {args.report}")


if __name__ == "__main__":
    main()
