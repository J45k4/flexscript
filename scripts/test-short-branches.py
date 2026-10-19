#!/usr/bin/env python3
"""Independent x86 branch encoding boundaries and native execution checks."""
import os
from pathlib import Path
import struct
import subprocess
import tempfile


def main():
    compiler = str(Path(os.environ.get("FLEX_COMPILER", "build/flex")).resolve())
    checks = 0
    with tempfile.TemporaryDirectory(prefix="flex-short-branches-") as work:
        source = Path(work) / "test.flex"
        binary = Path(work) / "test"

        def compile_run(text, expected=42, mode=None):
            nonlocal checks
            source.write_text(text)
            # Keep constant control-flow fixtures intact while measuring exact
            # native branch-distance boundaries in the IR-based pipeline.
            args = [compiler, "--ir-opt", "none"]
            if mode:
                args += ["--native-link", mode]
            subprocess.run(args + [str(source), "-o", str(binary)], check=True)
            result = subprocess.run([str(binary)], timeout=10, capture_output=True)
            assert result.returncode == expected, (text[:200], result)
            data = binary.read_bytes()
            # Locate the startup call by its argv setup, within the ELF entry
            # stub. Never scan strings/asset payloads for instruction patterns.
            entry = struct.unpack_from("<Q", data, 24)[0]
            ph = struct.unpack_from("<Q", data, 32)[0]
            base = struct.unpack_from("<Q", data, ph + 16)[0]
            offset = struct.unpack_from("<Q", data, ph + 8)[0] + entry - base
            stub = data[offset:offset + 96]
            at = stub.index(bytes.fromhex("488d44241050e8")) + offset + 6
            start = at + 5 + struct.unpack_from("<i", data, at + 1)[0]
            checks += 1
            return data[start:]

        def branch(code, at, conditional, distance):
            nonlocal checks
            short = -128 <= distance <= 127
            opcode = 0x74 if conditional else 0xEB
            if short:
                assert code[at] == opcode, (at, distance, code[at:at + 8].hex())
                actual = struct.unpack_from("<b", code, at + 1)[0]
            else:
                prefix = b"\x0f\x84" if conditional else b"\xe9"
                assert code[at:at + len(prefix)] == prefix
                actual = struct.unpack_from("<i", code, at + len(prefix))[0]
            assert actual == distance, (distance, actual)
            checks += 1

        for mode in (None, "all"):
            # The outer branch only fits after the inner string jump shrinks:
            # these also exercise relaxation through more than one iteration.
            for n in (0, 1, 116, 117, 118, 119, 200, 1000):
                payload = "x" * n
                body_size = n + (10 if n + 1 <= 127 else 13)
                for condition in (0, 1):
                    code = compile_run(f'fn main(){{if {condition} {{"{payload}";}}return 42;}}', mode=mode)
                    branch(code, 12, True, body_size)
                code = compile_run(f'fn main(){{if 1 {{1;}}else{{"{payload}";}}return 42;}}', mode=mode)
                branch(code, 19, False, body_size)
            # Literal data has its own jump; 127/128 bytes must choose exactly
            # the right encoding without interpreting those bytes as code.
            for n in (125, 126, 127, 128, 256):
                code = compile_run('fn main(){"' + "x" * n + '";return 42;}', mode=mode)
                branch(code, 4, False, n + 1)
            for n in (98, 99, 100, 101):
                code = compile_run('fn main(){while 1 {"' + "x" * n + '";return 42;}}', mode=mode)
                # Back edge is followed only by the seven-byte implicit return.
                short = n <= 99
                at = len(code) - 7 - (2 if short else 5)
                branch(code, at, False, -(n + (29 if short else 32)))
            for n in (0, 20, 100, 200, 1000):
                compile_run('global value=0;fn step(){value=value+1;return value;}fn main(){let n=0;while n<6 {"' + "x" * n + '";n=n+1;if n==2 {step();}else{value=value+n;}if n==5 || n==6 {value=value+1;}}return value+20;}', expected=42, mode=mode)
            compile_run('global count=0;fn bump(){count=count+1;return 1;}fn main(){if (0 && bump()) || (1 && bump()) {if count!=1{return 9;}}if 1 || bump() {return count+41;}return 8;}', mode=mode)
        # Exceeding the planning budget retains valid long branches rather
        # than imposing a new source-language limit or emitting partial plans.
        code = compile_run('fn main(){' + 'if 0 {}' * 131073 + 'return 42;}')
        assert code[12:14] == b"\x0f\x84", "oversized branch plan must fall back to long encodings"
        checks += 1
    print(f"Short branches: {checks} encoding, execution, boundary and fallback checks pass")


if __name__ == "__main__":
    main()
