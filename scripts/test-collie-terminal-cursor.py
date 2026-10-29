#!/usr/bin/env python3
"""Check shell editing AND cursor-only terminal repaints in the real GUI host."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--package', type=Path, required=True)
p.add_argument('--binary', type=Path, help='Override only the GUI executable for a before/after check')
p.add_argument('--out', type=Path, required=True)
p.add_argument('--session', type=Path, help='Private headless Wayland session')
a = p.parse_args()
package = a.package.resolve()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
with tempfile.TemporaryDirectory(prefix='terminal-cursor-', dir=out) as directory:
    work = Path(directory)
    session = work / 'data/sessions/test'
    (session / 'files').mkdir(parents=True)
    (session / 'session.json').write_text('{"messages":[],"cards":[]}')
    (work / 'data/settings.json').write_text('{"current":"test"}')
    fixture = work / 'fixture.json'
    fixture.write_text('[]')
    # Real readline, with no user startup scripts/history or model requests.
    shell = work / 'shell'
    shell.write_text('#!/bin/sh\nexec /usr/bin/bash --noprofile --norc -i\n')
    shell.chmod(0o700)
    env = dict(os.environ, SHELL=str(shell), ENV='/dev/null', PS1='cursor> ',
               HISTFILE='/dev/null', COLLIE_HEADLESS='1')
    env.pop('DISPLAY', None)
    if a.session:
        env.update(json.loads(a.session.read_text()), FLEX_GUI_BACKEND='wayland')
        env.pop('SDL_VIDEODRIVER', None)
        env.pop('SDL_VIDEO_DRIVER', None)
    else:
        env.update(FLEX_GUI_BACKEND='sdl2', SDL_VIDEODRIVER='dummy')
    events = []

    def event(at, action, **fields):
        events.append(dict(at=at, request=dict(action=action, **fields)))

    def key(at, code):
        event(at, 'native_key', code=code, modifiers=0)

    def probe(at, name):
        event(at, 'native_probe', path=str(out / f'{name}.json'))

    event(100, 'shortcut', shortcut='terminal')
    event(500, 'native_text', text="printf 'EDIT_RESULT=<%s>\\n' ac")
    probe(1000, 'before')
    key(1200, 80)  # Left: screen contents unchanged, cursor moves one column.
    probe(1600, 'left')
    key(1800, 79)  # Right: same screen contents, cursor returns.
    probe(2200, 'right')
    probe(2600, 'idle')
    key(2800, 80)
    event(3000, 'native_text', text='b')
    key(3200, 79)
    event(3400, 'native_text', text='d')
    key(3600, 40)
    script = work / 'events.json'
    script.write_text(json.dumps(events))
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        binary = a.binary.resolve() if a.binary else package / 'collie'
        result = subprocess.run([str(binary), '--data', str(work / 'data'),
            '--fixture', str(fixture), '--events', str(script), '--run-ms', '4300',
            '--dump-loop', str(out / 'loop.json'), '--dump-state', str(work / 'state.json')],
            cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=15)
    assert result.returncode == 0, (result.returncode, (out / 'stderr.log').read_text()[-2000:])
    snapshots = [json.loads((out / f'{name}.json').read_text()) for name in ('before', 'left', 'right', 'idle')]
    before, left, right, idle = snapshots
    assert all(row['terminal_id'] == before['terminal_id'] for row in snapshots)
    assert left['terminal_cursor_x'] == before['terminal_cursor_x'] - 1
    assert right['terminal_cursor_x'] == before['terminal_cursor_x']
    assert all(row['terminal_cursor_y'] == before['terminal_cursor_y'] for row in snapshots)
    assert all(row['terminal_output_hash'] == before['terminal_output_hash'] for row in snapshots)
    assert left['metrics'][7] > before['metrics'][7], 'Left moved the shell cursor without repainting it'
    assert right['metrics'][7] > left['metrics'][7], 'Right moved the shell cursor without repainting it'
    assert idle['metrics'][7] == right['metrics'][7], 'Idle terminal unexpectedly keeps repainting'
    state = json.loads((work / 'state.json').read_text())
    terminal = next(panel for panel in state['workspace']['panels'] if panel['kind'] == 'terminal')
    assert 'EDIT_RESULT=<abcd>' in terminal['output'], terminal['output']
    report = dict(passed=True, backend=before['backend'], cursor_columns=[row['terminal_cursor_x'] for row in snapshots],
                  presents=[row['metrics'][7] for row in snapshots], unchanged_screen_text=True, shell_result='abcd')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS terminal cursor:', json.dumps(report), flush=True)
