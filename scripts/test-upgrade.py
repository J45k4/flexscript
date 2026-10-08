#!/usr/bin/env python3
"""Exercise upgrades on disposable installations, against a local HTTPS release server."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import subprocess
import tempfile
import time

from tls_fixture import QuietHandler, TLSServer
from bootstrap import bootstrap_source

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()
parts = VERSION.split('.')
FUTURE = '.'.join(parts[:2] + [str(int(parts[2]) + 1)])
API = 'https://api.github.com/repos/J45k4/flexscript/releases/latest'
NAME = f'flexscript-{FUTURE}-linux-x86_64'
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

class ReleaseHandler(QuietHandler):
    def do_GET(self):
        d = self.server.fixture
        url = self.server.url + self.path
        with (d / 'requests').open('a') as f:
            f.write(url + '\n')
        name = 'metadata' if self.path.endswith('/releases/latest') else (
            'manifest' if self.path.endswith('/SHA256SUMS') else (
                'signature' if self.path.endswith('/SHA256SUMS.sig') else 'binary'))
        control = json.loads((d / 'control').read_text())
        if control.get('fail') == name:
            self.payload(b'download failed', 503)
            return
        if name == 'binary':
            target = Path(control['target'])
            if control.get('replace'):
                shutil.copyfile(d / 'replacement', d / 'replacement-install')
                (d / 'replacement-install').chmod(0o755)
                os.replace(d / 'replacement-install', target)
            if control.get('collision'):
                end = time.monotonic() + 5
                while not (d / 'parent-pid').exists() and time.monotonic() < end:
                    time.sleep(.01)
                pid = int((d / 'parent-pid').read_text())
                stage = Path(str(target) + '.upgrade.' + str(pid))
                stage.mkdir()
                (stage / 'sentinel').write_text('keep me')
        if control.get('hold') == name:
            (d / 'ready').touch()
            while not (d / 'continue').exists():
                time.sleep(.01)
        self.payload((d / name).read_bytes())


def run(*args, env=None):
    return subprocess.run([str(a) for a in args], capture_output=True, env=env, timeout=40)


def success(result):
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)


def build(compiler, work, name, source):
    path = work / (name + '.flex')
    path.write_text(source)
    binary = work / name
    success(run(compiler, path, '-o', binary))
    return binary


def wait_ready(directory, process):
    end = time.monotonic() + 5
    while not (directory / 'ready').exists():
        assert process.poll() is None, process.communicate()
        assert time.monotonic() < end, 'HTTPS fixture did not start'
        time.sleep(.01)


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flexscript-upgrade-') as temp:
        work = Path(temp)
        key = work / 'test-private.pem'
        success(run('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', key))
        key.chmod(0o600)
        other_key = work / 'other-private.pem'
        success(run('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', other_key))
        other_key.chmod(0o600)
        public = run('openssl', 'pkey', '-in', key, '-pubout', '-outform', 'DER')
        success(public)
        assert len(public.stdout) == 44 and public.stdout[:12].hex() == '302a300506032b6570032100'

        def sign(manifest, version=FUTURE, private=key):
            message = work / 'signed-message'
            message.write_bytes((f'Flexscript release signature v1\nversion={version}\n'
                                 'target=linux-x86_64\n').encode() + manifest)
            signature = work / 'signed-signature'
            success(run('openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', private,
                        '-in', message, '-out', signature))
            return signature.read_bytes()

        with TLSServer(work, ReleaseHandler) as server:
            # TemporaryDirectory cleanup also runs after every assertion failure.
            fixture_source = bootstrap_source().split('// Static bootstrap core:')[0]
            fixture_source, replaced = re.subn(
                r'fn release_public_key\(\) \{ return "[0-9a-f]{64}"; \}',
                f'fn release_public_key() {{ return "{public.stdout[12:].hex()}"; }}', fixture_source)
            assert replaced == 1, 'fixture must use its own test signing key'
            fixture_source = fixture_source.replace(API, server.url + '/releases/latest').replace(
                'https://github.com/J45k4/flexscript/releases/download/', server.url + '/download/')
            original = compiler
            compiler = build(original, work, 'test-compiler', fixture_source)
            expected_requests = [server.url + '/releases/latest',
                                 server.url + '/download/' + FUTURE + '/SHA256SUMS',
                                 server.url + '/download/' + FUTURE + '/SHA256SUMS.sig',
                                 server.url + '/download/' + FUTURE + '/' + NAME]
            future = build(compiler, work, 'future', fixture_source.replace(
                f'fn compiler_version() {{ return "{VERSION}"; }}',
                f'fn compiler_version() {{ return "{FUTURE}"; }}'))
            payload = future.read_bytes()
            assert run(future, '--version').stdout == f'flexscript {FUTURE}\n'.encode()
            wrong = build(compiler, work, 'wrong', 'fn main(){return 0;}').read_bytes()
            broken = build(compiler, work, 'broken', 'fn main(){return 7;}').read_bytes()
            hanging = build(compiler, work, 'hanging',
                            'fn main(){syscall(7,0,0,60000,0,0,0);return 0;}').read_bytes()

            def fixture(name, metadata=None, binary=payload, manifest=None, control=None,
                        signature=None, sign_version=FUTURE, sign_key=key):
                directory = work / name
                directory.mkdir()
                installed = directory / 'flex'
                shutil.copyfile(compiler, installed)
                installed.chmod(0o751)
                before = installed.stat()
                if metadata is None:
                    metadata = json.dumps({'tag_name': FUTURE, 'draft': False, 'prerelease': False,
                                           'assets': [{'tag_name': 'ignore nested fields'}],
                                           'body': 'Unicode ✓ and \\"escapes\\"', 'number': -1.25e3})
                if isinstance(metadata, str):
                    metadata = metadata.encode()
                (directory / 'metadata').write_bytes(metadata)
                (directory / 'binary').write_bytes(binary)
                if manifest is None:
                    manifest = f'{hashlib.sha256(binary).hexdigest()}  {NAME}\n'
                (directory / 'manifest').write_text(manifest)
                if signature is None:
                    signature = sign(manifest.encode(), sign_version, sign_key)
                (directory / 'signature').write_bytes(signature)
                (directory / 'replacement').write_bytes(wrong)
                settings = {'target': str(installed), **(control or {})}
                (directory / 'control').write_text(json.dumps(settings))
                server.fixture = directory
                env = {**os.environ, 'SSL_CERT_FILE': str(server.cert)}
                return directory, installed, before, env

            def unchanged(directory, installed, before):
                assert installed.read_bytes() == compiler.read_bytes(), 'changed installation on rejection'
                after = installed.stat()
                assert (after.st_ino, after.st_mode, after.st_uid, after.st_gid) == (
                    before.st_ino, before.st_mode, before.st_uid, before.st_gid)
                assert not list(directory.glob('flex.upgrade.*')), 'staging directory leaked'

            def reject(name, expected, **kwargs):
                nonlocal count
                directory, installed, before, env = fixture(name, **kwargs)
                result = run(installed, 'upgrade', env=env)
                assert result.returncode == 1 and expected.encode() in result.stderr, (
                    name, result.returncode, result.stdout, result.stderr)
                unchanged(directory, installed, before)
                count += 1
                return directory

            directory, installed, before, env = fixture('success')
            success(run(installed, 'upgrade', env=env))
            assert installed.read_bytes() == payload
            after = installed.stat()
            assert (after.st_mode, after.st_uid, after.st_gid) == (before.st_mode, before.st_uid, before.st_gid)
            assert not list(directory.glob('flex.upgrade.*'))
            assert (directory / 'requests').read_text().splitlines() == expected_requests
            assert run(installed, '--version').stdout == f'flexscript {FUTURE}\n'.encode()
            (directory / 'module.flex').write_text('fn hello(){return 42;}')
            program = build(installed, directory, 'program', 'import "module.flex"; fn main(){return hello();}')
            assert run(program).returncode == 42
            count += 1

            directory, installed, before, env = fixture('symlink')
            launcher = directory / 'launcher'
            launcher.symlink_to('flex')
            success(run(launcher, 'upgrade', env=env))
            assert launcher.is_symlink() and os.readlink(launcher) == 'flex'
            assert installed.read_bytes() == payload
            assert not list(directory.glob('flex.upgrade.*'))
            count += 1

            for name, metadata, expected in [('check', None, b'Upgrade available:'),
                                             ('equal', json.dumps({'tag_name': VERSION}), b'Already up to date'),
                                             ('older', '{"tag_name":"0.0.0"}', b'newer than the latest')]:
                directory, installed, before, env = fixture(name, metadata=metadata)
                result = run(installed, 'upgrade', *(['--check'] if name == 'check' else []), env=env)
                success(result)
                assert expected in result.stdout
                unchanged(directory, installed, before)
                assert (directory / 'requests').read_text().splitlines() == expected_requests[:1]
                count += 1

            # Strings and nested JSON cannot masquerade as the root release tag.
            bad_metadata = ['{}', '[]', '{', '{"nested":{"tag_name":"0.0.3"}}',
                            '{"body":"tag_name:0.0.3"}', '{"tag_name":1}',
                            '{"tag_name":"0.0.3","tag_name":"0.0.4"}',
                            '{"tag_name":"0.0.3","draft":true}',
                            '{"tag_name":"0.0.3","prerelease":true}',
                            '{"tag_name":"0.0.3","draft":0}',
                            '{"tag_name":"0.0.3",}', '{"tag_name":"0.0.3"}garbage',
                            '{"tag_name":"0.0.3","x":01}', '{"tag_name":"0.0.3","x":1.}',
                            '{"tag_name":"0.0.3","x":1e}', '{"tag_name":"0.0.3","x":"\\q"}',
                            '{"tag_name":"0.0.3","x":' + '[' * 70 + '0' + ']' * 70 + '}']
            for i, metadata in enumerate(bad_metadata):
                reject(f'json-{i}', 'Invalid latest-release metadata', metadata=metadata)
            for i, tag in enumerate(['', '../0.0.3', 'v0.0.3', '0.0.3-beta', '0.0', '0.0.3.1',
                                     '00.0.3', '0.0.03', '0.0.-1', '0.0.1000000000', '0.0.3\x00']):
                reject(f'tag-{i}', 'numeric major.minor.patch', metadata=json.dumps({'tag_name': tag}))
            reject('metadata-limit', 'size limit', metadata=b' ' * 65537)
            reject('manifest-limit', 'size limit', manifest=' ' * 65537)
            for item in ['metadata', 'manifest', 'signature', 'binary']:
                reject('https-fail-' + item, 'command failed', control={'fail': item})

            # Reject unauthenticated content before downloading or executing it.
            altered = hashlib.sha256(wrong).hexdigest() + f'  {NAME}\n'
            good_signature = sign((hashlib.sha256(payload).hexdigest() + f'  {NAME}\n').encode())
            attacks = [
                ('missing-signature', 'command failed', {'control': {'fail': 'signature'}}),
                ('empty-signature', 'signature verification failed', {'signature': b''}),
                ('short-signature', 'signature verification failed', {'signature': good_signature[:-1]}),
                ('long-signature', 'size limit', {'signature': good_signature + b'\x00'}),
                ('wrong-key', 'signature verification failed', {'sign_key': other_key}),
                ('version-replay', 'signature verification failed', {'sign_version': VERSION}),
                ('damaged-signature', 'signature verification failed',
                 {'signature': bytes([good_signature[0] ^ 1]) + good_signature[1:]}),
                ('replaced-manifest', 'signature verification failed',
                 {'binary': wrong, 'manifest': altered, 'signature': good_signature}),
                ('changed-manifest-byte', 'signature verification failed',
                 {'manifest': hashlib.sha256(payload).hexdigest().upper() + f'  {NAME}\n',
                  'signature': good_signature}),
                ('wrong-target', 'signature verification failed', {'signature': b'\x00' * 64}),
            ]
            # Generate a real signature for another target, rather than merely corrupting one.
            (work / 'signed-message').write_bytes(
                (f'Flexscript release signature v1\nversion={FUTURE}\ntarget=linux-aarch64\n'
                 + hashlib.sha256(payload).hexdigest() + f'  {NAME}\n').encode())
            success(run('openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', key,
                        '-in', work / 'signed-message', '-out', work / 'signed-signature'))
            attacks[-1][2]['signature'] = (work / 'signed-signature').read_bytes()
            for name, expected, settings in attacks:
                directory = reject(name, expected, **settings)
                assert (directory / 'requests').read_text().splitlines() == expected_requests[:3], name

            directory, installed, before, env = fixture('signature-no-tools')
            env['PATH'] = '/no/executables'
            success(run(installed, 'upgrade', env=env))
            assert installed.read_bytes() == payload
            count += 1

            for i, manifest in enumerate(['', '0' * 64 + '  other-file\n',
                                          'z' * 64 + f'  {NAME}\n',
                                          '0' * 64 + f' {NAME}\n',
                                          '0' * 64 + f'  {NAME}\n' + '0' * 64 + f'  {NAME}\n',
                                          'malformed\n']):
                reject(f'manifest-{i}', 'checksums do not uniquely', manifest=manifest)
            reject('checksum', 'SHA-256 checksum mismatch', manifest='0' * 64 + f'  {NAME}\n')
            for name, binary in [('text', b'not ELF'), ('truncated', payload[:-1]),
                                 ('architecture', payload[:18] + b'\x03\x00' + payload[20:])]:
                reject(name, 'not a native Linux', binary=binary)
            reject('version-mismatch', 'version does not match', binary=wrong)
            reject('probe-failed', 'command failed', binary=broken)

            for name, manifest in [('uppercase', hashlib.sha256(payload).hexdigest().upper() + f' *{NAME}\r\n'),
                                   ('no-newline', hashlib.sha256(payload).hexdigest() + f'  {NAME}')]:
                directory, installed, before, env = fixture(name, manifest=manifest)
                success(run(installed, 'upgrade', env=env))
                assert installed.read_bytes() == payload
                count += 1

            directory, installed, before, env = fixture('no-curl')
            env['PATH'] = str(directory)
            result = run(installed, 'upgrade', '--check', env=env)
            success(result)
            assert b'Upgrade available:' in result.stdout
            unchanged(directory, installed, before)
            count += 1
            result = run(installed, 'upgrade', '--unknown', env=env)
            assert result.returncode == 1 and b'Usage: flex upgrade' in result.stderr
            unchanged(directory, installed, before)
            count += 1

            directory, installed, before, env = fixture('changed-target', control={'replace': True})
            result = run(installed, 'upgrade', env=env)
            assert result.returncode == 1 and b'changed during upgrade' in result.stderr, result.stderr
            assert installed.read_bytes() == wrong
            assert not list(directory.glob('flex.upgrade.*'))
            count += 1

            directory, installed, before, env = fixture('collision', control={'collision': True})
            process = subprocess.Popen([str(installed), 'upgrade'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            (directory / 'parent-pid').write_text(str(process.pid))
            stdout, stderr = process.communicate(timeout=10)
            result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
            assert result.returncode == 1 and b'Cannot create staging directory' in result.stderr
            assert installed.read_bytes() == compiler.read_bytes()
            leftovers = list(directory.glob('flex.upgrade.*'))
            assert len(leftovers) == 1 and (leftovers[0] / 'sentinel').read_text() == 'keep me'
            count += 1

            directory, installed, before, env = fixture('concurrent', control={'hold': 'binary'})
            first = subprocess.Popen([str(installed), 'upgrade'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                wait_ready(directory, first)
                second = run(installed, 'upgrade', env=env)
                assert second.returncode == 1 and b'Another upgrade' in second.stderr, second.stderr
                (directory / 'continue').touch()
                stdout, stderr = first.communicate(timeout=10)
                assert first.returncode == 0, (stdout, stderr)
                assert installed.read_bytes() == payload
                assert not list(directory.glob('flex.upgrade.*'))
            finally:
                if first.poll() is None:
                    first.kill()
                    first.communicate()
            count += 1

            for sig in [signal.SIGINT, signal.SIGTERM]:
                directory, installed, before, env = fixture('signal-' + str(sig), control={'hold': 'binary'})
                process = subprocess.Popen([str(installed), 'upgrade'], env=env,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    wait_ready(directory, process)
                    process.send_signal(sig)
                    stdout, stderr = process.communicate(timeout=5)
                    assert process.returncode == 128 + sig and b'interrupted' in stderr, (stdout, stderr)
                    unchanged(directory, installed, before)
                    (directory / 'continue').touch()
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()
                count += 1

            directory, installed, before, env = fixture('probe-interrupt', binary=hanging)
            process = subprocess.Popen([str(installed), 'upgrade'], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                end = time.monotonic() + 5
                while not list(directory.glob('flex.upgrade.*/compiler')):
                    assert process.poll() is None, process.communicate()
                    assert time.monotonic() < end
                    time.sleep(.01)
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                assert process.returncode == 143, (stdout, stderr)
                unchanged(directory, installed, before)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
            count += 1

            if os.geteuid() != 0:
                directory, installed, before, env = fixture('permissions')
                # The server's request log lives in the fixture; the installation parent
                # alone is read-only. --check never needs installation write access.
                parent = directory / 'installation'
                parent.mkdir()
                relocated = parent / 'flex'
                installed.rename(relocated)
                settings = {'target': str(relocated)}
                (directory / 'control').write_text(json.dumps(settings))
                parent.chmod(0o555)
                try:
                    success(run(relocated, 'upgrade', '--check', env=env))
                    result = run(relocated, 'upgrade', env=env)
                    assert result.returncode == 1 and b'installation permissions' in result.stderr
                    assert relocated.read_bytes() == compiler.read_bytes()
                    assert not list(parent.glob('flex.upgrade.*'))
                finally:
                    parent.chmod(0o755)
                count += 1

            # Independent hashlib known-answer checks include every padding boundary,
            # binary data and a million-byte message. No public testing command added.
            harness = build(compiler, work, 'sha-harness', bootstrap_source().split('// Static bootstrap core:')[0].replace('fn main(argc, argv)', 'fn original_main(argc, argv)') + '''
    fn main(argc,argv) {
        if !up_init() { return 1; }
        let fd=syscall(2,load64(argv+8),0,0,0,0,0);
        if fd<0 { return 2; }
        let data=alloc(1048576); let n=0; let more=1;
        while more { let got=syscall(0,fd,data+n,1048576-n,0,0,0); if got<0 {return 3;}
            if !got {more=0;} else {n=n+got;} }
        print(1,up_sha256(data,n)); return 0;
    }
    ''')
            vectors = [b'', b'abc', b'a' * 1000000] + [bytes(i % 256 for i in range(n))
                                                              for n in [1, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024]]
            for message in vectors:
                (work / 'message').write_bytes(message)
                result = run(harness, work / 'message')
                success(result)
                assert result.stdout.decode() == hashlib.sha256(message).hexdigest(), result.stdout
                count += 1
    print(f'{original.name}: {count} upgrade checks passed', flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers', nargs='+', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = [{'compiler': str(p), 'checks': suite(p.resolve())} for p in args.compilers]
    total = sum(result['checks'] for result in results)
    print(f'Total: {total} upgrade checks passed')
    if args.report:
        args.report.write_text(json.dumps({'results': results, 'total': total}, indent=2) + '\n')


if __name__ == '__main__':
    main()
