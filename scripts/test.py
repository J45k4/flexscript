#!/usr/bin/env python3
"""Run behavioral, diagnostic, limit, and file-handling tests against compilers."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = json.loads((ROOT / "tests/cases.json").read_text())
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(command):
    return subprocess.run(
        [str(arg) for arg in command], capture_output=True, timeout=30
    )


def check(result, status=0, stdout=None):
    assert result.returncode == status, (
        f"status {result.returncode}, expected {status}; stderr={result.stderr!r}"
    )
    if stdout is not None:
        assert result.stdout == stdout.encode(), (result.stdout, stdout)


def rejected(compiler, source, destination, message):
    before = source.read_bytes()
    result = run([compiler, source, "-o", destination])
    assert result.returncode == 1, result
    assert message.encode() in result.stderr, result.stderr
    assert re.search(rb":\d+:\d+: error: ", result.stderr), result.stderr
    assert source.read_bytes() == before, "compiler changed source on rejection"
    assert not destination.exists(), "invalid source produced an output file"


def suite(compiler):
    count = 0
    version = run([compiler, "--version"])
    check(version)
    current = (ROOT / "VERSION").read_text().strip()
    assert version.stdout in (b"flexscript 0.0.1\n", f"flexscript {current}\n".encode()), version.stdout
    help_result = run([compiler, "--help"])
    check(help_result)
    legacy_help = b"Usage: flexscript <source.flex> -o <binary>\n"
    upgrade_help=legacy_help+b"       flex upgrade [--check]\n"
    assert help_result.stdout in (legacy_help,upgrade_help,upgrade_help+b"       flex run [options] <source.flex> [args...]\n"), help_result.stdout
    check(run([compiler]), status=1)
    count += 3
    with tempfile.TemporaryDirectory(prefix="flexscript-tests-") as directory:
        work = Path(directory)
        for case in CASES["valid"]:
            binary = work / "program"
            source = ROOT / "tests" / case["source"]
            result = run([compiler, source, "-o", binary])
            check(result)
            assert result.stderr == b"", result.stderr
            assert os.access(binary, os.X_OK)
            assert binary.read_bytes()[:4] == b"\x7fELF"
            args = [arg.replace("{work}", str(work)) for arg in case["args"]]
            check(run([binary, *args]), status=case["exit"], stdout=case["stdout"])
            if "file_content" in case:
                assert (work / "file.txt").read_text() == case["file_content"]
            count += 1
        for case in CASES["invalid"]:
            rejected(
                compiler, ROOT / "tests" / case["source"],
                work / "invalid", case["error"]
            )
            count += 1

        source = work / "limit.flex"
        limits = [
            ("fn main(){return " + "(" * 130 + "1" + ")" * 130 + ";}", "expression nesting"),
            ("fn main(){" + "{" * 130 + "return 0;" + "}" * 130 + "}", "block nesting"),
            ("fn main(){" + "if 0 {} else " * 130 + "{} return 0;}", "conditional nesting"),
            ("global x0=0;" + "".join(f"global x{i}=0;" for i in range(1, 2049)) + "fn main(){return 0;}", "too many globals"),
            ("fn main(){" + "".join(f"let x{i}=0;" for i in range(4097)) + "return 0;}", "too many locals"),
            ("fn main(){return 0;}" + "".join(f"fn f{i}(){{}}" for i in range(2048)), "too many functions"),
            ("fn main(){" + "f();" * 65537 + "} fn f(){}", "too many calls"),
            (" " * 16777216, "source must be smaller"),
        ]
        for text, message in limits:
            source.write_text(text)
            rejected(compiler, source, work / "invalid", message)
            count += 1

        # Output-size limit reached before the source-size limit.
        source.write_text("fn main(){" + "1;" * 6711000 + "}")
        rejected(compiler, source, work / "invalid", "output exceeds")
        count += 1

        source.write_text("fn main(){return 42;}\n")
        original = source.read_bytes()
        result = run([compiler, source, "-o", source])
        check(result, status=1)
        assert source.read_bytes() == original
        count += 1
        for alias, create in [
            (work / "hardlink", lambda p: os.link(source, p)),
            (work / "symlink", lambda p: p.symlink_to(source)),
        ]:
            create(alias)
            check(run([compiler, source, "-o", alias]), status=1)
            assert source.read_bytes() == original
            count += 1
        check(run([compiler, source, "-o", work / "missing-dir/out"]), status=1)
        check(run([compiler, work / "absent.flex", "-o", work / "absent"]), status=1)
        check(run([compiler, work, "-o", work / "directory"]), status=1)
        check(run([compiler, source, "--bad", work / "bad"]), status=1)
        count += 4

        # Invalid compilation preserves an already-existing destination too.
        existing = work / "existing"
        existing.write_bytes(b"keep me")
        invalid = ROOT / "tests/invalid/undefined-variable.flex"
        check(run([compiler, invalid, "-o", existing]), status=1)
        assert existing.read_bytes() == b"keep me"
        # Valid compilation truncates the old file and restores executable mode.
        existing.write_bytes(b"old" * 10000)
        existing.chmod(0o600)
        check(run([compiler, source, "-o", existing]))
        check(run([existing]), status=42)
        assert existing.stat().st_size < 1000
        count += 2

        source.write_text("fn main() {\n  // diagnostic location\n  return @;\n}\n")
        result = run([compiler, source, "-o", work / "location"])
        check(result, status=1)
        assert b":3:10: error: unexpected source byte" in result.stderr, result.stderr
        count += 1
        for expression in ("1/0", "0x8000000000000000 / -1"):
            source.write_text(f"fn main() {{ return {expression}; }}")
            binary = work / "trap"
            check(run([compiler, source, "-o", binary]))
            check(run([binary]), status=-8)  # Linux SIGFPE, as specified.
            count += 1
    print(f"{compiler.name}: {count} checks passed", flush=True)
    return count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compilers", nargs="+", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    total = 0
    results = []
    for compiler in args.compilers:
        try:
            count = suite(compiler.resolve())
            total += count
            results.append({"compiler": compiler.name, "checks": count})
        except Exception as error:
            raise AssertionError(f"{compiler}: {error}") from error
    print(f"Total: {total} checks passed")
    if args.report:
        args.report.write_text(json.dumps({"results": results, "total": total}, indent=2) + "\n")


if __name__ == "__main__":
    main()
