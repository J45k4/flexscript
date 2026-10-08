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
    core = args.build_dir / 'core'
    core_checksum = digest(core)
    assert core_checksum == report['core_sha256'] == report['clean_room']['compiler_sha256'] == report['clean_room']['rebuilt_sha256']
    assert len(report['tests']['results']) == 3
    assert all(result['checks'] >= 84 for result in report['tests']['results'])
    assert len(report['import_tests']['results']) == 2
    assert all(result['checks'] >= 46 for result in report['import_tests']['results'])
    assert len(report['upgrade_tests']['results']) == 2
    assert all(result['checks'] >= 88 for result in report['upgrade_tests']['results'])
    assert len(report['signature_tests']['results']) == 2
    assert all(result['checks'] >= 37 for result in report['signature_tests']['results'])
    for key, minimum in [('ffi_tests', 24), ('network_tests', 38), ('vm_tests', 335)]:
        assert len(report[key]['results']) == 2
        assert all(result['checks'] >= minimum for result in report[key]['results'])
    assert report['clean_room']['checks'] >= 10
    native_elf(binary)
    native_elf(core, standalone=True)
    assert subprocess.check_output([str(binary.resolve()), '--version']) == f'flexscript {VERSION}\n'.encode()
    summary = (ROOT / 'docs/releases' / f'{VERSION}.md').read_text().strip()
    args.dist_dir.mkdir(parents=True, exist_ok=True)
    artifact = args.dist_dir / f'flexscript-{VERSION}-linux-x86_64'
    shutil.copyfile(binary, artifact)
    artifact.chmod(0o755)
    core_artifact = args.dist_dir / f'flexscript-core-{VERSION}-linux-x86_64'
    shutil.copyfile(core, core_artifact)
    core_artifact.chmod(0o755)
    (args.dist_dir / 'SHA256SUMS').write_text(f'{checksum}  {artifact.name}\n{core_checksum}  {core_artifact.name}\n')
    notes = f'''{summary}

Verified build:

- Source commit: `{report['source_commit']}` (tag `{VERSION}`).
- Compiler version: `flexscript {VERSION}`.
- Bootstrap input: `{report['seed_version']}`; SHA-256 `{report['seed_sha256']}`.
- Native stage 1 -> stage 2 -> stage 3; stages 2 and 3 are byte-identical.
- {report['tests']['total']} core checks, {report['import_tests']['total']} import checks and {report['upgrade_tests']['total']} upgrade checks across the bootstrap stages.
- {report['signature_tests']['total']} Ed25519 and release-signing checks across the bootstrap stages.
- {report['ffi_tests']['total']} FFI checks and {report['network_tests']['total']} networking checks across the bootstrap stages.
- {report['vm_tests']['total']} interpreter, JIT and capability checks across the bootstrap stages.
- {report['clean_room']['checks']} checks of the static core in an empty filesystem with no toolchain or libc, including self-rebuild and nested imports.

The downloadable binary is the verified stage 2 compiler. Verify it with
`sha256sum -c SHA256SUMS`, then make it executable with `chmod +x {artifact.name}`.
It requires the Linux x86-64 glibc loader and libc. HTTPS upgrades additionally
require OpenSSL 3 (`libssl.so.3`, `libcrypto.so.3`) and a trusted CA certificate store. No curl is needed.
The release job signs the version-bound checksums as `SHA256SUMS.sig` using
Ed25519. The updater requires that signature and verifies it against its pinned
public key before downloading, executing or installing the candidate compiler.
See `docs/signing.md` for the signature format and manual verification.
The separate `flexscript-core` artifact is standalone and can build the full
compiler. Foreign calls and HTTPS upgrades are unavailable in the core itself.
The full compiler also provides `flex run [options] app.flex` with a restricted
interpreter and a baseline x86-64 JIT. The static core can use `run --interpret`.
See `docs/vm.md` for capabilities, resource limits and current JIT coverage.

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
