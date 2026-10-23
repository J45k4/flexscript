#!/usr/bin/env python3
"""Revoke an allowed device while a real Flexscript program is running."""
import argparse
import hashlib
import json
import subprocess
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--serial', required=True)
p.add_argument('--adb', default='/opt/android-sdk/platform-tools/adb')
a = p.parse_args()
assert a.serial.startswith('emulator-'), 'Use an isolated emulator.'
pkg = 'org.flexscript.collie'
name = 'revoke-hw-' + uuid.uuid4().hex[:12]
names = []

def adb(*args, data=None):
    r = subprocess.run([a.adb, '-s', a.serial, *map(str, args)],
                       input=data, capture_output=True, timeout=45)
    assert r.returncode == 0, (args, r.stdout[:500], r.stderr[:500])
    return r.stdout

def read(path):
    return json.loads(adb('exec-out', 'run-as', pkg, 'cat', path))

def run(case_name, case):
    names.append(case_name)
    adb('shell', 'run-as', pkg, 'sh', '-c',
        "'umask 077; cat > files/test/" + case_name + ".json'",
        data=json.dumps(case).encode())
    adb('shell', 'am', 'start', '-n', pkg + '/.MainActivity',
        '--es', 'test_case', case_name)
    deadline = time.monotonic() + 90
    path = 'files/test/' + case_name + '.result.json'
    while time.monotonic() < deadline:
        r = subprocess.run([a.adb, '-s', a.serial, 'exec-out', 'run-as', pkg,
                            'cat', path], capture_output=True, timeout=15)
        if r.returncode == 0 and r.stdout.strip():
            try:
                result = json.loads(r.stdout)
            except json.JSONDecodeError:
                time.sleep(.2)
                continue
            assert result['ok'], result
            return result
        time.sleep(.2)
    raise AssertionError('Live-revocation fixture timed out')

prefs = ET.fromstring(adb('exec-out', 'run-as', pkg, 'cat',
                         'shared_prefs/MainActivity.xml'))
original = next(n.text for n in prefs if n.get('name') == 'session')
before = read('files/workspaces/' + original + '/session.json')
adb('shell', 'run-as', pkg, 'mkdir', '-p', 'files/test')
try:
    adb('shell', 'am', 'force-stop', pkg)
    result = run(name, dict(session=name, hardware_tests=True,
                           hardware_revocation_tests=True,
                           initial_permissions=dict(wifi=True, db_read=True,
                                                    db_write=True)))
    checks = result['hardware']['checks']
    for check in checks:
        print('PASS', check, flush=True)
finally:
    adb('shell', 'am', 'force-stop', pkg)
    run(name + '-restore', dict(session=original, resume_only=True,
                               initial_permissions=None))
    after = read('files/workspaces/' + original + '/session.json')
    assert before['messages'] == after['messages']
    assert before['permissions'] == after['permissions']
    adb('shell', 'run-as', pkg, 'rm', '-rf', 'files/workspaces/' + name)
    for fixture in names:
        adb('shell', 'run-as', pkg, 'rm', '-f', 'files/test/' + fixture + '.json',
            'files/test/' + fixture + '.result.json')
checks.append('original conversation and permissions preserved; temporary workspace removed')
report = dict(count=len(checks), checks=checks, serial=a.serial,
              apk_sha256=hashlib.sha256((a.out / 'collie.apk').read_bytes()).hexdigest())
(a.out / 'revocation-android-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(len(checks), 'Android revocation checks passed')
