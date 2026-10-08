#!/usr/bin/env python3
"""Package a verified stage-2 binary from the exact clean committed source tree."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from bootstrap import ROOT, VERSION, digest, git, native_elf, source_manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    parser.add_argument('--dist-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    report = json.loads((args.build_dir / 'bootstrap-report.json').read_text())
    assert re.fullmatch(r'\d+\.\d+\.\d+', VERSION), 'invalid release version'
    assert report['version'] == VERSION, 'build version differs'
    assert not git('status', '--porcelain'), 'commit the source tree before packaging'
    assert report['source_clean'], 'rerun bootstrap from the clean committed tree'
    assert report['source_commit'] == git('rev-parse', 'HEAD'), 'build commit differs'
    assert report['source_manifest'] == source_manifest(), 'source files differ from build'
    binary = args.build_dir / 'stage2'
    checksum = digest(binary)
    assert checksum == report['stages']['stage2'] == report['stages']['stage3']
    assert checksum == report['clean_room']['compiler_sha256'] == report['clean_room']['rebuilt_sha256']
    assert len(report['tests']['results']) == 3
    assert all(result['checks'] >= 84 for result in report['tests']['results'])
    assert len(report['import_tests']['results']) == 2
    assert all(result['checks'] >= 46 for result in report['import_tests']['results'])
    assert report['clean_room']['checks'] >= 8
    native_elf(binary)
    assert subprocess.check_output([str(binary.resolve()), '--version']) == f'flexscript {VERSION}\n'.encode()
    summary = (ROOT / 'docs/releases' / f'{VERSION}.md').read_text().strip()
    args.dist_dir.mkdir(parents=True, exist_ok=True)
    artifact = args.dist_dir / f'flexscript-{VERSION}-linux-x86_64'
    shutil.copyfile(binary, artifact)
    artifact.chmod(0o755)
    (args.dist_dir / 'SHA256SUMS').write_text(f'{checksum}  {artifact.name}\n')
    notes = f'''{summary}

Verified build:

- Source commit: `{report['source_commit']}` (tag `{VERSION}`).
- Compiler version: `flexscript {VERSION}`.
- Bootstrap input: `{report['seed_version']}`; SHA-256 `{report['seed_sha256']}`.
- Native stage 1 -> stage 2 -> stage 3; stages 2 and 3 are byte-identical.
- {report['tests']['total']} core checks and {report['import_tests']['total']} import checks across the bootstrap stages.
- {report['clean_room']['checks']} checks in an empty filesystem with no toolchain or libc, including self-rebuild and nested imports.

The downloadable binary is the verified stage 2 compiler. Verify it with
`sha256sum -c SHA256SUMS`, then make it executable with `chmod +x {artifact.name}`.

```sh
./{artifact.name} --version
./{artifact.name} examples/imports/main.flex -o imported-hello
./imported-hello
```

Reproduce without Rust using the published bootstrap binary:

```sh
python3 scripts/bootstrap.py --compiler /path/to/flexscript-0.0.1-linux-x86_64
```

Compiler SHA-256: `{checksum}`
'''
    (args.dist_dir / 'release-notes.md').write_text(notes)
    print(f'Packaged {artifact.name}: {checksum}')


if __name__ == '__main__':
    main()
