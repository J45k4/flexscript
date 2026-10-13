#!/usr/bin/env python3
"""Alternate matched chat requests between graph and resident GPU execution."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import select
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def sensors():
    device = Path('/sys/class/drm/card1/device')
    result = {}
    for name in ('gpu_busy_percent', 'mem_info_vram_used', 'mem_info_vram_total'):
        try:
            result[name] = int((device / name).read_text())
        except (OSError, ValueError):
            pass
    for directory in sorted((device / 'hwmon').glob('hwmon*')):
        for name in ('temp1_input', 'power1_average', 'freq1_input'):
            try:
                result[name] = int((directory / name).read_text())
            except (OSError, ValueError):
                pass
    return result


class Worker:
    def __init__(self, args, runtime, directory):
        self.runtime = runtime
        self.error_path = directory / (runtime + '.stderr.log')
        self.error = self.error_path.open('wb')
        self.process = subprocess.Popen([
            str(Path(args.binary).resolve()), '--worker', '1',
            '--checkpoint', str(Path(args.checkpoint).resolve()),
            '--compiler', str(Path(args.compiler).resolve()),
            '--backend', 'rdna', '--weights', 'f16',
            '--runtime', runtime, '--device', '0', '--context', str(args.context),
        ], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self.error, bufsize=0)
        self.buffer = b''
        loading = self.until('ready', 300)
        self.ready = loading[-1]
        assert self.ready['runtime'] == runtime, self.ready

    def until(self, kind, timeout=120):
        events = []
        deadline = time.monotonic() + timeout
        while True:
            if b'\n' not in self.buffer:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f'{self.runtime}: waiting for {kind}')
                if not select.select([self.process.stdout], [], [], .1)[0]:
                    continue
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError(self.error_path.read_text(errors='replace')[-3000:])
                self.buffer += chunk
                continue
            line, self.buffer = self.buffer.split(b'\n', 1)
            event = json.loads(line.decode('utf-8', errors='replace'))
            if event['event'] == 'error':
                raise RuntimeError(event['text'])
            events.append(event)
            if event['event'] == kind:
                return events

    def send(self, request):
        self.process.stdin.write((json.dumps(request) + '\n').encode())
        self.process.stdin.flush()

    def generate(self, prompt, maximum, profile):
        before = sensors()
        start = time.perf_counter_ns()
        self.send(dict(op='generate', turns=[dict(role='user', content=prompt)],
                       max_tokens=maximum, temperature=0, thinking=0, profile=int(profile)))
        events = self.until('idle')
        wall_us = (time.perf_counter_ns() - start) // 1000
        done = next(e for e in events if e['event'] == 'done')
        usage = next(e for e in events if e['event'] == 'context')
        assert events[-1]['resident_bytes'] == self.ready['resident_bytes'], 'scratch leak'
        decode_us = done['elapsed_us'] - done['first_token_us']
        assert done['tokens'] > 1 and decode_us > 0, done
        return dict(done=done, prompt_tokens=usage['prompt_tokens'], wall_us=wall_us,
                    decode_us=decode_us, decode_steps=done['tokens'] - 1,
                    decode_steps_per_second=(done['tokens'] - 1) * 1e6 / decode_us,
                    end_to_end_tokens_per_second=done['tokens'] * 1e6 / done['elapsed_us'],
                    before=before, after=sensors())

    def close(self):
        if self.process.poll() is None:
            self.send(dict(op='shutdown'))
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.error.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', default='build/llm-chat')
    parser.add_argument('--compiler', default='build/flex')
    parser.add_argument('--checkpoint', default='build/llm/models/qwen3-1.7b')
    parser.add_argument('--context', type=int, default=1024)
    parser.add_argument('--tokens', type=int, default=128)
    parser.add_argument('--rounds', type=int, default=5)
    parser.add_argument('--output', default='build/gpu-os/paired-runtime-benchmark')
    args = parser.parse_args()
    assert args.rounds > 0 and 1 < args.tokens < args.context
    directory = Path(args.output)
    directory.mkdir(parents=True, exist_ok=True)
    short = ('Write a long, detailed adventure story about a little robot exploring '
             'a forest. Include scenery, dialogue, and several events. Keep telling the story.')
    background = ('The forest has tall trees, a river, old stone bridges, hidden caves, '
                  'friendly animals, and an abandoned observatory. The robot carries '
                  'a map and wants to learn how the forest changes through the seasons. ')
    prompts = dict(short=short, longer=background * 8 + '\n' + short)
    regimes = [('graph', False), ('gpu-os', False), ('gpu-os-profile', True)]
    report = dict(date=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  settings=vars(args), backend='rdna', weights='f16',
                  sampling='greedy', thinking=False, prompts=prompts,
                  timing='Decode steps/s excludes prefill and the first selected token; '
                         'includes sampling, worker streaming/publication and host polling.',
                  initial_sensors=sensors(), workers={}, samples=[], warmups=[], summaries={})
    report['checkpoint_config_sha256'] = hashlib.sha256(
        (Path(args.checkpoint) / 'config.json').read_bytes()).hexdigest()
    workers = {}
    try:
        for runtime in ('graph', 'gpu-os'):
            print('Loading ' + runtime, flush=True)
            workers[runtime] = Worker(args, runtime, directory)
            report['workers'][runtime] = workers[runtime].ready
        for workload, prompt in prompts.items():
            reference = None

            def run(name, profile, measured, round_number):
                nonlocal reference
                worker = workers['graph' if name == 'graph' else 'gpu-os']
                sample = worker.generate(prompt, args.tokens, profile)
                identity = (sample['done']['input_ids'], sample['done']['generated_ids'])
                if reference is None:
                    reference = identity
                assert identity == reference, f'Token mismatch in {workload}/{name}'
                sample.update(workload=workload, regime=name, round=round_number)
                report['samples' if measured else 'warmups'].append(sample)
                (directory / 'results.json').write_text(json.dumps(report, indent=2))
                print(f"{workload:6} {'run '+str(round_number) if measured else 'warmup':7} "
                      f"{name:14} {sample['done']['tokens']:3} tokens, "
                      f"{sample['decode_steps_per_second']:6.1f} decode steps/s", flush=True)

            for name, profile in regimes:
                run(name, profile, False, 0)
            for round_number in range(1, args.rounds + 1):
                shift = (round_number - 1) % len(regimes)
                order = regimes[shift:] + regimes[:shift]
                if round_number % 2 == 0:
                    order = list(reversed(order))
                for name, profile in order:
                    run(name, profile, True, round_number)
            summary = {}
            for name, _ in regimes:
                samples = [s for s in report['samples'] if s['workload'] == workload and s['regime'] == name]
                rates = [s['decode_steps_per_second'] for s in samples]
                summary[name] = dict(median=statistics.median(rates), minimum=min(rates), maximum=max(rates),
                                     median_first_token_ms=statistics.median(s['done']['first_token_us']/1000 for s in samples),
                                     median_reply_ms=statistics.median(s['done']['elapsed_us']/1000 for s in samples),
                                     prompt_tokens=samples[0]['prompt_tokens'], tokens=samples[0]['done']['tokens'])
            for name, _ in regimes:
                summary[name]['vs_graph_percent'] = (summary[name]['median']/summary['graph']['median'] - 1)*100
            report['summaries'][workload] = summary
    finally:
        for worker in workers.values():
            worker.close()
        report['final_sensors'] = sensors()
        (directory / 'results.json').write_text(json.dumps(report, indent=2))
    lines = ['| Prompt | Runtime | Decode steps/s median (range) | First token ms | Reply ms | vs graph |',
             '|---|---|---:|---:|---:|---:|']
    for workload, summary in report['summaries'].items():
        for name, values in summary.items():
            lines.append(f"| {workload} ({values['prompt_tokens']} tokens) | {name} | "
                         f"{values['median']:.1f} ({values['minimum']:.1f}–{values['maximum']:.1f}) | "
                         f"{values['median_first_token_ms']:.1f} | {values['median_reply_ms']:.1f} | "
                         f"{values['vs_graph_percent']:+.1f}% |")
    text = '\n'.join(lines) + '\n\nAll input and generated token IDs match across every run.\n'
    (directory / 'summary.md').write_text(text)
    print(text, flush=True)


if __name__ == '__main__':
    main()
