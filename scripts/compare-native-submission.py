#!/usr/bin/env python3
"""Query-free native A/B control; not an SDL release qualification run."""
import argparse, hashlib, json, os, random, resource, stat, statistics, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
for name in ['before', 'after', 'session', 'out']: p.add_argument('--'+name, type=Path, required=True)
p.add_argument('--runs', type=int, default=7)
p.add_argument('--samples', type=int, default=160)
p.add_argument('--context-versions', nargs=2, help='Require actual before/after GL versions and identical EGL buffer settings')
p.add_argument('--scenes', nargs='+', choices=['scroll','selection','stream','navigation','typing'], default=['scroll','selection','typing'])
p.add_argument('--measure-reuse-control', action='store_true', help='Require disabled/enabled layout reuse and reduced measurement counts')
p.add_argument('--direct-copy-control', action='store_true', help='Require round-trip/direct model copies and unchanged measurement counts')
a = p.parse_args()
assert a.runs >= 7 and 20 <= a.samples <= 10000 and a.runs*a.samples >= 1000
assert not (a.measure_reuse_control and a.direct_copy_control), 'Select one implementation control at a time'
assert 'selection' in a.scenes and len(set(a.scenes)) == len(a.scenes), 'Keep the selection pixel-equivalence control and unique scenes'
session = json.loads(a.session.read_text()); runtime = Path(session['XDG_RUNTIME_DIR'])
assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, **session, FLEX_GUI_BACKEND='wayland', SDL_VIDEODRIVER='wayland', SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0'); env.pop('DISPLAY', None)
available = os.sched_getaffinity(0); cpu = 3 if 3 in available else min(available)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def host_context():
    def read(path):
        try: return Path(path).read_text().strip()
        except OSError: return None
    counters = next((line for line in Path('/proc/stat').read_text().splitlines() if line.startswith(f'cpu{cpu} ')), None)
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return dict(cpu_stat=counters, frequency_khz=read(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq'),
        governor=read(f'/sys/devices/system/cpu/cpu{cpu}/cpufreq/scaling_governor'), pressure=read('/proc/pressure/cpu'),
        child_user_seconds=usage.ru_utime, child_system_seconds=usage.ru_stime,
        child_voluntary_context_switches=usage.ru_nvcsw, child_involuntary_context_switches=usage.ru_nivcsw,
        scope='Run boundaries only; no per-frame interruption/frequency attribution')
def percent(values, q):
    v = sorted(values); x = (len(v)-1)*q; lo = int(x); hi = min(lo+1, len(v)-1)
    return v[lo] + (v[hi]-v[lo])*(x-lo)
binaries = dict(before=a.before.resolve(), after=a.after.resolve())
metadata = dict(control_experiment=True, acceptance_complete=False, cpu_gate_pass=None,
    release_qualification_unavailable_reason='Both variants are native; this control does not compare against SDL.',
    runs=a.runs, samples_per_run=a.samples, cpu=cpu, replay_interval_ns=23_000_000,
    executable_sha256={name: digest(path) for name,path in binaries.items()},
    flattened_source_sha256={name: digest(path.parent/'benchmark-generated.flex') for name,path in binaries.items()},
    harness_sha256=digest(Path(__file__)), expected_context_versions=a.context_versions, actual_hardware_scanout_verified=False,
    scenes=a.scenes, measure_reuse_control=a.measure_reuse_control, direct_copy_control=a.direct_copy_control)
metadata['fonts'] = []
for pattern in ['sans-serif', 'monospace', 'sans-serif:charset=4e2d', 'sans-serif:charset=1f44b']:
    path = Path(subprocess.check_output(['fc-match', '-f', '%{file}', pattern], text=True))
    metadata['fonts'].append(dict(pattern=pattern, file=str(path), sha256=digest(path)))
rows = []
for scene in a.scenes:
    for run in range(a.runs):
        order = ['before', 'after'] if run % 2 == 0 else ['after', 'before']
        for name in order:
            prefix = out/f'{scene}-{run}-{name}'; request = prefix.with_suffix('.request.json'); result = prefix.with_suffix('.result.json')
            config = dict(scene=scene, samples=a.samples, output=str(result), presentation_feedback=True,
                replay_interval_ns=23_000_000, gpu_timing=False, gpu_present_timing=False)
            if scene == 'selection' and run == 0: config['capture'] = str(prefix.with_suffix('.rgba'))
            request.write_text(json.dumps(config))
            host_before = host_context()
            process = subprocess.run(['taskset', '--cpu-list', str(cpu), str(binaries[name]), str(request)], cwd=ROOT,
                env=env, capture_output=True, timeout=a.samples*.023+30)
            host_after = host_context()
            prefix.with_suffix('.stdout.log').write_bytes(process.stdout); prefix.with_suffix('.stderr.log').write_bytes(process.stderr)
            assert process.returncode == 0, (scene, run, name, process.returncode, process.stderr[-3000:])
            row = json.loads(result.read_text())
            assert row['scene'] == scene and row['backend'] == 'wayland' and not row['sdl_loaded'] and row['inline_preview'], row
            assert row['gpu_renderer'] and not any(v in row['gpu_renderer'].lower() for v in ['llvmpipe', 'softpipe', 'software']), row
            assert not row['gpu_timing_enabled'] and not row['gpu_present_timing_enabled'], 'Control must have no query instrumentation'
            if a.measure_reuse_control: assert row['layout_measure_reuse'] == (name == 'after') and row['counters'][15] > 0, 'Layout control mode/count missing'
            if a.direct_copy_control: assert row['direct_model_copy'] == (name == 'after') and row['layout_measure_reuse'], 'Model copy control changed the selected mode or disabled layout reuse'
            if a.context_versions:
                config = row['egl_config']; expected_version = a.context_versions[0 if name == 'before' else 1]
                assert '.'.join(config['gl_version'].split()[0].split('.')[:2]) == expected_version and config['egl_error_after'] == 0x3000, ('Actual context version mismatch', expected_version, config)
            assert row['presented_updates'] == a.samples and row['discarded_updates'] == 0 and row['counters'][7] == a.samples, row
            assert row['presentation_clock_id'] == 1 and row['replay_interval_ns'] == 23_000_000, row
            assert len(row['scheduled_arrival_ns']) == len(row['arrival_to_dispatch_ns']) == len(row['dispatch_to_presentation_ns']) == len(row['presentation_records']) == len(row['input_update_to_presentation_ns']) == a.samples
            assert [v['tag'] for v in row['presentation_records']] == list(range(1, a.samples+1)), 'Missing/reordered outcomes'
            assert all(b-x == 23_000_000 for x,b in zip(row['scheduled_arrival_ns'], row['scheduled_arrival_ns'][1:])), 'Arrivals dropped or retimed'
            assert all(v['status'] == 1 and v['origin_ns'] == origin and latency == v['presented_ns']-origin == wait+after and wait>=0 and after>=0 for v,origin,latency,wait,after in zip(row['presentation_records'], row['scheduled_arrival_ns'], row['input_update_to_presentation_ns'], row['arrival_to_dispatch_ns'], row['dispatch_to_presentation_ns'])), 'Latency excludes waiting or uses a different clock'
            assert all(len(row[key]) == a.samples for key in ['cpu_work_ns', 'cpu_before_present_ns', 'cpu_present_ns', 'cpu_cleanup_ns']) and all(total == draw+present+cleanup for total,draw,present,cleanup in zip(row['cpu_work_ns'], row['cpu_before_present_ns'], row['cpu_present_ns'], row['cpu_cleanup_ns'])), 'CPU interval excludes required work'
            if scene == 'selection': assert row['selection_text'] and '#' not in row['selection_text'] and row['selection_caret'] != row['selection_anchor']
            if scene == 'typing': assert row['typing_verified_updates'] == a.samples and row['typing_cycle'] == 'ä中👋 -> ä中 -> ä -> empty' and row['typing_final_draft'] == '' and row['typing_caret'] == 0
            mate = next((r for r in rows if r['scene'] == scene and r['run'] == run), None)
            if mate: assert all(row[k] == mate[k] for k in ['width', 'height', 'pixel_width', 'pixel_height', 'gpu_renderer', 'presentation_clock_id']), 'Control viewport/GPU/clock mismatch'
            if mate and a.measure_reuse_control:
                pair = {name: row, mate['variant']: mate}
                assert pair['after']['counters'][15] < pair['before']['counters'][15], 'Layout reuse did not reduce actual measurements'
            if mate and a.direct_copy_control: assert row['counters'][15] == mate['counters'][15], 'Ownership-copy control changed layout workload'
            if mate and a.context_versions:
                assert all(row['egl_config'][key] == mate['egl_config'][key] for key in ['red_bits','green_bits','blue_bits','alpha_bits','depth_bits','stencil_bits','buffer_bits','sample_buffers','samples','surface_type','renderable_type','render_buffer','swap_behavior','minimum_swap_interval','maximum_swap_interval','client_api']), 'Context-only control changed EGL buffer configuration'
            row.update(variant=name, run=run, host_before=host_before, host_after=host_after); rows.append(row)
            (out/'report.json').write_text(json.dumps(dict(**metadata, rows=rows), indent=2)+'\n')
            print(f'PASS native A/B {scene} {run+1}/{a.runs} {name}: p95 {percent(row["input_update_to_presentation_ns"],.95)/1e6:.3f} ms, no discarded updates', flush=True)
before = out/'selection-0-before.rgba'; after = out/'selection-0-after.rgba'
selection = next(row for row in rows if row['scene'] == 'selection' and row['run'] == 0)
assert before.stat().st_size == after.stat().st_size == selection['pixel_width']*selection['pixel_height']*4 > 0, 'Invalid capture size'
equivalence = dict(bytes=before.stat().st_size, before_sha256=digest(before), after_sha256=digest(after))
equivalence['byte_identical'] = equivalence['before_sha256'] == equivalence['after_sha256']
(out/'selection-equivalence.json').write_text(json.dumps(equivalence, indent=2)+'\n'); assert equivalence['byte_identical'], 'Submission change altered selection pixels'
summary = []
for scene in a.scenes:
    selected = [r for r in rows if r['scene'] == scene]; result = dict(scene=scene, variants={})
    for name in ['before', 'after']:
        values = [v for r in selected if r['variant'] == name for v in r['input_update_to_presentation_ns']]
        cpu_values = [v for r in selected if r['variant'] == name for v in r['cpu_work_ns']]
        result['variants'][name] = dict(latency_median_ns=statistics.median(values), latency_p95_ns=percent(values,.95), cpu_median_ns=statistics.median(cpu_values), cpu_p95_ns=percent(cpu_values,.95))
    differences = []
    for run in range(a.runs):
        pair = {r['variant']: r for r in selected if r['run'] == run}
        differences.append(percent(pair['after']['input_update_to_presentation_ns'],.95)-percent(pair['before']['input_update_to_presentation_ns'],.95))
    rng = random.Random(81731); means = sorted(statistics.mean(rng.choices(differences, k=len(differences))) for _ in range(10000))
    result['paired_after_minus_before_p95_ns'] = dict(per_run=differences, mean=statistics.mean(differences), bootstrap_95_low=percent(means,.025), bootstrap_95_high=percent(means,.975)); summary.append(result)
    result['paired_cpu_speedups'] = {}
    for label,quantile in [('median',.5),('p95',.95)]:
        ratios=[]
        for run in range(a.runs):
            pair={r['variant']:r for r in selected if r['run']==run}
            ratios.append(percent(pair['before']['cpu_work_ns'],quantile)/percent(pair['after']['cpu_work_ns'],quantile))
        import math
        rng=random.Random(81731);logs=[math.log(v) for v in ratios]
        estimates=sorted(math.exp(statistics.mean(rng.choices(logs,k=len(logs)))) for _ in range(10000))
        result['paired_cpu_speedups'][label]=dict(per_run=ratios,geomean=math.exp(statistics.mean(logs)),bootstrap_95_low=percent(estimates,.025),bootstrap_95_high=percent(estimates,.975))
(out/'report.json').write_text(json.dumps(dict(**metadata, rows=rows, summary=summary, selection_equivalence=equivalence, experiment_complete=True), indent=2)+'\n')
print('Native A/B control complete; SDL performance qualification is separate.', flush=True)
