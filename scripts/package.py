#!/usr/bin/env python3
"""Package a verified stage-2 binary from the exact clean committed source tree."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from bootstrap import ROOT, digest, git, native_elf, source_manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build")
    parser.add_argument("--dist-dir", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    report = json.loads((args.build_dir / "bootstrap-report.json").read_text())
    assert not git("status", "--porcelain"), "commit the source tree before packaging"
    assert report["source_clean"], "rerun bootstrap from the clean committed tree"
    assert report["source_commit"] == git("rev-parse", "HEAD"), "build commit differs"
    assert report["source_manifest"] == source_manifest(), "source files differ from build"
    binary = args.build_dir / "stage2"
    checksum = digest(binary)
    assert checksum == report["stages"]["stage2"] == report["stages"]["stage3"]
    assert checksum == report["clean_room"]["compiler_sha256"] == report["clean_room"]["rebuilt_sha256"]
    assert len(report["tests"]["results"]) == 3
    assert all(result["checks"] >= 84 for result in report["tests"]["results"])
    native_elf(binary)
    assert subprocess.check_output([str(binary.resolve()), "--version"]) == b"flexscript 0.0.1\n"
    args.dist_dir.mkdir(parents=True, exist_ok=True)
    artifact = args.dist_dir / "flexscript-0.0.1-linux-x86_64"
    shutil.copyfile(binary, artifact)
    artifact.chmod(0o755)
    (args.dist_dir / "SHA256SUMS").write_text(f"{checksum}  {artifact.name}\n")
    notes = f"""Flexscript 0.0.1 is the first native bootstrap compiler built from Flexscript source.

- Target: Linux x86-64.
- Source commit: `{report['source_commit']}` (tag `0.0.1`).
- Compiler version: `flexscript 0.0.1`.
- Native x86-64 machine code and ELF output; no runtime Rust, Cargo, libc, assembler, or linker dependency.
- Rust seed -> native stage 1 -> native stage 2 -> native stage 3.
- Stage 2 and stage 3 are byte-identical.
- {report['tests']['total']} behavioral, diagnostic, limit, and file-handling checks passed across the Rust seed, stage 1, and stage 2.
- An empty-filesystem clean-room test rebuilt the compiler, compiled the sample using that rebuilt compiler, and ran the sample with no toolchain or libc installed.

The downloadable binary is the verified stage 2 compiler. Verify it with `sha256sum -c SHA256SUMS`, then make it executable with `chmod +x {artifact.name}`.

```sh
./{artifact.name} --version
./{artifact.name} compiler/main.flex -o flexscript
./flexscript examples/hello.flex -o hello
./hello
```

To reproduce the initial Rust bootstrap from the tagged source:

```sh
python3 scripts/bootstrap.py
```

To bootstrap without Rust using the downloaded release binary:

```sh
python3 scripts/bootstrap.py --compiler /path/to/{artifact.name}
```

Specification and limitations: `docs/language-0.0.1.md`. Build and next-version instructions: `docs/bootstrap-0.0.1.md`. This initial core uses 64-bit words, manual memory management, a single source file, and a Linux x86-64 backend with a read/write/execute ELF segment.

SHA-256: `{checksum}`
"""
    (args.dist_dir / "release-notes.md").write_text(notes)
    print(f"Packaged {artifact.name}: {checksum}")


if __name__ == "__main__":
    main()
