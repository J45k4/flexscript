#!/usr/bin/env python3
"""Compare direct and IR native host compilation with identical RDNA GPU OS code."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import platform
import statistics
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('runtime_bench', ROOT / 'scripts/benchmark-llm-runtimes.py')
runtime_bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime_bench)


def artifact(path):
    path = Path(path)
    return dict(path=str(path.resolve()), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def memory(pid):
    """Post-exec process counters, avoiding the launcher's inherited max RSS."""
    fields = {'VmRSS', 'VmHWM', 'VmSize', 'RssAnon', 'RssFile', 'RssShmem'}
    values = {}
    for line in Path(f'/proc/{pid}/status').read_text().splitlines():
        key, _, value = line.partition(':')
        if key in fields:
            values[key + '_KiB'] = int(value.split()[0])
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', default='build/flex')
    parser.add_argument('--checkpoint', default='build/llm/models/qwen3-1.7b')
    parser.add_argument('--context', type=int, default=1024)
    parser.add_argument('--tokens', type=int, default=128)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--output', default='build/gpu-os/native-pipeline')
    args = parser.parse_args()
    assert args.rounds > 0 and 1 < args.tokens < args.context
    compiler = Path(args.compiler).resolve()
    directory = Path(args.output).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    report = dict(date=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  settings=vars(args), machine=platform.uname()._asdict(),
                  scope='Same compiler source and GPU code; only native x86-64 host pipeline differs.',
                  timing='Decode steps/s excludes prefill and first selected token; includes sampling, '
                         'mailbox publication, host polling and streaming. Profiling off; unlocked GPU clocks.',
                  compiler=artifact(compiler), artifacts={}, builds={}, workers={},
                  warmups=[], samples=[], summaries={}, initial_sensors=runtime_bench.sensors())
    result_path = directory / 'results.json'

    def save():
        result_path.write_text(json.dumps(report, indent=2) + '\n')

    # Production compilation remains entirely in Flexscript. Python only drives
    # the comparison, JSON protocol, measurements and report generation.
    for name, source in [('qwen', 'libs/os/gpu/qwen.flex'), ('llm', 'llm.flex'),
                         ('compiler', 'compiler/main.flex')]:
        report['artifacts'][name] = {}
        for pipeline in ('direct', 'ir'):
            path = directory / f'{name}-{pipeline}'
            command = [str(compiler), '--native-pipeline', pipeline, source, '-o', str(path)]
            started = time.perf_counter_ns()
            subprocess.run(command, cwd=ROOT, check=True, capture_output=True)
            report['builds'][name + '-' + pipeline] = dict(
                command=command, single_build_ms=(time.perf_counter_ns() - started)/1e6)
            report['artifacts'][name][pipeline] = artifact(path)
    for name, variants in report['artifacts'].items():
        before, after = variants['direct']['bytes'], variants['ir']['bytes']
        variants['saved_bytes'] = before - after
        variants['saved_percent'] = (1 - after / before) * 100

    short = ('Write a long, detailed adventure story about a little robot exploring '
             'a forest. Include scenery, dialogue, and several events. Keep telling the story.')
    background = ('The forest has tall trees, a river, old stone bridges, hidden caves, '
                  'friendly animals, and an abandoned observatory. The robot carries '
                  'a map and wants to learn how the forest changes through the seasons. ')
    prompts = dict(short=short, longer=background * 8 + '\n' + short)
    report['prompts'] = prompts
    report['checkpoint_config'] = artifact(Path(args.checkpoint) / 'config.json')
    workers = {}
    try:
        for pipeline in ('direct', 'ir'):
            worker_dir = directory / pipeline
            worker_dir.mkdir(exist_ok=True)
            options = SimpleNamespace(binary=directory / f'llm-{pipeline}', compiler=compiler,
                                      checkpoint=args.checkpoint, context=args.context,
                                      worker_target='rdna')
            print('Loading ' + pipeline, flush=True)
            started = time.perf_counter_ns()
            worker = runtime_bench.Worker(options, 'gpu-os', worker_dir)
            workers[pipeline] = worker
            assert worker.ready['worker_target'] == 'rdna-greedy', worker.ready
            report['workers'][pipeline] = dict(ready=worker.ready,
                startup_ms=(time.perf_counter_ns()-started)/1e6,
                ready_memory=memory(worker.process.pid),
                worker_image=artifact(ROOT / 'build/gpu-os/rdna/resident.hsaco'))
            save()
        assert (report['workers']['direct']['worker_image']['sha256'] ==
                report['workers']['ir']['worker_image']['sha256']), 'GPU worker changed between hosts'
        assert (report['workers']['direct']['ready']['resident_bytes'] ==
                report['workers']['ir']['ready']['resident_bytes']), 'GPU allocation mismatch'

        for workload, prompt in prompts.items():
            reference = None
            for round_number in range(args.rounds + 1):
                order = ('direct', 'ir') if round_number % 2 == 0 else ('ir', 'direct')
                for pipeline in order:
                    worker = workers[pipeline]
                    sample = worker.generate(prompt, args.tokens, False)
                    done = sample['done']
                    assert done['worker_target'] == 'rdna-greedy', done
                    assert done['decode_launches'] == 1, done
                    assert done['tokens'] == args.tokens, 'Use a prompt that reaches the token limit'
                    identity = (done['input_ids'], done['generated_ids'])
                    if reference is None:
                        reference = identity
                    assert identity == reference, f'Token mismatch: {workload}/{pipeline}'
                    sample.update(workload=workload, pipeline=pipeline, round=round_number,
                                  memory=memory(worker.process.pid))
                    report['samples' if round_number else 'warmups'].append(sample)
                    save()
                    print(f"{workload:6} round {round_number} {pipeline:6} "
                          f"{sample['decode_steps_per_second']:.2f} steps/s", flush=True)
            summaries = {}
            for pipeline in ('direct', 'ir'):
                samples = [s for s in report['samples']
                           if s['workload'] == workload and s['pipeline'] == pipeline]
                rates = [s['decode_steps_per_second'] for s in samples]
                summaries[pipeline] = dict(median=statistics.median(rates),
                    minimum=min(rates), maximum=max(rates),
                    prompt_tokens=samples[0]['prompt_tokens'], generated_tokens=args.tokens,
                    median_first_token_ms=statistics.median(s['done']['first_token_us']/1000 for s in samples),
                    median_prefill_ms=statistics.median(s['done']['prefill_us']/1000 for s in samples),
                    median_request_wall_ms=statistics.median(s['wall_us']/1000 for s in samples),
                    median_RSS_KiB=statistics.median(s['memory']['VmRSS_KiB'] for s in samples),
                    peak_RSS_KiB=max(s['memory']['VmHWM_KiB'] for s in samples))
            gains = []
            for round_number in range(1, args.rounds + 1):
                pair = {s['pipeline']: s['decode_steps_per_second'] for s in report['samples']
                        if s['workload'] == workload and s['round'] == round_number}
                gains.append((pair['ir']/pair['direct'] - 1) * 100)
            summaries['ir_vs_direct_percent'] = (summaries['ir']['median']/summaries['direct']['median'] - 1)*100
            summaries['paired_gain_percent'] = dict(median=statistics.median(gains),
                minimum=min(gains), maximum=max(gains), ir_wins=sum(g > 0 for g in gains),
                rounds=args.rounds)
            report['summaries'][workload] = summaries
    finally:
        for pipeline, worker in workers.items():
            if worker.process.poll() is None:
                report['workers'][pipeline]['final_memory'] = memory(worker.process.pid)
            worker.close()
        report['final_sensors'] = runtime_bench.sensors()
        save()

    lines = ['| Workload | Direct steps/s | IR steps/s | Change |', '|---|---:|---:|---:|']
    for workload, values in report['summaries'].items():
        lines.append(f"| {workload} ({values['ir']['prompt_tokens']} prompt tokens) | "
                     f"{values['direct']['median']:.2f} | {values['ir']['median']:.2f} | "
                     f"{values['ir_vs_direct_percent']:+.2f}% |")
    lines += ['', '| Binary | Direct bytes | IR bytes | Saved |', '|---|---:|---:|---:|']
    for name, values in report['artifacts'].items():
        lines.append(f"| {name} | {values['direct']['bytes']:,} | {values['ir']['bytes']:,} | "
                     f"{values['saved_percent']:.2f}% |")
    lines += ['', 'All prompt and generated token IDs matched. GPU worker hashes and allocation sizes matched.',
              'Host RSS includes driver and mapped allocations. Single build/startup times are diagnostic, not warm timing medians.']
    summary = '\n'.join(lines) + '\n'
    (directory / 'summary.md').write_text(summary)
    print(summary, flush=True)


if __name__ == '__main__':
    main()
