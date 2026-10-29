#!/usr/bin/env python3
"""Exercise terminal editing through actual private Wayland keyboard events."""
import argparse
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--package', type=Path, required=True)
p.add_argument('--session', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--word-navigation', action='store_true', help='Exercise Ctrl+Left and Ctrl+Right')
a = p.parse_args()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
session = json.loads(a.session.read_text())
runtime = Path(session['XDG_RUNTIME_DIR'])
assert runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime / session['WAYLAND_DISPLAY']).stat().st_mode)
with tempfile.TemporaryDirectory(prefix='terminal-wayland-', dir=out) as directory:
    work = Path(directory)
    conversation = work / 'data/sessions/test'
    (conversation / 'files').mkdir(parents=True)
    (conversation / 'session.json').write_text('{"messages":[],"cards":[]}')
    (work / 'data/settings.json').write_text('{"current":"test"}')
    (work / 'fixture.json').write_text('[]')
    shell = work / 'shell'
    shell.write_text('#!/bin/sh\nexec /usr/bin/bash --noprofile --norc -i\n')
    shell.chmod(0o700)
    env = dict(os.environ, **session, FLEX_GUI_BACKEND='wayland', COLLIE_HEADLESS='1',
               COLLIE_TRACE_TERMINAL='1', SHELL=str(shell), ENV='/dev/null', PS1='cursor> ', HISTFILE='/dev/null')
    env.pop('DISPLAY', None)
    env.pop('SDL_VIDEODRIVER', None)
    env.pop('SDL_VIDEO_DRIVER', None)
    subprocess.run(['fcitx5-remote', '-c'], env=env, capture_output=True, check=True, timeout=3)
    ready = work / 'ready.json'
    script = [dict(at=100, request=dict(action='shortcut', shortcut='terminal')),
              dict(at=1000, request=dict(action='native_probe', path=str(ready)))]
    (work / 'events.json').write_text(json.dumps(script))
    state = work / 'state.json'
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        app = subprocess.Popen([str(a.package.resolve() / 'collie'), '--data', str(work / 'data'),
            '--fixture', str(work / 'fixture.json'), '--events', str(work / 'events.json'),
            '--run-ms', '6000', '--width', '1280', '--height', '800', '--capture', str(out / 'screen.rgba'),
            '--dump-state', str(state), '--dump-loop', str(out / 'loop.json')], cwd=ROOT, env=env,
            stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            deadline = time.monotonic() + 8
            while not ready.exists() and app.poll() is None and time.monotonic() < deadline:
                time.sleep(.02)
            assert ready.exists(), 'Terminal did not become ready'
            facts = json.loads(ready.read_text())
            assert facts['focused'] and facts['terminal_id'], facts
            # wtype generates a custom keymap and keycode assignment; this
            # fixture sends the evdev keycodes from an ordinary keyboard map.
            keyboard = work / 'evdev-keyboard'
            subprocess.run(['cc', '-std=gnu11', '-O2', str(ROOT / 'tests/ui/wayland-evdev-keyboard.c'),
                '-o', str(keyboard), '-lwayland-client', '-lxkbcommon'], cwd=ROOT, check=True, timeout=10)
            args = [str(keyboard)]
            if a.word_navigation:
                args.append('--word-navigation')
            subprocess.run(args, cwd=ROOT, env=env, capture_output=True, check=True, timeout=8)
            rc = app.wait(timeout=10)
        finally:
            if app.poll() is None:
                os.killpg(app.pid, signal.SIGTERM)
                app.wait(timeout=5)
    assert rc == 0, (rc, (out / 'stderr.log').read_text()[-2000:])
    panel = next(p for p in json.loads(state.read_text())['workspace']['panels'] if p['kind'] == 'terminal')
    expected = 'alpha beta newgamma' if a.word_navigation else 'abcd'
    assert f'\n{expected}\n' in panel['output'], panel['output']
    rows = [json.loads(line) for line in (out / 'stderr.log').read_text().splitlines() if line.startswith('{')]
    rows = [r for r in rows if r.get('trace') == 'terminal']
    inputs = [r for r in rows if r['event'] == 'input']
    first = 21 if a.word_navigation else 7
    movements = [-5, -5, 4, 6, -5] if a.word_navigation else [-1]
    assert len(inputs) == (30 if a.word_navigation else 12), inputs
    latencies = []
    for i, delta in enumerate(movements):
        left = inputs[first + i]
        frames = [r for r in rows if r['event'] == 'present' and r['id'] == left['id']
                  and r['x'] == left['x'] + delta and left['time_ns'] <= r['time_ns'] < inputs[first + i + 1]['time_ns']]
        assert frames, ('Wayland arrow key did not produce the expected cursor frame', i, delta)
        latencies.append(round((frames[0]['time_ns'] - left['time_ns']) / 1_000_000, 2))
    report = dict(passed=True, backend='wayland', virtual_keyboard=True, shell_result=expected,
                  cursor_movements=movements)
    if not a.word_navigation:
        report['left_input_to_frame_ms'] = latencies[0]
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS Wayland keyboard terminal editing:', json.dumps(report), flush=True)
