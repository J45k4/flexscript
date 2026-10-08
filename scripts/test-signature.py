#!/usr/bin/env python3
"""Check native Ed25519 verification against RFC 8032 and release signing policy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()

# RFC 8032 section 7.1, tests 1, 2 and 3. No test signing implementation is used
# to generate these signatures: https://www.rfc-editor.org/rfc/rfc8032#section-7.1
VECTORS = [
    ('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', '',
     'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
     '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
    ('3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', '72',
     '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
     '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'),
    ('fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025', 'af82',
     '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac'
     '18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a'),
]


def run(*args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=30, env=env)


def success(result):
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flexscript-signature-test-') as temporary:
        work = Path(temporary)
        source = work / 'verify.flex'
        source.write_text((ROOT / 'lib/signature.flex').read_text() + '''
fn main(argc,argv) {
    let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0 {return 2;}
    let data=alloc(4096);let size=syscall(0,fd,data,4096,0,0,0);
    syscall(3,fd,0,0,0,0,0);if size<120 {return 2;}
    let valid=ed25519_verify(data+24,load64(data),data+56,load64(data+8),data+120,load64(data+16));
    if valid {return 0;}return 1;
}
''')
        harness = work / 'verify'
        success(run(compiler, source, '-o', harness))

        def verify(key, signature, message, valid, key_size=32, sig_size=64):
            nonlocal count
            packet = work / 'packet'
            packet.write_bytes(struct.pack('<QQQ', key_size, sig_size, len(message))
                               + key + signature + message)
            result = run(harness, packet, env={**os.environ, 'PATH': '/no/executables'})
            assert result.returncode == (0 if valid else 1), (result.returncode, result.stderr)
            count += 1

        for public, message, signature in VECTORS:
            key, msg, sig = map(bytes.fromhex, (public, message, signature))
            verify(key, sig, msg, True)
            verify(key, sig, msg + b'\x00', False)
            verify(bytes([key[0] ^ 1]) + key[1:], sig, msg, False)
            verify(key, bytes([sig[0] ^ 1]) + sig[1:], msg, False)
            verify(key, sig[:-1] + bytes([sig[-1] ^ 1]), msg, False)
            # Non-canonical scalar S+L must not verify the same message.
            order = 2**252 + 27742317777372353535851937790883648493
            malleable = sig[:32] + (int.from_bytes(sig[32:], 'little') + order).to_bytes(32, 'little')
            verify(key, malleable, msg, False)
        for key_size in [0, 31, 33]:
            verify(key, sig, msg, False, key_size=key_size)
        for sig_size in [0, 63, 65]:
            verify(key, sig, msg, False, sig_size=sig_size)

        # Exercise the production signer using an isolated source/key tree.
        # The real CI private key is never needed by the test suite.
        tree = work / 'signer'
        for directory in ['scripts', 'keys', 'compiler', 'dist']:
            (tree / directory).mkdir(parents=True)
        shutil.copyfile(ROOT / 'scripts/sign-release.py', tree / 'scripts/sign-release.py')
        (tree / 'VERSION').write_text(VERSION + '\n')
        private = work / 'private.pem'
        success(run('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', private))
        private.chmod(0o600)
        public = run('openssl', 'pkey', '-in', private, '-pubout')
        success(public)
        public_path = tree / 'keys/release-ed25519.pub.pem'
        public_path.write_bytes(public.stdout)
        der = run('openssl', 'pkey', '-in', private, '-pubout', '-outform', 'DER')
        success(der)
        assert len(der.stdout) == 44
        compiler_path = tree / 'compiler/main.flex'
        compiler_path.write_text(f'fn release_public_key() {{ return "{der.stdout[12:].hex()}"; }}')
        manifest = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                           for name, data in [(f'flexscript-{VERSION}-linux-x86_64', b'full compiler'),
                                              (f'flexscript-core-{VERSION}-linux-x86_64', b'core compiler')])
        for prefix, data in [('flexscript', b'full compiler'), ('flexscript-core', b'core compiler')]:
            (tree / 'dist' / f'{prefix}-{VERSION}-linux-x86_64').write_bytes(data)
        manifest_path = tree / 'dist/SHA256SUMS'
        manifest_path.write_text(manifest)
        sig_path = tree / 'dist/SHA256SUMS.sig'
        command = [sys.executable, tree / 'scripts/sign-release.py']
        env = {**os.environ, 'FLEXSCRIPT_RELEASE_SIGNING_KEY': private.read_text()}
        success(run(*command, env=env))
        signature = sig_path.read_bytes()
        assert len(signature) == 64
        message = (f'Flexscript release signature v1\nversion={VERSION}\ntarget=linux-x86_64\n'
                   + manifest).encode()
        verify(der.stdout[12:], signature, message, True)
        verify(der.stdout[12:], signature, message.replace(b'linux-x86_64', b'linux-aarch64'), False)
        verify(der.stdout[12:], signature, message[:-1], False)

        def refuse(expected, environment=env, extra=()):
            nonlocal count
            sig_path.unlink(missing_ok=True)
            result = run(*command, *extra, env=environment)
            assert result.returncode == 1 and expected.encode() in result.stderr, (result.stdout, result.stderr)
            assert not sig_path.exists(), 'published a signature on signing failure'
            assert private.read_bytes().strip() not in result.stdout + result.stderr
            count += 1

        no_key = {k: v for k, v in os.environ.items() if k != 'FLEXSCRIPT_RELEASE_SIGNING_KEY'}
        refuse('required; refusing unsigned', environment=no_key)
        other = work / 'other.pem'
        success(run('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', other))
        other.chmod(0o600)
        refuse('does not match', environment={**env, 'FLEXSCRIPT_RELEASE_SIGNING_KEY': other.read_text()})
        refuse('OpenSSL release-signing operation failed', environment={**env, 'FLEXSCRIPT_RELEASE_SIGNING_KEY': 'invalid'})
        for version in ['v0.0.4', '00.0.4', '0.0.1000000000', '99.99.99']:
            refuse('version', extra=('--version', version))
        manifest_path.write_text(manifest.upper())
        refuse('checksums do not match')
        manifest_path.write_text(manifest)
        asset = tree / 'dist' / f'flexscript-{VERSION}-linux-x86_64'
        asset.write_bytes(b'tampered compiler')
        refuse('checksums do not match')
        asset.write_bytes(b'full compiler')
        compiler_path.write_text('fn release_public_key() { return "' + '0' * 64 + '"; }')
        refuse('differs from the compiler trust anchor')

    print(f'{compiler.name}: {count} signature checks passed', flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers', nargs='+', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = [{'compiler': str(p), 'checks': suite(p.resolve())} for p in args.compilers]
    total = sum(r['checks'] for r in results)
    print(f'Total: {total} signature checks passed')
    if args.report:
        args.report.write_text(json.dumps({'results': results, 'total': total}, indent=2) + '\n')


if __name__ == '__main__':
    main()
