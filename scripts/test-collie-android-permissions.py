#!/usr/bin/env python3
"""Verify permission switches and real VM enforcement on an installed debug APK.

Uses an explicitly selected Android device. Restores the original conversation,
removes its temporary sessions, and leaves Menu > Permissions open for review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--out', type=Path, default=Path('build/android-collie'))
parser.add_argument('--adb', default='/opt/android-sdk/platform-tools/adb')
args = parser.parse_args()
out = args.out.resolve() / 'permissions'
out.mkdir(parents=True, exist_ok=True)
pkg = 'org.flexscript.collie'
checks, requests = [], []
labels = dict(internet='Internet access', files_read='Read workspace files',
    files_write='Write workspace files', db_read='Read database',
    db_write='Write database', history='Read past messages', workers='Manage workers')

def adb(*command, data=b'', check=True):
    result = subprocess.run([args.adb, '-s', args.serial, *map(str, command)],
        input=data, capture_output=True, timeout=40)
    if check and result.returncode:
        raise RuntimeError((command, result.stdout[:300], result.stderr[:300]))
    return result.stdout

def saved(session):
    return json.loads(adb('exec-out', 'run-as', pkg, 'cat',
        'files/workspaces/' + session + '/session.json'))

prefs = ET.fromstring(adb('exec-out', 'run-as', pkg, 'cat', 'shared_prefs/MainActivity.xml'))
original = next(node.text for node in prefs if node.get('name') == 'session')
before = saved(original)
session = 'perm-check-' + str(time.time_ns())
other = session + '-other'

def base_grants(sid):return {key:saved(sid)['permissions'][key] for key in labels}

def case(name, request):
    requests.append(name)
    request.setdefault('session', session)
    request.setdefault('initial_permissions', dict.fromkeys(labels, True))
    path = 'files/test/' + name
    adb('shell', 'run-as', pkg, 'mkdir', '-p', 'files/test')
    adb('shell', 'run-as', pkg, 'sh', '-c', "'cat > " + path + ".json'",
        data=json.dumps(request).encode())
    adb('shell', 'run-as', pkg, 'rm', '-f', path + '.result.json')
    adb('shell', 'am', 'start', '-n', pkg + '/.MainActivity', '--es', 'test_case', name)
    until = time.monotonic() + 60
    while time.monotonic() < until:
        raw = adb('exec-out', 'run-as', pkg, 'cat', path + '.result.json', check=False)
        if raw.lstrip().startswith(b'{'):
            result = json.loads(raw)
            assert result.get('ok'), result
            (out / (name + '.json')).write_text(json.dumps(result, indent=2) + '\n')
            time.sleep(.3)
            return result
        time.sleep(.25)
    raise AssertionError('Timed out: ' + name)

def run(name, source):
    return case(name, dict(source=source))['observation']

def tree():
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/collie-permissions.xml')
    return ET.fromstring(adb('exec-out', 'cat', '/data/local/tmp/collie-permissions.xml'))

def find(root, label, checkable=False):
    return next((node for node in root.iter('node') if
        (node.get('content-desc') == label or node.get('text') == label)
        and (not checkable or node.get('checkable') == 'true')), None)

def tap(node):
    assert node is not None, 'Missing control'
    left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
    adb('shell', 'input', 'tap', (left + right) // 2, (top + bottom) // 2)
    time.sleep(.2)

size = re.findall(rb'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1]
width, height = map(int, size)

def scroll(down):
    adb('shell', 'input', 'swipe', width // 2, int(height * (.76 if down else .32)),
        width // 2, int(height * (.32 if down else .76)), 250)

def toggle(key, checked):
    for _ in range(8):
        node = find(tree(), ('Allow ' if checked else 'Deny ') + labels[key])
        if node is not None:
            left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
            if right > left and bottom > top and bottom < height - 40:
                tap(node)
                until = time.monotonic() + 2
                while time.monotonic() < until:
                    if saved(session)['permissions'][key] == checked:
                        return
                    time.sleep(.1)
        scroll(True)
    raise AssertionError('Permission choice not reachable: ' + key)

def open_page():
    tap(find(tree(), 'Menu'))
    tap(find(tree(), 'Permissions'))
    root = tree()
    assert find(root, 'Permissions') is not None
    assert find(root, 'Message Collie') is None
    return root

def passed(name):
    checks.append(name)
    print('PASS', name, flush=True)

seed = '''fn main(){
fs_write("note.txt",db_text("private"));db_begin();
let s=db_schema();db_column(s,"value",2,0);db_create("notes",s);
let v=db_values();db_add(v,db_text("persistent"));db_insert("notes",v);
return db_commit()-1;}'''
try:
    assert run('perm_seed', seed)['exit_code'] == 0
    assert all(base_grants(session).values())
    open_page()
    (out / 'all-enabled.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    passed('Dedicated permission page lists conversation grants with explicit legacy grants enabled')
    for key in labels:
        toggle(key, False)
    assert not any(base_grants(session).values())
    passed('All seven settings persist their settings immediately')

    probes = dict(internet='http_get("https://example.com/")',
        files_read='fs_read("note.txt",0,100)',
        files_write='fs_write("note.txt",db_text("forbidden"))',
        db_read='db_tables()', db_write='db_begin()', history='db_history(0,10)')
    for key, probe in probes.items():
        result = run('perm_deny_' + key, 'fn main(){' + probe +
            ';let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}')
        assert result['stdout'] == 'Permission denied: ' + key, result
    assert adb('exec-out', 'run-as', pkg, 'cat',
        'files/workspaces/' + session + '/files/note.txt') == b'private'
    passed('Real device VM denies every disabled capability and preserves existing files')

    adb('shell', 'am', 'force-stop', pkg)
    adb('shell', 'am', 'start', '-n', pkg + '/.MainActivity')
    assert not any(base_grants(session).values())
    open_page()
    assert find(tree(), '0 allowed · 23 ask · 7 denied') is not None
    adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    assert find(tree(), 'Message Collie') is not None
    open_page()
    tap(find(tree(), 'Back to conversation'))
    assert find(tree(), 'Message Collie') is not None
    passed('Grants survive process restart; header Back and Android Back return to chat')

    case('perm_other', dict(session=other, source='fn main(){return 0;}'))
    assert all(base_grants(other).values())
    case('perm_reopen', dict(resume_only=True))
    assert not any(base_grants(session).values())
    passed('Permissions belong to their conversation and do not affect another session')

    open_page()
    toggle('files_read', True)
    toggle('db_read', True)
    tap(find(tree(), 'Back to conversation'))
    result = run('perm_read_files', 'fn main(){let v=fs_read("note.txt",0,100);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return 0;}')
    assert result['stdout'] == 'private', result
    result = run('perm_read_db', 'fn main(){let v=db_cell(db_at(db_scan("notes",0,10),0),0);syscall(1,1,db_word(v),db_bytes(v),0,0,0);return 0;}')
    assert result['stdout'] == 'persistent', result
    result = run('perm_write_still_denied', 'fn main(){db_begin();let e=db_error();syscall(1,1,e,db_len(e),0,0,0);return 0;}')
    assert result['stdout'] == 'Permission denied: db_write', result
    passed('Read-only files and database work while write permissions remain disabled')

    open_page()
    toggle('internet', True)
    tap(find(tree(), 'Back to conversation'))
    result = run('perm_net_enabled', 'fn main(){let r=http_get("https://example.com/");if !r {return 1;}let b=http_body(r);syscall(1,1,db_word(b),db_bytes(b),0,0,0);if http_status(r)!=200 {return 2;}return 0;}')
    assert result['exit_code'] == 0 and 'Example Domain' in result['stdout'], result
    passed('Re-enabling internet in the UI permits a genuine HTTPS fetch')
finally:
    case('perm_restore', dict(session=original, resume_only=True))
    after = saved(original)
    assert before['messages'] == after['messages']
    assert after['permissions'] == before.get('permissions', dict.fromkeys(labels, True))
    for name in requests:
        adb('shell', 'run-as', pkg, 'rm', '-f', 'files/test/' + name + '.json',
            'files/test/' + name + '.result.json')
    for temporary in [session, other]:
        assert temporary != original
        adb('shell', 'run-as', pkg, 'rm', '-rf', 'files/workspaces/' + temporary)
    adb('shell', 'am', 'force-stop', pkg)
    adb('shell', 'am', 'start', '-n', pkg + '/.MainActivity')

root = open_page()
(out / 'final.png').write_bytes(adb('exec-out', 'screencap', '-p'))
(out / 'final.xml').write_bytes(ET.tostring(root))
passed('Original conversation and its grants preserved; test sessions removed')
report = dict(checks=checks, count=len(checks), android_serial=args.serial,
    apk_sha256=hashlib.sha256((args.out / 'collie.apk').read_bytes()).hexdigest())
(out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
