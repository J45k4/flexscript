#!/usr/bin/env python3
"""Full Collie settled idle/caret CPU and memory on a private compositor only.

Python is independent orchestration, never application implementation. Snapshot
events use the normal replay deadlines. No sampler thread runs inside Collie.
Context switches and loop iterations are wake proxies, not kernel wake tracing.
"""
import argparse, hashlib, json, os, random, signal, stat, statistics, struct, subprocess, time, zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--collie', type=Path, required=True)
p.add_argument('--focus', type=Path, required=True)
p.add_argument('--session', type=Path, required=True)
p.add_argument('--swaymsg', type=Path, required=True)
p.add_argument('--seconds', type=int, default=60)
p.add_argument('--runs', type=int, default=1)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
assert 2 <= a.seconds <= 600 and 1 <= a.runs <= 7
session = json.loads(a.session.read_text())
runtime = Path(session['XDG_RUNTIME_DIR'])
assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid == os.getuid()
assert stat.S_IMODE(runtime.stat().st_mode) == 0o700
assert '/' not in session['WAYLAND_DISPLAY']
assert stat.S_ISSOCK((runtime / session['WAYLAND_DISPLAY']).stat().st_mode)
env = dict(os.environ, **session, COLLIE_HEADLESS='1', SDL_VIDEODRIVER='wayland',
           SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0')
for key in ['DISPLAY', 'SDL_VIDEO_DRIVER', 'FLEX_GUI_BACKEND']:
    env.pop(key, None)
out = a.out.resolve()
out.mkdir(parents=True, exist_ok=True)

def ipc(*args):
    r = subprocess.run([str(a.swaymsg.resolve()), '-r', *args], env=env,
                       capture_output=True, text=True, check=True, timeout=5)
    rows = json.loads(r.stdout)
    if isinstance(rows, list):
        assert all(row.get('success', True) for row in rows), rows
    return rows

def nodes(tree):
    yield tree
    for child in tree.get('nodes', []) + tree.get('floating_nodes', []):
        yield from nodes(child)

def window_state(pid):
    tree = ipc('-t', 'get_tree')
    found = [n for n in nodes(tree) if n.get('pid') == pid]
    assert len(found) == 1, ('Expected one private window', pid, found)
    n = found[0]
    workspaces = [w for w in nodes(tree) if w.get('type') == 'workspace'
                  and any(child.get('id') == n['id'] for child in nodes(w))]
    assert len(workspaces) == 1, 'Window is not on a normal workspace'
    workspace = next(w for w in ipc('-t', 'get_workspaces') if w['id'] == workspaces[0]['id'])
    assert workspace['visible'] and n['rect']['width'] > 0 and n['rect']['height'] > 0, 'Window is not visible'
    return dict(workspace=workspace['name'], workspace_visible=workspace['visible'],
                **{k: n.get(k) for k in ['id', 'pid', 'name', 'focused', 'rect', 'type']})

def read_json(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None

def wait_json(path, process, seconds=15):
    until = time.monotonic() + seconds
    while process.poll() is None and time.monotonic() < until:
        row = read_json(path)
        if row is not None:
            return row
        time.sleep(.01)
    raise AssertionError(('Private child readiness/snapshot failed', str(path), process.poll()))

def process_stat(pid):
    text = Path(f'/proc/{pid}/stat').read_text()
    fields = text[text.rfind(')') + 2:].split()
    return dict(pid=pid, start_ticks=int(fields[19]),
                cpu_ticks=int(fields[11]) + int(fields[12]))

def status(path):
    result = {}
    for line in path.read_text().splitlines():
        key, _, value = line.partition(':')
        if key in ['Rss', 'Pss', 'Private_Clean', 'Private_Dirty', 'VmHWM',
                   'voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches']:
            result[key] = int(value.split()[0])
    return result

def processes(pid):
    row = process_stat(pid)
    row.update(status(Path(f'/proc/{pid}/smaps_rollup')))
    row.update(status(Path(f'/proc/{pid}/status')))
    row['executable'] = str(Path(f'/proc/{pid}/exe').resolve())
    row['threads'] = {task.name: status(task / 'status') for task in Path(f'/proc/{pid}/task').iterdir()}
    result = [row]
    children = Path(f'/proc/{pid}/task/{pid}/children').read_text().split()
    for child in children:
        result.extend(processes(int(child)))
    return result

def snapshot(pid):
    before = time.monotonic_ns()
    rows = processes(pid)
    return dict(begin_ns=before, end_ns=time.monotonic_ns(), processes=rows,
                rss_kib=sum(r['Rss'] for r in rows), pss_kib=sum(r['Pss'] for r in rows))

def stop(child):
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=5)

def delta(first, last):
    by_pid = {r['pid']: r for r in first['processes']}
    assert set(by_pid) == {r['pid'] for r in last['processes']}, 'Measured process tree changed'
    ticks = voluntary = involuntary = 0
    for row in last['processes']:
        old = by_pid[row['pid']]
        assert row['start_ticks'] == old['start_ticks'], 'Measured PID was reused'
        assert set(row['threads']) == set(old['threads']), 'Measured thread set changed'
        ticks += row['cpu_ticks'] - old['cpu_ticks']
        for tid, values in row['threads'].items():
            voluntary += values['voluntary_ctxt_switches'] - old['threads'][tid]['voluntary_ctxt_switches']
            involuntary += values['nonvoluntary_ctxt_switches'] - old['threads'][tid]['nonvoluntary_ctxt_switches']
    return dict(group_cpu_ns=ticks * 1_000_000_000 / os.sysconf('SC_CLK_TCK'),
                group_voluntary_context_switches=voluntary,
                group_involuntary_context_switches=involuntary,
                rss_delta_kib=last['rss_kib'] - first['rss_kib'],
                pss_delta_kib=last['pss_kib'] - first['pss_kib'])

ipc('for_window [title="^Idle focus sink$"] floating enable')
reports = []
metadata = dict(seconds=a.seconds, runs=a.runs, full_idle_acceptance=False,
                physical_desktop=False, kernel_wakeups_measured=False,
                memory_lifetime_acceptance=False,
                collie_sha256=hashlib.sha256(a.collie.resolve().read_bytes()).hexdigest(),
                focus_sha256=hashlib.sha256(a.focus.resolve().read_bytes()).hexdigest(),
                source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                    for name in ['apps/collie/desktop/probe.flex', 'apps/collie/desktop/main.flex',
                                 'libs/gui/draw.flex', 'libs/gui/text/bitmap-size.flex',
                                 'tests/ui/idle-focus.flex', 'scripts/test-collie-idle.py',
                                 'scripts/test-wayland-ime-session.py']},
                boundary='settled snapshot endpoints; process CPU clocks, /proc PSS/RSS, all app/service thread context switches; no GPU residency measurement')
for case in ['unfocused', 'caret']:
    for run in range(a.runs):
        order = ['sdl2', 'wayland'] if run % 2 == 0 else ['wayland', 'sdl2']
        for backend in order:
            directory = out / f'{case}-{run}-{backend}'
            directory.mkdir(exist_ok=True)
            data = directory / 'data'
            conversation = data / 'sessions/conversation-0'
            (conversation / 'files').mkdir(parents=True, exist_ok=True)
            messages = [dict(role='user', content='Settled idle ä中👋'),
                        dict(role='assistant', content='## Idle measurement\n\nKeep this **conversation** unchanged.\n\n| Case | Result |\n| --- | --- |\n| Unicode | ä中👋 |\n| Native | mapped |\n\n[Local link](idle.txt) and `code`.')]
            (conversation / 'session.json').write_text(json.dumps(dict(messages=messages, archive=messages,
                cards=[dict(kind=m['role'], text=m['content']) for m in messages])))
            (data / 'settings.json').write_text(json.dumps(dict(current='conversation-0')))
            fixture = directory / 'fixture.json'
            fixture.write_text('[]')
            ready_path = directory / 'mapped.json'
            ready_path.unlink(missing_ok=True)
            start_path, end_path = directory / 'start.json', directory / 'end.json'
            start_path.unlink(missing_ok=True)
            end_path.unlink(missing_ok=True)
            events = [dict(at=1000, request=dict(action='native_probe', path=str(ready_path))),
                      dict(at=5000, request=dict(action='native_probe', path=str(start_path))),
                      dict(at=5000 + a.seconds * 1000, request=dict(action='native_probe', path=str(end_path)))]
            event_path = directory / 'events.json'
            event_path.write_text(json.dumps(events))
            app = sink = keyboard = None
            with (directory / 'stdout.log').open('wb') as stdout, (directory / 'stderr.log').open('wb') as stderr:
                try:
                    # A headless seat has no hardware keyboard. Keep a real
                    # virtual device connected for the entire case so both
                    # backends receive keyboard enter/leave, without typing.
                    keyboard = subprocess.Popen(['wtype', '-s', str((a.seconds + 30) * 1000)],
                        env=env, cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
                    time.sleep(.15)
                    assert keyboard.poll() is None, 'Persistent private keyboard did not start'
                    args = [str(a.collie.resolve()), '--fixture', str(fixture), '--data', str(data),
                        '--width', '1280', '--height', '800', '--run-ms', str((a.seconds + 9) * 1000),
                        '--events', str(event_path), '--dump-loop', str(directory / 'loop.json'),
                        '--dump-window', str(directory / 'window.json'), '--dump-state', str(directory / 'state.json')]
                    if run == 0:
                        args += ['--capture', str(directory / 'capture.rgba')]
                    app = subprocess.Popen(args,
                        env=dict(env, FLEX_GUI_BACKEND=backend), cwd=ROOT, stdout=stdout, stderr=stderr, start_new_session=True)
                    until = time.monotonic() + 4
                    while time.monotonic() < until:
                        try:
                            state = window_state(app.pid)
                            break
                        except AssertionError:
                            assert app.poll() is None, 'Collie exited during startup'
                            time.sleep(.02)
                    else:
                        raise AssertionError('Collie did not map')
                    mapped = wait_json(ready_path, app, 4)
                    assert mapped['focused'] and mapped['caret_animated'], ('Initial real keyboard focus was not delivered', mapped)
                    assert mapped['gpu_renderer'] and not any(s in mapped['gpu_renderer'].lower() for s in ['llvmpipe', 'softpipe', 'software']), mapped
                    assert backend != 'sdl2' or (mapped['renderer'] == 'opengl' and mapped['renderer_flags'] & 2), 'SDL must use the accelerated OpenGL baseline'
                    if case == 'unfocused':
                        ready = directory / 'focus-ready.json'
                        ready.unlink(missing_ok=True)
                        sink = subprocess.Popen([str(a.focus.resolve()), str(ready)], env=env, cwd=ROOT,
                            stdout=stdout, stderr=stderr, start_new_session=True)
                        wait_json(ready, sink, 4)
                    else:
                        ipc(f'[con_id={state["id"]}] focus')
                    first = wait_json(start_path, app)
                    first_os = snapshot(app.pid)
                    (directory / 'start-os.json').write_text(json.dumps(first_os, indent=2) + '\n')
                    maps = Path(f'/proc/{app.pid}/maps').read_text()
                    (directory / 'process-maps.txt').write_text(maps)
                    assert ('libSDL2' in maps) == (backend == 'sdl2'), 'Unexpected SDL dependency'
                    tree_start = window_state(app.pid)
                    assert first['focused'] == (case == 'caret') and first['caret_animated'] == (case == 'caret'), first
                    assert tree_start['focused'] == first['focused'], tree_start
                    samples = [first_os]
                    until = time.monotonic() + a.seconds + 10
                    next_sample = time.monotonic() + 5
                    while app.poll() is None and time.monotonic() < until:
                        last = read_json(end_path)
                        if last is not None:
                            break
                        if time.monotonic() >= next_sample:
                            samples.append(snapshot(app.pid))
                            next_sample += 5
                        time.sleep(.02)
                    else:
                        raise AssertionError(('Idle endpoint missing', app.poll()))
                    last_os = snapshot(app.pid)
                    samples.append(last_os)
                    (directory / 'end-os.json').write_text(json.dumps(last_os, indent=2) + '\n')
                    (directory / 'memory-samples.json').write_text(json.dumps(samples, indent=2) + '\n')
                    tree_end = window_state(app.pid)
                    assert last['focused'] == first['focused'] and last['caret_animated'] == first['caret_animated'], last
                    assert tree_end['focused'] == tree_start['focused'], tree_end
                    elapsed = last['monotonic_ns'] - first['monotonic_ns']
                    assert a.seconds * 1e9 - 50e6 <= elapsed <= a.seconds * 1e9 + 200e6, elapsed
                    assert all(last[k] == first[k] for k in ['width', 'height', 'pixel_width', 'pixel_height', 'scale', 'focus_key', 'gpu_renderer']), 'Viewport/focus/GPU changed'
                    counters = [b - x for x, b in zip(first['metrics'], last['metrics'])]
                    if case == 'unfocused':
                        assert all(counters[i] == 0 for i in [0, 1, 2, 3, 4, 6, 7]), ('Unfocused app performed render/upload work', backend, counters)
                        if backend == 'wayland':
                            assert last['draw_batches'] == first['draw_batches'], 'Native idle submitted draw batches'
                    else:
                        assert max(1, a.seconds * 2 - 3) <= counters[7] <= a.seconds * 2 + 3, ('Caret missed blink or redraws excessively', counters)
                    if backend == 'wayland':
                        for key in ['texture_count', 'texture_storage_bytes', 'atlas_pages', 'atlas_storage_bytes', 'shape_cache_bytes', 'shape_transient_bytes']:
                            assert last.get(key) == first.get(key), ('Idle cache grew', key, first, last)
                    row = dict(case=case, run=run, backend=backend, elapsed_ns=elapsed,
                        ui_process_cpu_ns=last['process_cpu_ns'] - first['process_cpu_ns'],
                        ui_thread_cpu_ns=last['thread_cpu_ns'] - first['thread_cpu_ns'],
                        iterations=last['iterations'] - first['iterations'],
                        counter_delta=counters, first=first, last=last,
                        first_os=first_os, last_os=last_os, memory_samples=samples,
                        observed_peak_rss_kib=max(s['rss_kib'] for s in samples),
                        observed_peak_pss_kib=max(s['pss_kib'] for s in samples),
                        compositor_start=tree_start, compositor_end=tree_end, **delta(first_os, last_os))
                    (directory / 'measurement.json').write_text(json.dumps(row, indent=2) + '\n')
                    assert app.wait(timeout=12) == 0, 'Collie failed at normal shutdown'
                    window = json.loads((directory / 'window.json').read_text())
                    assert window['backend'] == backend and window['sdl_loaded'] == (backend == 'sdl2'), window
                    state = json.loads((directory / 'state.json').read_text())
                    assert state['page'] == 'chat' and state['draft'] == '', 'Fixture state changed'
                    if run == 0:
                        w, h = window['pixel_width'], window['pixel_height']
                        raw = (directory / 'capture.rgba').read_bytes()
                        assert len(raw) == w * h * 4
                        def chunk(tag, payload):
                            return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff)
                        scan = b''.join(b'\0' + raw[y*w*4:(y+1)*w*4] for y in range(h))
                        (directory / 'capture.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(scan)) + chunk(b'IEND', b''))
                    reports.append(row)
                    (out / 'report.json').write_text(json.dumps(dict(**metadata, rows=reports), indent=2) + '\n')
                    print(f'PASS settled {case} {run+1}/{a.runs} {backend}: {elapsed/1e9:.3f}s, UI CPU {row["ui_process_cpu_ns"]/1e6:.3f}ms, iterations {row["iterations"]}, presents {counters[7]}, PSS {first_os["pss_kib"]}->{last_os["pss_kib"]} KiB', flush=True)
                finally:
                    stop(app)
                    if sink is not None and sink.poll() is None:
                        ipc('[title="^Idle focus sink$"] kill')
                        try:
                            sink.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            stop(sink)
                    stop(keyboard)

for case in ['unfocused', 'caret']:
    for run in range(a.runs):
        pair = {r['backend']: r for r in reports if r['case'] == case and r['run'] == run}
        assert all(pair['sdl2']['first'][k] == pair['wayland']['first'][k] for k in ['width', 'height', 'pixel_width', 'pixel_height', 'scale', 'focus_key', 'gpu_renderer']), 'Paired geometry/focus/GPU mismatch'
summary = []
for case in ['unfocused', 'caret']:
    rows = [r for r in reports if r['case'] == case]
    result = dict(case=case, backends={}, paired_differences={})
    measures = dict(ui_cpu_ns_per_second=lambda r: r['ui_process_cpu_ns'] * 1e9 / r['elapsed_ns'],
                    group_cpu_ns_per_second=lambda r: r['group_cpu_ns'] * 1e9 / r['elapsed_ns'],
                    group_voluntary_context_switches_per_second=lambda r: r['group_voluntary_context_switches'] * 1e9 / r['elapsed_ns'],
                    warm_pss_kib=lambda r: r['first_os']['pss_kib'],
                    warm_rss_kib=lambda r: r['first_os']['rss_kib'])
    for backend in ['sdl2', 'wayland']:
        selected = [r for r in rows if r['backend'] == backend]
        result['backends'][backend] = {key: dict(per_run=[fn(r) for r in selected], median=statistics.median(fn(r) for r in selected)) for key, fn in measures.items()}
    for key, fn in measures.items():
        differences = []
        for run in range(a.runs):
            pair = {r['backend']: r for r in rows if r['run'] == run}
            differences.append(fn(pair['wayland']) - fn(pair['sdl2']))
        rng = random.Random(81729)
        estimates = sorted(statistics.mean(rng.choices(differences, k=len(differences))) for _ in range(10000))
        result['paired_differences'][key] = dict(native_minus_sdl=differences, mean=statistics.mean(differences),
            bootstrap_95_low=estimates[249], bootstrap_95_high=estimates[9749],
            uncertainty_qualified=a.runs >= 7)
    summary.append(result)
(out / 'report.json').write_text(json.dumps(dict(**metadata, rows=reports, summary=summary), indent=2) + '\n')
print('Saved private full-Collie idle/memory evidence; kernel wake tracing and lifetime/active-memory acceptance remain unproven.', flush=True)
