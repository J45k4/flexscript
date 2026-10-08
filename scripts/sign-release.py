#!/usr/bin/env python3
"""Sign verified release checksums with the CI-only Ed25519 private key."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / 'keys/release-ed25519.pub.pem'
DER_PREFIX = bytes.fromhex('302a300506032b6570032100')


def openssl(*args):
    environment = {k: v for k, v in os.environ.items() if k != 'FLEXSCRIPT_RELEASE_SIGNING_KEY'}
    result = subprocess.run(['openssl', *map(str, args)], capture_output=True, timeout=30, env=environment)
    if result.returncode:
        # Do not copy tool diagnostics into CI logs where key material is present.
        raise ValueError('OpenSSL release-signing operation failed')
    return result.stdout


def pinned_key():
    public = openssl('pkey', '-pubin', '-in', PUBLIC, '-outform', 'DER')
    if len(public) != 44 or not public.startswith(DER_PREFIX):
        raise ValueError('release public key must be Ed25519')
    match = re.search(r'fn release_public_key\(\) \{ return "([0-9a-f]{64})"; \}',
                      (ROOT / 'compiler/main.flex').read_text())
    if not match or bytes.fromhex(match[1]) != public[12:]:
        raise ValueError('public key differs from the compiler trust anchor')
    return public


def sign(dist, version):
    if not re.fullmatch(r'(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})', version):
        raise ValueError('invalid release version')
    if version != (ROOT / 'VERSION').read_text().strip():
        raise ValueError('release version differs from source VERSION')
    manifest = (dist / 'SHA256SUMS').read_bytes()
    if not 0 < len(manifest) <= 65536:
        raise ValueError('invalid checksum manifest size')
    expected = []
    for prefix in ['flexscript', 'flexscript-core']:
        name = f'{prefix}-{version}-linux-x86_64'
        binary = dist / name
        if not 0 < binary.stat().st_size <= 67108864:
            raise ValueError('invalid release binary size')
        expected.append(f'{hashlib.sha256(binary.read_bytes()).hexdigest()}  {name}\n')
    if manifest != ''.join(expected).encode('ascii'):
        raise ValueError('release checksums do not match both compiler assets')
    public = pinned_key()
    private = os.environ.get('FLEXSCRIPT_RELEASE_SIGNING_KEY')
    if not private:
        raise ValueError('FLEXSCRIPT_RELEASE_SIGNING_KEY is required; refusing unsigned release')
    message = (f'Flexscript release signature v1\nversion={version}\ntarget=linux-x86_64\n'.encode()
               + manifest)
    # TemporaryDirectory is mode 0700; the private key file is mode 0600.
    # No private key is placed in the checkout, build artifact or release assets.
    with tempfile.TemporaryDirectory(prefix='flexscript-sign-') as temporary:
        work = Path(temporary)
        key = work / 'private.pem'
        fd = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(private)
        if openssl('pkey', '-in', key, '-pubout', '-outform', 'DER') != public:
            raise ValueError('CI signing key does not match the pinned release public key')
        data = work / 'message'
        data.write_bytes(message)
        signature = work / 'signature'
        openssl('pkeyutl', '-sign', '-rawin', '-inkey', key, '-in', data, '-out', signature)
        result = signature.read_bytes()
        if len(result) != 64:
            raise ValueError('invalid Ed25519 signature length')
        openssl('pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', PUBLIC,
                '-in', data, '-sigfile', signature)
        # Publish the signature only after checking the key and signature.
        fd, staged = tempfile.mkstemp(prefix='.signature-', dir=dist)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(result)
            os.chmod(staged, 0o644)
            os.replace(staged, dist / 'SHA256SUMS.sig')
        finally:
            Path(staged).unlink(missing_ok=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist-dir', type=Path, default=ROOT / 'dist')
    parser.add_argument('--version', default=(ROOT / 'VERSION').read_text().strip())
    args = parser.parse_args()
    try:
        sign(args.dist_dir.resolve(), args.version)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        # Exception text can include paths and validation errors, never the key.
        parser.exit(1, f'Release signing failed: {error}\n')
    print(f'Signed Flexscript {args.version} Linux x86-64 release checksums (Ed25519).')


if __name__ == '__main__':
    main()
