#!/usr/bin/env python3
"""Ensure a closed PTY does not keep Collie's idle service busy."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--package', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=False)

def children(pid):
    try:
        return [int(pid) for pid in Path(f'/proc/{pid}/task/{pid}/children').read_text().split()]
    except FileNotFoundError:
        return []

def ticks(pid):
    fields = Path(f'/proc/{pid}/stat').read_text().split()
    return int(fields[13]) + int(fields[14])

with tempfile.TemporaryDirectory(prefix='terminal-wait-', dir=out) as directory:
    work = Path(directory)
    session = work / 'data/sessions/test'
    (session / 'files').mkdir(parents=True)
    (session / 'session.json').write_text('{"messages":[],"cards":[]}')
    (work / 'data/settings.json').write_text('{"current":"test"}')
    (work / 'fixture.json').write_text('[]')
    # The process stays alive after closing every PTY slave descriptor. Polling
    # its master must not spin on POLLHUP while the child is still running.
    shell = work / 'shell'
    shell.write_text("#!/bin/sh\nexec /bin/sh -c 'exec 0<&- 1>&- 2>&-; exec sleep 4'\n")
    shell.chmod(0o700)
    events = [dict(at=100, request=dict(action='shortcut', shortcut='terminal'))]
    (work / 'events.json').write_text(json.dumps(events))
    env = dict(os.environ, SHELL=str(shell), ENV='/dev/null', COLLIE_HEADLESS='1',
               FLEX_GUI_BACKEND='sdl2', SDL_VIDEODRIVER='dummy')
    env.pop('DISPLAY', None)
    env.pop('WAYLAND_DISPLAY', None)
    state_path = work / 'state.json'
    with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
        app = subprocess.Popen([str(a.package.resolve() / 'collie'), '--data', str(work / 'data'),
            '--fixture', str(work / 'fixture.json'), '--events', str(work / 'events.json'),
            '--run-ms', '5500', '--dump-state', str(state_path)], cwd=ROOT, env=env,
            stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            deadline = time.monotonic() + 3
            service = 0
            terminal = 0
            while time.monotonic() < deadline and app.poll() is None:
                app_children = children(app.pid)
                if app_children:
                    service = app_children[0]
                    for pid in children(service):
                        cmdline = Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ')
                        if cmdline.startswith(b'sleep '):
                            terminal = pid
                            break
                if terminal:
                    break
                time.sleep(.025)
            assert terminal, 'Closed-PTY fixture did not start'
            assert not any((Path(f'/proc/{terminal}/fd') / str(i)).exists() for i in (0, 1, 2))
            time.sleep(.1)  # Allow the service to observe the first PTY HUP.
            start = ticks(service)
            time.sleep(1.2)
            cpu_seconds = (ticks(service) - start) / os.sysconf('SC_CLK_TCK')
            rc = app.wait(timeout=10)
        finally:
            if app.poll() is None:
                os.killpg(app.pid, signal.SIGTERM)
                app.wait(timeout=5)
    assert rc == 0, (rc, (out / 'stderr.log').read_text()[-2000:])
    state = json.loads(state_path.read_text())
    panel = next(p for p in state['workspace']['panels'] if p['kind'] == 'terminal')
    assert panel['exited'], 'Terminal exit was not reported'
    assert cpu_seconds < .5, ('Service spun after PTY HUP', cpu_seconds)
    report = dict(passed=True, closed_slave_fds=True, child_exited=True,
                  sample_seconds=1.2, service_cpu_seconds=round(cpu_seconds, 3))
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS terminal idle and exit:', json.dumps(report), flush=True)
