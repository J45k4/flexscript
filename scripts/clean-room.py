#!/usr/bin/env python3
"""Verify self-compilation in an empty root with no language toolchain or libc."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def isolated(compiler, source=None, output=None, args=()):
    command = [
        "bwrap", "--unshare-all", "--die-with-parent", "--clearenv",
        "--tmpfs", "/", "--dir", "/work", "--chdir", "/work",
        "--ro-bind", str(compiler.resolve()), "/compiler",
    ]
    if source is not None:
        command += ["--ro-bind", str(source.resolve()), "/source.flex"]
    if output is not None:
        command += ["--bind", str(output.parent.resolve()), "/work"]
    command += ["/compiler"]
    if source is not None:
        command += ["/source.flex", "-o", f"/work/{output.name}"]
    else:
        command += list(args)
    return subprocess.run(command, capture_output=True, timeout=30)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "build/clean")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if not shutil.which("bwrap"):
        raise SystemExit("bubblewrap is required for the clean-room verification")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    rebuilt = args.out_dir / "rebuilt"
    hello = args.out_dir / "hello"
    checks = [
        ((args.compiler, None, None, ("--version",)), b"flexscript 0.0.1\n"),
        ((args.compiler, ROOT / "compiler/main.flex", rebuilt), b""),
        ((rebuilt, None, None, ("--version",)), b"flexscript 0.0.1\n"),
        ((rebuilt, ROOT / "examples/hello.flex", hello), b""),
        ((hello,), b"Hello from native Flexscript!\n"),
    ]
    for command, expected in checks:
        result = isolated(*command)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert result.stdout == expected, (result.stdout, expected)
        assert result.stderr == b"", result.stderr
    assert rebuilt.read_bytes() == args.compiler.read_bytes(), "clean rebuild differs"
    report = {
        "compiler_sha256": digest(args.compiler),
        "rebuilt_sha256": digest(rebuilt),
        "checks": len(checks) + 1,
        "environment": "empty bubblewrap root, empty environment, no network, no Rust/Cargo/libc",
    }
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print("Clean room: self-rebuild, rebuilt compiler, and native sample passed; no toolchain or libc present.")


if __name__ == "__main__":
    main()
