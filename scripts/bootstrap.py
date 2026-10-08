#!/usr/bin/env python3
"""Build and verify the native bootstrap. --compiler skips Rust entirely."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "VERSION").read_text().strip()


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, timeout=180)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_manifest():
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).split(b"\0")
    return {
        name.decode(): digest(ROOT / name.decode())
        for name in sorted(set(names)) if name
    }


def native_elf(path):
    binary = path.read_bytes()
    assert binary[:7] == b"\x7fELF\x02\x01\x01"
    assert struct.unpack_from("<H", binary, 18)[0] == 62
    phoff = struct.unpack_from("<Q", binary, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", binary, 54)
    types = [struct.unpack_from("<I", binary, phoff + i * phsize)[0] for i in range(phcount)]
    assert types == [1], "expected a native LOAD segment without INTERP or DYNAMIC"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, help="existing native bootstrap binary; do not use Rust")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "build")
    args = parser.parse_args()
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source_commit = git("rev-parse", "HEAD")
    source_clean = not git("status", "--porcelain")
    manifest = source_manifest()
    if args.compiler:
        seed = args.compiler.resolve()
    else:
        run("cargo", "build", "--manifest-path", ROOT / "bootstrap/Cargo.toml",
            "--release", "--locked", "--offline")
        seed = ROOT / "bootstrap/target/release/flexscript-seed"
    stages = [out / f"stage{i}" for i in range(1, 4)]
    compiler = seed
    for binary in stages:
        run(compiler, ROOT / "compiler/main.flex", "-o", binary)
        native_elf(binary)
        assert subprocess.check_output([str(binary), "--version"]) == f"flexscript {VERSION}\n".encode()
        compiler = binary
    assert stages[1].read_bytes() == stages[2].read_bytes(), "stages 2 and 3 differ"
    run(sys.executable, ROOT / "scripts/test.py", seed, *stages[:2], "--report", out / "tests.json")
    # The frozen seed and published 0.0.1 binary build the extended compiler,
    # but only the newly built compilers implement imports.
    run(sys.executable, ROOT / "scripts/test-imports.py", *stages[:2],
        "--report", out / "import-tests.json")
    run(sys.executable, ROOT / "scripts/clean-room.py", stages[1],
        "--out-dir", out / "clean", "--report", out / "clean-room.json")
    report = {
        "version": VERSION,
        "seed_version": subprocess.check_output([str(seed), "--version"]).decode().strip(),
        "seed_sha256": digest(seed),
        "target": "linux-x86_64",
        "source_commit": source_commit,
        "source_clean": source_clean,
        "source_manifest": manifest,
        "compiler_source_sha256": digest(ROOT / "compiler/main.flex"),
        "stages": {p.name: digest(p) for p in stages},
        "tests": json.loads((out / "tests.json").read_text()),
        "import_tests": json.loads((out / "import-tests.json").read_text()),
        "clean_room": json.loads((out / "clean-room.json").read_text()),
    }
    assert git("rev-parse", "HEAD") == source_commit, "source commit changed during build"
    assert source_manifest() == manifest, "source files changed during build"
    assert bool(git("status", "--porcelain")) == (not source_clean), "source status changed during build"
    (out / "bootstrap-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Bootstrap passed: {report['stages']['stage2']}")


if __name__ == "__main__":
    main()
