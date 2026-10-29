#!/usr/bin/env python3
"""Exercise Ctrl+Left/Right word navigation in a real terminal shell."""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--package', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--session', type=Path, help='Private headless Wayland session')
a = p.parse_args()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
with tempfile.TemporaryDirectory(prefix='terminal-word-', dir=out) as directory:
    work = Path(directory)
    session = work / 'data/sessions/test'
    (session / 'files').mkdir(parents=True)
    (session / 'session.json').write_text('{"messages":[],"cards":[]}')
    (work / 'data/settings.json').write_text('{"current":"test"}')
    (work / 'fixture.json').write_text('[]')
    shell = work / 'shell'
    shell.write_text('#!/bin/sh\nexec /usr/bin/bash --noprofile --norc -i\n')
    shell.chmod(0o700)
    env = dict(os.environ, SHELL=str(shell), ENV='/dev/null', HISTFILE='/dev/null', COLLIE_HEADLESS='1')
    env.pop('DISPLAY', None)
    if a.session:
        info = json.loads(a.session.read_text())
        runtime = Path(info['XDG_RUNTIME_DIR'])
        assert runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
        assert '/' not in info['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime / info['WAYLAND_DISPLAY']).stat().st_mode)
        env.update(info, FLEX_GUI_BACKEND='wayland')
        env.pop('SDL_VIDEODRIVER', None)
        env.pop('SDL_VIDEO_DRIVER', None)
    else:
        env.update(FLEX_GUI_BACKEND='sdl2', SDL_VIDEODRIVER='dummy')
    events = []

    def event(at, action, **fields):
        events.append(dict(at=at, request=dict(action=action, **fields)))

    def probe(at, name):
        event(at, 'native_probe', path=str(out / f'{name}.json'))

    event(100, 'shortcut', shortcut='terminal')
    event(500, 'native_text', text='echo alpha beta gamma')
    probe(1000, 'before')
    # Bash Readline's word motion goes to the start of the previous word or
    # the end of the next. The extra presses check both line boundaries.
    offsets = [-5, -10, -16, -21, -21, -17, -11, -6, 0, 0]
    for i, offset in enumerate(offsets):
        at = 1200 + i * 400
        event(at, 'native_key', code=80 if i < 5 else 79, modifiers=64)
        probe(at + 250, f'step-{i}')
    finish = 1200 + len(offsets) * 400
    event(finish, 'native_key', code=80, modifiers=64)
    event(finish + 200, 'native_text', text='new_')
    event(finish + 400, 'native_key', code=40, modifiers=0)
    (work / 'events.json').write_text(json.dumps(events))
    state_path = work / 'state.json'
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        result = subprocess.run([str(a.package.resolve() / 'collie'), '--data', str(work / 'data'),
            '--fixture', str(work / 'fixture.json'), '--events', str(work / 'events.json'),
            '--run-ms', '9000', '--dump-state', str(state_path), '--dump-loop', str(out / 'loop.json')],
            cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=20)
    assert result.returncode == 0, (result.returncode, (out / 'stderr.log').read_text()[-2000:])
    before = json.loads((out / 'before.json').read_text())
    steps = [json.loads((out / f'step-{i}.json').read_text()) for i in range(len(offsets))]
    assert all(step['terminal_id'] == before['terminal_id'] for step in steps)
    assert all(step['terminal_cursor_y'] == before['terminal_cursor_y'] for step in steps)
    assert all(step['terminal_output_hash'] == before['terminal_output_hash'] for step in steps)
    positions = [step['terminal_cursor_x'] - before['terminal_cursor_x'] for step in steps]
    assert positions == offsets, ('Ctrl+arrow did not move by words', positions, offsets)
    previous = before
    for step, offset, prior_offset in zip(steps, offsets, [0] + offsets[:-1]):
        if offset != prior_offset:
            assert step['metrics'][7] > previous['metrics'][7], 'Moved terminal cursor was not repainted'
        previous = step
    state = json.loads(state_path.read_text())
    terminal = next(p for p in state['workspace']['panels'] if p['kind'] == 'terminal')
    assert '\nalpha beta new_gamma\n' in terminal['output'], terminal['output']
    report = dict(passed=True, backend=before['backend'], offsets=positions,
                  boundary_checks=True, shell_result='alpha beta new_gamma')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS terminal word navigation:', json.dumps(report), flush=True)
