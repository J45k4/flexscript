#!/usr/bin/env python3
"""Check native comparison branches against independently evaluated inputs."""
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

MASK = (1 << 64) - 1
OPS = {"==": (0x94, lambda a, b: a == b), "!=": (0x95, lambda a, b: a != b),
       "<": (0x9C, lambda a, b: a < b), ">": (0x9F, lambda a, b: a > b),
       "<=": (0x9E, lambda a, b: a <= b), ">=": (0x9D, lambda a, b: a >= b)}


def signed(n):
    n &= MASK
    return n - (1 << 64) if n >> 63 else n


def main():
    compiler = str(Path(os.environ.get("FLEX_COMPILER", "build/flex")).resolve())
    checks = 0
    with tempfile.TemporaryDirectory(prefix="flex-condition-branches-") as directory:
        work = Path(directory)
        source, binary = work / "test.flex", work / "test"

        def compile_text(text, mode=None):
            source.write_text(text)
            args = [compiler]
            if mode:
                args += ["--native-link", mode]
            subprocess.run(args + [str(source), "-o", str(binary)], check=True)
            return binary.read_bytes()

        # Small fixtures contain no data literals. Check actual instruction
        # encodings, including each signed condition and its inverse.
        for op, (cc, compare) in OPS.items():
            cmp_bytes = bytes.fromhex("4883f802")  # CMP RAX,2
            for negations in range(3):
                expr = "!" * negations + f"(argc {op} 2)"
                expected = bool(compare(1, 2)) ^ bool(negations & 1)
                for kind in ("if", "while"):
                    data = compile_text(f"fn main(argc,argv){{{kind} {expr} {{return 42;}}return 7;}}")
                    branch_cc = cc ^ (0 if negations & 1 else 1)
                    assert cmp_bytes + bytes([branch_cc - 0x20]) in data, (op, negations, kind)
                    assert bytes([0x0F, cc, 0xC0]) not in data, "branch-only comparison materialized a boolean"
                    assert subprocess.run([str(binary)], timeout=5).returncode == (42 if expected else 7)
                    checks += 1
            data = compile_text(f"fn main(argc,argv){{return argc {op} 2;}}")
            assert bytes([0x0F, cc, 0xC0, 0x0F, 0xB6, 0xC0]) in data
            assert subprocess.run([str(binary)], timeout=5).returncode == int(compare(1, 2))
            checks += 1

        definitions = ["global seen=0;", "fn left(x){seen=seen*10+1;return x;}",
                       "fn right(x){seen=seen*10+2;return x;}"]
        cases = []

        def case(body, evaluate):
            name = f"case{len(cases)}"
            definitions.append(f"fn {name}(a,b){{{body}}}")
            cases.append((name, evaluate))

        for op, (_, compare) in OPS.items():
            expr = f"a {op} b"
            case(f"return {expr};", lambda a, b, c=compare: int(c(a, b)))
            case(f"if {expr} {{return 1;}}return 0;", lambda a, b, c=compare: int(c(a, b)))
            case(f"if !({expr}) {{return 1;}}return 0;", lambda a, b, c=compare: int(not c(a, b)))
            case(f"if !!({expr}) {{return 1;}}return 0;", lambda a, b, c=compare: int(c(a, b)))
            case(f"seen=0;if left(a) {op} right(b) {{return seen+100;}}return seen;", lambda a, b, c=compare: 12 + 100 * c(a, b))
            case(f"if (a+1) {op} (b-1) {{return 1;}}return 0;", lambda a, b, c=compare: int(c(signed(a + 1), signed(b - 1))))
            case(f"let value={expr};return value*7+!value;", lambda a, b, c=compare: 7 if c(a, b) else 1)
            case(f"if -({expr}) {{return 1;}}return 0;", lambda a, b, c=compare: int(c(a, b)))
            for negate in (False, True):
                condition = f"!({expr})" if negate else expr
                case(f"let count=0;while {condition} {{count=count+1;a=b;if count>2 {{return 99;}}}}return count;",
                     lambda a, b, c=compare, n=negate: 0 if not (c(a, b) ^ n) else (99 if c(b, b) ^ n else 1))
            for value in (-2147483648, -129, -1, 0, 127, 2147483647, 2147483648, 4294967295, 1 << 62):
                case(f"if a {op} {value} {{return 1;}}return 0;", lambda a, b, c=compare, v=value: int(c(a, v)))

        logical = [
            ("(a<b) && (a>=b)", lambda a, b: (a < b) and (a >= b)),
            ("(a<b) || (a>=b)", lambda a, b: (a < b) or (a >= b)),
            ("!(a<b) && (a!=b)", lambda a, b: not (a < b) and (a != b)),
            ("!((a<b) || (a>b))", lambda a, b: not ((a < b) or (a > b))),
            ("((a<b) && b) || ((a>b) && a)", lambda a, b: ((a < b) and b) or ((a > b) and a)),
            ("(a==b) || ((a<b) && (b>0))", lambda a, b: (a == b) or ((a < b) and (b > 0))),
            ("((a<b) || b) && ((a>b) || a)", lambda a, b: ((a < b) or b) and ((a > b) or a)),
            ("!((a<b) && (b>0)) || (a==b)", lambda a, b: not ((a < b) and (b > 0)) or (a == b)),
        ]
        for expr, evaluate in logical:
            case(f"return {expr};", lambda a, b, e=evaluate: int(bool(e(a, b))))
            case(f"if {expr} {{return 1;}}return 0;", lambda a, b, e=evaluate: int(bool(e(a, b))))
            case(f"let value={expr};return value*7+!value;", lambda a, b, e=evaluate: 7 if e(a, b) else 1)
        # A skipped logical operand must preserve 0/1 and must not execute its
        # calls. Mixed comparison directions deliberately leave different flags.
        case("seen=0;let v=(a<b) && left(1);return seen*10+v;", lambda a, b: 11 if a < b else 0)
        case("seen=0;let v=(a>b) || right(0);return seen*10+v;", lambda a, b: 1 if a > b else 20)
        case("seen=0;if ((a<b) && left(1)) || ((a>=b) && right(1)) {return seen;}return 99;", lambda a, b: 1 if a < b else 2)

        size = len(cases) * 8
        definitions.append(f"fn main(argc,argv){{let fd=syscall(2,load64(argv+8),0,0,0,0,0);let input=alloc(16);let out=alloc({size});let n=syscall(0,fd,input,16,0,0,0);while n==16 {{let a=load64(input);let b=load64(input+8);")
        definitions.extend(f"store64(out+{i*8},{name}(a,b));" for i, (name, _) in enumerate(cases))
        definitions.append(f"if syscall(1,1,out,{size},0,0,0)!={size} {{return 9;}}n=syscall(0,fd,input,16,0,0,0);}}return 0;}}")
        rng = random.Random(8136)
        values = [-(1 << 63), -(1 << 32), -2147483649, -2147483648, -129, -1, 0, 1, 127,
                  2147483647, 2147483648, 4294967295, 1 << 62, (1 << 63) - 1]
        pairs = [(a, b) for a in values for b in values]
        pairs += [(signed(rng.getrandbits(64)), signed(rng.getrandbits(64))) for _ in range(2048)]
        input_path = work / "input"
        input_path.write_bytes(b"".join(struct.pack("<QQ", a & MASK, b & MASK) for a, b in pairs))
        expected = [evaluate(a, b) for a, b in pairs for _, evaluate in cases]
        for mode in (None, "all"):
            compile_text("\n".join(definitions), mode)
            output = subprocess.check_output([str(binary), str(input_path)], timeout=30)
            actual = [n for (n,) in struct.iter_unpack("<Q", output)]
            assert len(actual) == len(expected)
            for i, (got, want) in enumerate(zip(actual, expected)):
                assert got == want, (mode, i, pairs[i // len(cases)], cases[i % len(cases)][0], got, want)
            checks += len(actual)
    print(f"Condition branches: {checks:,} encoding, signed comparison, value, loop, short-circuit and side-effect checks pass")


if __name__ == "__main__":
    main()
