#!/usr/bin/env python3
"""Measure terminal-input-handler-to-frame-submission latency with a real PTY and Bash.

Input events use the normalized GUI ABI; a private Wayland display may be used.
These numbers do not measure physical keyboard, compositor, or scanout latency.
"""
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
p.add_argument('--out', type=Path, required=True)
p.add_argument('--session', type=Path, help='Private headless Wayland session')
p.add_argument('--max-latency-ms', type=float, default=300)
a = p.parse_args()
package = a.package.resolve()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
with tempfile.TemporaryDirectory(prefix='terminal-latency-', dir=out) as directory:
    work = Path(directory)
    data = work / 'data'
    ids = [1, 3, 4, 5, 6, 7]
    panels = []
    for i, panel_id in enumerate(ids):
        sid = f'terminal-chat-{i}'
        folder = data / 'sessions' / sid
        (folder / 'files').mkdir(parents=True)
        message = f'Chat {i}: ' + ('A bounded transcript paragraph.\n\n' * 24)
        messages = [dict(role='user', content=f'Question {i}'), dict(role='assistant', content=message)]
        (folder / 'session.json').write_text(json.dumps(dict(messages=messages, archive=messages,
            cards=[dict(kind=m['role'], text=m['content']) for m in messages], navigation=dict(page='chat'))))
        panels.append(dict(id=panel_id, kind='chat', title=f'Chat {i}', session_id=sid))
    (data / 'settings.json').write_text(json.dumps(dict(current='terminal-chat-0', model='gpt-6.1-sol')))
    (data / 'workspaces').mkdir()
    (data / 'workspaces/desktop.json').write_text(json.dumps(dict(version=1, next=7, focused=1,
        root=dict(id=2, tabs=ids, active=1), panels=panels, side='chats')))
    fixture = work / 'fixture.json'
    fixture.write_text('[]')
    shell = work / 'shell'
    shell.write_text('#!/bin/sh\nexec /usr/bin/bash --noprofile --norc -i\n')
    shell.chmod(0o700)
    env = dict(os.environ, SHELL=str(shell), ENV='/dev/null', PS1='cursor> ', HISTFILE='/dev/null',
               COLLIE_HEADLESS='1', COLLIE_TRACE_TERMINAL='1')
    env.pop('DISPLAY', None)
    env.pop('COLLIE_TRACE_UI', None)
    if a.session:
        session = json.loads(a.session.read_text())
        runtime = Path(session['XDG_RUNTIME_DIR'])
        assert runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
        assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime / session['WAYLAND_DISPLAY']).stat().st_mode)
        env.update(session, FLEX_GUI_BACKEND='wayland')
        env.pop('SDL_VIDEODRIVER', None)
        env.pop('SDL_VIDEO_DRIVER', None)
    else:
        env.update(FLEX_GUI_BACKEND='sdl2', SDL_VIDEODRIVER='dummy')
    events = []
    def event(at, action, **fields):
        events.append(dict(at=at, request=dict(action=action, **fields)))
    def key(at, code, modifiers=0):
        event(at, 'native_key', code=code, modifiers=modifiers)

    event(200, 'shortcut', shortcut='terminal')
    event(800, 'native_text', text="printf 'EDIT_RESULT=<%s>\\n' ")
    sample_at = 1200
    sample_count = 12
    for i in range(sample_count):
        event(sample_at + 180 * i, 'native_text', text='x')
    sample_at += 180 * sample_count
    for i in range(sample_count):
        key(sample_at + 180 * i, 80)
    finish = sample_at + 180 * sample_count + 250
    event(finish, 'native_text', text='q')
    key(finish + 150, 8, 64)  # Ctrl+E, end of line.
    for i, char in enumerate('0123456789'):
        event(finish + 300 + i * 8, 'native_text', text=char)
    key(finish + 550, 40)
    script = work / 'events.json'
    script.write_text(json.dumps(events))
    state_path = work / 'state.json'
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        app = subprocess.Popen([str(package / 'collie'), '--data', str(data), '--fixture', str(fixture),
            '--events', str(script), '--run-ms', '10000', '--dump-state', str(state_path),
            '--dump-loop', str(out / 'loop.json')], cwd=ROOT, env=env, stdout=stdout, stderr=stderr,
            start_new_session=True)
        started = time.monotonic()
        peak_rss = 0
        try:
            while app.poll() is None and time.monotonic() - started < 25:
                try:
                    line = next(line for line in Path(f'/proc/{app.pid}/status').read_text().splitlines()
                                if line.startswith('VmRSS:'))
                    peak_rss = max(peak_rss, int(line.split()[1]) * 1024)
                except (OSError, StopIteration):
                    pass
                if peak_rss > 1024 ** 3:
                    break
                time.sleep(.025)
        finally:
            if app.poll() is None:
                os.killpg(app.pid, signal.SIGTERM)
                try:
                    app.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(app.pid, signal.SIGKILL)
                    app.wait(timeout=3)
    assert app.returncode == 0, (app.returncode, peak_rss, (out / 'stderr.log').read_text()[-2000:])
    state = json.loads(state_path.read_text())
    terminal = next(panel for panel in state['workspace']['panels'] if panel['kind'] == 'terminal')
    assert 'EDIT_RESULT=<qxxxxxxxxxxxx0123456789>' in terminal['output'], terminal['output']
    rows = []
    for line in (out / 'stderr.log').read_text().splitlines():
        if line.startswith('{'):
            row = json.loads(line)
            if row.get('trace') == 'terminal':
                rows.append(row)
    inputs = [r for r in rows if r['event'] == 'input']
    assert len(inputs) == 1 + 2 * sample_count + 13, len(inputs)
    samples = {'typing': [], 'left': []}
    for i, entry in enumerate(inputs[1:1 + 2 * sample_count]):
        group = 'typing' if i < sample_count else 'left'
        expected = entry['x'] + (1 if group == 'typing' else -1)
        next_input = inputs[i + 2]['time_ns']
        frames = [r for r in rows if r['event'] == 'present' and r['id'] == entry['id']
                  and r['x'] == expected and r['y'] == entry['y']
                  and entry['time_ns'] <= r['time_ns'] < next_input]
        assert frames, (group, i, 'no matching terminal frame before next key')
        latency = (frames[0]['time_ns'] - entry['time_ns']) / 1_000_000
        samples[group].append(latency)
    # The burst is faster than the terminal's frame cadence. Its last screen
    # update must be emitted even after the PTY stops producing new bytes.
    final_x = inputs[1]['x'] + sample_count + 1 + 10
    burst_frame = [r for r in rows if r['event'] == 'present' and r['id'] == inputs[-1]['id']
                   and r['x'] == final_x and inputs[-2]['time_ns'] <= r['time_ns'] < inputs[-1]['time_ns']]
    assert burst_frame and inputs[-1]['x'] == final_x, 'Final coalesced burst update was not presented'
    def stats(values):
        values = sorted(values)
        return dict(count=len(values), median_ms=round((values[5] + values[6]) / 2, 2),
                    p95_ms=round(values[-1], 2), max_ms=round(max(values), 2))
    measured = {key: stats(value) for key, value in samples.items()}
    assert max(row['max_ms'] for row in measured.values()) < a.max_latency_ms, measured
    loop = json.loads((out / 'loop.json').read_text())
    report = dict(passed=True, backend=loop['backend'], open_chats=len(ids),
                  latency_scope='terminal input handler to frame submission', samples=measured, peak_rss_bytes=peak_rss,
                  burst_characters=10, burst_final_frame=True, shell_result='qxxxxxxxxxxxx0123456789')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS terminal latency:', json.dumps(report), flush=True)
