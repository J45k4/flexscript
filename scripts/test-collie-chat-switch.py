#!/usr/bin/env python3
"""Stress cached chat switching, input ordering and native tree consistency.

Uses only generated private data. A private Wayland session is optional; absent
that, run the same application through SDL's dummy backend. Timing is a bounded
responsiveness regression, not a hardware input-to-display benchmark.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--package', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--session', type=Path)
a = p.parse_args()
package = a.package.resolve()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)
data = out / 'data'
ids = [1, 3, 4, 5, 6, 7]
panels = []
for i, id in enumerate(ids):
    sid = f'switch-{i}'
    folder = data / 'sessions' / sid
    (folder / 'files').mkdir(parents=True)
    text = f'## Chat {i}\n\nHäät 中文 👋 with **formatting** and [a link](example.txt).\n\n' + ('A bounded transcript paragraph.\n\n' * 24)
    messages = [dict(role='user', content=f'Question {i}'), dict(role='assistant', content=text)]
    (folder / 'session.json').write_text(json.dumps(dict(messages=messages, archive=messages,
        cards=[dict(kind=m['role'], text=m['content']) for m in messages], navigation=dict(page='chat', draft=f'draft-{i}'))))
    panels.append(dict(id=id, kind='chat', title=f'Chat {i}', session_id=sid))
(data / 'settings.json').write_text(json.dumps(dict(current='switch-0', model='gpt-6.1-sol')))
(data / 'workspaces').mkdir()
(data / 'workspaces' / 'desktop.json').write_text(json.dumps(dict(version=1, next=7,
    focused=1, root=dict(id=2, tabs=ids, active=1), panels=panels, side='chats')))
fixture = out / 'fixture.json'
fixture.write_text('[]')
events = []
for i in range(120):
    id = ids[i % len(ids)]
    events.append(dict(at=250, request=dict(action='event', event=dict(
        key=f'workspace-tab-{id}', action='workspace_tab', action_id=id, type='click'))))
# Input immediately following the burst must flush the last selection first.
events += [dict(at=251, request=dict(action='native_key', code=4, modifiers=64)),
           dict(at=252, request=dict(action='native_text', text='typed into latest chat'))]
script = out / 'events.json'
script.write_text(json.dumps(events))
state_path = out / 'state.json'
layout_path = out / 'layout.json'
loop_path = out / 'loop.json'
window_path = out / 'window.json'
env = dict(os.environ, COLLIE_HEADLESS='1', COLLIE_TRACE_UI='1', SHELL='/bin/sh', ENV='/dev/null')
if a.session:
    import stat
    session = json.loads(a.session.read_text())
    runtime = Path(session['XDG_RUNTIME_DIR'])
    assert runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
    assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime / session['WAYLAND_DISPLAY']).stat().st_mode)
    env.update(session, FLEX_GUI_BACKEND='wayland')
    env.pop('SDL_VIDEODRIVER', None)
    env.pop('SDL_VIDEO_DRIVER', None)
else:
    env.update(FLEX_GUI_BACKEND='sdl2', SDL_VIDEODRIVER='dummy')
env.pop('DISPLAY', None)

start = time.monotonic()
with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
    app = subprocess.Popen([str(package / 'collie'), '--run-ms', '4000', '--width', '1280', '--height', '800',
        '--data', str(data), '--fixture', str(fixture), '--events', str(script), '--dump-state', str(state_path),
        '--dump-layout', str(layout_path), '--dump-loop', str(loop_path), '--dump-window', str(window_path), '--capture', str(out / 'capture.rgba')],
        cwd=ROOT, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
    peak_rss = 0
    try:
        while app.poll() is None and time.monotonic() - start < 12:
            try:
                line = next(x for x in Path(f'/proc/{app.pid}/status').read_text().splitlines() if x.startswith('VmRSS:'))
                peak_rss = max(peak_rss, int(line.split()[1]) * 1024)
            except (OSError, StopIteration):
                pass
            if peak_rss > 1024 ** 3:
                break
            time.sleep(.025)
    finally:
        if app.poll() is None:
            os.killpg(app.pid, signal.SIGTERM)
            app.wait(timeout=5)
wall = time.monotonic() - start
assert app.returncode == 0, (app.returncode, (out / 'stderr.log').read_text()[-2000:])
state = json.loads(state_path.read_text())
assert state['chat_active'] == ids[-1], state['chat_active']
for i, panel in enumerate(state['workspace']['panels']):
    assert not panel['chat'].get('notice'), panel['chat'].get('notice')
    expected = 'typed into latest chat' if panel['id'] == ids[-1] else f'draft-{ids.index(panel["id"])}'
    assert panel['chat']['draft'] == expected, (panel['id'], panel['chat']['draft'])
    saved = json.loads((data / 'sessions' / panel['session_id'] / 'session.json').read_text())
    assert saved['navigation']['draft'] == expected, (panel['id'], saved['navigation'])
rows = []
for line in (out / 'stderr.log').read_text().splitlines():
    if line.startswith('{'):
        row = json.loads(line)
        if row.get('trace') == 'ui-update':
            rows.append(row)
assert sum(r['event'] == 'workspace_tab' for r in rows) == 1, 'Superseded tab views were rendered'
assert max(r['queued_bytes'] for r in rows) < 32768, 'Focus/navigation commands accumulated'
assert 'Too many pending desktop commands' not in (out / 'stderr.log').read_text()
assert wall < 9, ('Chat switching starved shutdown', wall)
# Structural updates must match a fresh declarative render, including old
# descendants removed when the active chat changes.
request = dict(state=state, action='update', reset=True)
fresh = json.loads(subprocess.check_output([str(package / 'ui-host')], input=json.dumps(request).encode(), timeout=10))
expected = set()
def visit(node, hidden=False):
    hidden = hidden or node.get('hidden', False)
    if not hidden:
        expected.add(node['key'])
    for child in node.get('children', []):
        visit(child, hidden)
for op in fresh['ops']:
    visit(op['node'])
live = {r['key'] for r in json.loads(layout_path.read_text())}
assert live == expected, ('Stale native widgets', sorted(live - expected), 'missing', sorted(expected - live))
window = json.loads(window_path.read_text())
assert not a.session or (window['backend'] == 'wayland' and not window['sdl_loaded']), window
assert (out / 'capture.rgba').stat().st_size == window['pixel_width'] * window['pixel_height'] * 4
report = dict(passed=True, backend=window['backend'], requested_tab_switches=120, applied_tab_switches=1,
    wall_seconds=round(wall, 3), peak_rss_bytes=peak_rss, max_queued_bytes=max(r['queued_bytes'] for r in rows),
    latest_input_target=ids[-1], preserved_drafts=len(ids), native_tree_matches_fresh=True)
(out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS rapid chat switching:', json.dumps(report), flush=True)
