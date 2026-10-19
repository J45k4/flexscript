#!/usr/bin/env python3
"""Differential shared-IR checks with independent word results and real backends."""
import ctypes
import json
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
MASK = (1 << 64) - 1


def signed(n):
    n &= MASK
    return n - (1 << 64) if n >> 63 else n


def main():
    compiler = str(Path(os.environ.get("FLEX_COMPILER", ROOT / "build/flex")).resolve())
    checks = 0
    sizes = {}
    with tempfile.TemporaryDirectory(prefix="flex-ir-opt-") as directory:
        work = Path(directory)

        def compile_file(source, output, mode, target=None, extra=()):
            args = [compiler, "--ir-opt", mode]
            if target:
                args += ["--target", target]
            subprocess.run(args + list(extra) + [str(source), "-o", str(output)], check=True)
            return output.read_bytes()

        def run_vm(source, mode, expected=42, extra=(), stdout=b""):
            nonlocal checks
            results = []
            for engine in ("--interpret", "--jit"):
                p = subprocess.run([compiler, "run", engine, "--restricted", "--stats",
                                    f"--ir-opt={mode}", *extra, str(source)], capture_output=True, timeout=30)
                assert p.returncode == expected, (source, mode, engine, p.returncode, p.stderr)
                assert p.stdout == stdout, (source, mode, engine, len(p.stdout), len(stdout), p.stdout[:32], stdout[:32])
                stats = re.search(rb"IR instructions: (\d+) -> (\d+)", p.stderr)
                assert stats, p.stderr
                results.append(tuple(map(int, stats.groups())))
                if expected == 70:
                    assert b"integer division trap" in p.stderr, p.stderr
                checks += 1
            assert results[0] == results[1], "interpreter/JIT optimize different IR"
            return results[0]

        def wasm_run(module, expected=42, calls=None):
            nonlocal checks
            request = work / "request.json"
            value = {"module": str(module)}
            if calls is not None:
                value["calls"] = calls
            request.write_text(json.dumps(value))
            result = json.loads(subprocess.check_output(["bun", str(ROOT / "scripts/wasm-runner.js"), str(request)], timeout=30))
            assert result.get("valid"), result
            if expected == "trap":
                assert result.get("trap"), result
            else:
                assert not result.get("error"), result
                if calls is None:
                    assert int(result["result"]) == expected, result
            checks += 1
            return result

        source = work / "test.flex"
        rng = random.Random(5362)
        pairs = [(-(1 << 63), -1), ((1 << 63) - 1, 1), (0, 0), (-1, 1)]
        pairs += [(signed(rng.getrandbits(64)), signed(rng.getrandbits(64))) for _ in range(256)]
        definitions = ['global seen=0;fn mark(n){seen=seen+n;return n;}',
                       'fn compute(a,b){let c=(3+5)*(9-2);if 0 {mark(999);}if a<b {return (a+b)^c;}else{return (a-b)^c;}}',
                       'fn main(){if 1 {mark(2);}else{mark(99);}while 0 {mark(999);}if 0 && mark(77){return 1;}if !(1 || mark(88)){return 2;}let n=0;while n<4 {mark(1);n=n+1;}if seen!=6{return 3;}']
        expected = [signed((signed(a + b) if a < b else signed(a - b)) ^ 56) for a, b in pairs]
        definitions += [f'if compute(0x{a & MASK:x},0x{b & MASK:x})!=0x{v & MASK:x} {{return 9;}}'
                        for (a, b), v in zip(pairs, expected)]
        definitions.append('return 42;}')
        source.write_text('\n'.join(definitions))
        native = []
        for mode in ("none", "basic"):
            before, after = run_vm(source, mode)
            assert after < before if mode == "basic" else after == before
            native.append(compile_file(source, work / f"native-{mode}", mode))
            assert subprocess.run([str(work / f"native-{mode}")]).returncode == 42
            module = work / f"test-{mode}.wasm"
            compile_file(source, module, mode, "wasm32")
            sizes[mode] = module.stat().st_size
            wasm_run(module)
            calls = [{"name": "compute", "args": [str(a), str(b)]} for a, b in pairs]
            got = list(map(int, wasm_run(module, calls=calls)["values"]))
            assert got == expected
            checks += len(got)
        assert len(native[1]) < len(native[0]), "default native source compilation bypassed shared optimization"
        direct = [compile_file(source, work / f"direct-{mode}", mode, extra=("--native-pipeline", "direct")) for mode in ("none", "basic")]
        assert direct[0] == direct[1], "IR mode unexpectedly changes the direct reference emitter"
        assert sizes["basic"] < sizes["none"], sizes

        # Both faults must remain faults, with effects preceding them intact.
        for expr in ("7/0", "0x8000000000000000/(-1)", "7%0", "0x8000000000000000%(-1)"):
            source.write_text(f'fn main(){{syscall(1,1,"before",6,0,0,0);return {expr};}}')
            for mode in ("none", "basic"):
                run_vm(source, mode, 70, stdout=b"before")
                module = work / "trap.wasm"
                compile_file(source, module, mode, "wasm32")
                wasm_run(module, "trap")

        # Exercise every foldable word operation against Python arithmetic,
        # including signed extremes, wrapping and masked shift distances.
        values = [-(1 << 63), -2147483649, -129, -1, 0, 1, 127, 2147483648, (1 << 63) - 1]
        operators = ["+", "-", "*", "&", "|", "^", "<<", ">>", "==", "!=", "<", ">", "<=", ">=", "/", "%"]
        expressions, words = [], []
        for a in values:
            for b in values:
                for op in operators:
                    if op in ("/", "%"):
                        if not b or (a == -(1 << 63) and b == -1):
                            continue
                        q = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
                        result = q if op == "/" else a - q * b
                    elif op == "<<":
                        result = a << (b & 63)
                    elif op == ">>":
                        result = a >> (b & 63)
                    else:
                        result = int(eval(f"a {op} b", {}, {"a": a, "b": b}))
                    expressions.append(f"store64(p+{len(words)*8},(0x{a & MASK:x}) {op} (0x{b & MASK:x}));")
                    words.append(result & MASK)
        raw = b"".join(struct.pack("<Q", n) for n in words)
        source.write_text(f"fn main(){{let p=alloc({len(raw)});" + "".join(expressions) + f"let sent=0;while sent<{len(raw)} {{let n=syscall(1,1,p+sent,{len(raw)}-sent,0,0,0);if n<=0{{return 9;}}sent=sent+n;}}return 42;}}")
        for mode in ("none", "basic"):
            run_vm(source, mode, stdout=raw)
            module = work / f"words-{mode}.wasm"
            compile_file(source, module, mode, "wasm32")
            result = wasm_run(module)
            assert result["stdoutHex"] == raw.hex()
            checks += len(words) * 3

        # Hand-built, validated FIR branches into a unary operation. Its
        # preceding physical constant is unreachable on that edge and must
        # never be folded together with the target instruction.
        for initial, jump, expected_result in ((7, 10, -7), (0, 11, 0), (7, 11, -3)):
            instructions = [(18, 0), (1, 0), (1, initial), (jump, 80), (1, 3), (14, 0), (9, 0)]
            code = b"".join(struct.pack("<QQ", op, arg) for op, arg in instructions)
            artifact = work / "incoming.fir"
            artifact.write_bytes(struct.pack("<8Q", 0x31524946, 128 + len(code) + 4, 1, 128, len(code), 128 + len(code), 4, 0)
                                 + struct.pack("<8Q", 0, 4, 0, 0, 0, 0, 0, 0) + code + b"main")
            for mode in ("none", "basic"):
                run_vm(artifact, mode, expected_result & 255, extra=("--language", "ir"))
                module = work / f"incoming-{mode}.wasm"
                compile_file(artifact, module, mode, "wasm32", ("--language", "ir"))
                wasm_run(module, expected_result)

        # Basic-block joins may enter the middle of the physical instruction
        # stream. The forward labels protect loads from constant folding.
        seta = work / "test.seta"
        seta.write_text('plugin opt v1 {} fn main()->i32{let x:i32=0 if x==0 {x=6} else{x=99} if x<7 {x=x*(2+5)} return x}')
        artifacts = []
        for mode in ("none", "basic"):
            artifact = work / f"test-{mode}.fir"
            artifacts.append(compile_file(seta, artifact, mode, "ir"))
            run_vm(seta, mode)
            run_vm(artifact, mode, extra=("--language", "ir"))
            app = work / f"seta-{mode}"
            compile_file(artifact, app, mode, extra=("--language", "ir"))
            assert subprocess.run([str(app)]).returncode == 42
            checks += 1
        assert artifacts[0] == artifacts[1], "serialized FIR compatibility changed"

        platform = work / "platform.flex"
        platform.write_text('fn platform(x){if 0 {return 99;}return x*(2+6);}')
        seta.write_text('plugin opt v1 {} extern fn platform(x:i32)->i32 fn main()->i32{return platform(2+3)+2}')
        for mode in ("none", "basic"):
            run_vm(seta, mode, extra=("--platform", str(platform)))
            app = work / f"platform-{mode}"
            compile_file(seta, app, mode, extra=("--platform", str(platform)))
            assert subprocess.run([str(app)]).returncode == 42
            module = work / f"platform-{mode}.wasm"
            compile_file(seta, module, mode, "wasm32", ("--platform", str(platform)))
            wasm_run(module)

        source.write_text('fn kernel(i,input,output,count){let x=(2+3)*(8-1);if 0{store64(output+i*8,99);}if i<count{store64(output+i*8,load64(input+i*8)+x);}return 0;}')
        for target in ("ptx", "sass-sm75", "hip", "rdna-gfx1201", "cpu-cxx"):
            for mode in ("none", "basic"):
                artifact = work / f"kernel-{target}-{mode}"
                data = compile_file(source, artifact, mode, target)
                assert data
                checks += 1
                if target == "cpu-cxx":
                    lib = work / f"kernel-{mode}.so"
                    subprocess.run(["g++", "-x", "c++", "-std=c++17", "-O2", "-shared", "-fPIC", str(artifact), "-o", str(lib)], check=True)
                    kernel = ctypes.CDLL(str(lib)).flex_kernel
                    kernel.argtypes = [ctypes.c_uint64] * 4
                    kernel.restype = ctypes.c_uint64
                    inputs = (ctypes.c_uint64 * 257)(*(rng.getrandbits(64) for _ in range(257)))
                    output = (ctypes.c_uint64 * 257)()
                    for i in range(257):
                        kernel(i, ctypes.addressof(inputs), ctypes.addressof(output), 257)
                        assert output[i] == (inputs[i] + 35) & MASK
                        checks += 1
        # Invalid code is still resolved before dead-code removal.
        source.write_text('fn unused(){return missing();}fn main(){if 0{return unused();}return 42;}')
        for mode in ("none", "basic"):
            p = subprocess.run([compiler, "--target", "wasm32", "--ir-opt", mode, str(source), "-o", str(work / "bad")], capture_output=True)
            assert p.returncode == 1 and b"undefined function" in p.stderr
            checks += 1
        p = subprocess.run([compiler, "run", "--ir-opt=bad", str(source)], capture_output=True)
        assert p.returncode == 1 and b"expected basic or none" in p.stderr
        checks += 1
    print(f"Shared IR: {checks:,} differential/oracle checks pass; VM/JIT, Wasm, FIR/native, platform links and CPU kernels execute; PTX/SASS/HIP/RDNA compile")
    print(f"Wasm fixture: {sizes['none']:,} -> {sizes['basic']:,} bytes")


if __name__ == "__main__":
    main()
