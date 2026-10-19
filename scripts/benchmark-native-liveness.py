#!/usr/bin/env python3
"""Alternate identical call-heavy native programs built by two compilers."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import statistics
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def artifact(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, help='Compiler before selective preservation')
    parser.add_argument('--after', default='build/flex')
    parser.add_argument('--application', type=Path, help='Also compare executable sizes for this source')
    parser.add_argument('--iterations', type=int, default=50_000_000)
    parser.add_argument('--rounds', type=int, default=9)
    parser.add_argument('--output', type=Path, default=Path('build/ir-liveness/comparison'))
    args = parser.parse_args()
    assert 0 < args.iterations <= 1_000_000_000 and 1 <= args.rounds <= 100
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    compilers = {name: Path(getattr(args, name)).resolve() for name in ('before', 'after')}
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    source = directory / 'calls.flex'
    source.write_text('fn tick(x){return x^17;}'
        'fn run(count){let a=0;let b=0;let c=0;let d=0;let e=0;let f=0;let g=0;let h=0;let total=0;let n=0;'
        'while n<count{a=n+1;b=n+2;c=n+3;d=n+4;e=n+5;f=n+6;g=n+7;h=n+8;'
        'total=total+a+b+c+d+e+f+g+h;tick(n);n=n+1;}return total;}'
        f'fn main(){{let p=alloc(8);store64(p,run({args.iterations}));syscall(1,1,p,8,0,0,0);return 0;}}\n')
    report = dict(date=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=cpu,
                  scope='Synthetic loop designed to make cached locals dead across calls. Same native IR pipeline; '
                        'process wall time, including process startup. Two warmups per binary; alternating pairs. '
                        'Application measurements are sizes only, not application throughput.',
                  iterations=args.iterations, rounds=args.rounds,
                  compilers={name: artifact(path) for name, path in compilers.items()},
                  source=artifact(source), artifacts={}, samples=[], warmups=[])
    for name, compiler in compilers.items():
        binary = directory / ('calls-' + name)
        subprocess.run([str(compiler), '--native-pipeline', 'ir', str(source), '-o', str(binary)], cwd=ROOT, check=True)
        report['artifacts'][name] = artifact(binary)
        if args.application:
            application = directory / ('application-' + name)
            subprocess.run([str(compiler), '--native-pipeline', 'ir', str(args.application.resolve()), '-o', str(application)], cwd=ROOT, check=True)
            report.setdefault('application', {})[name] = artifact(application)
    expected = struct.pack('<Q', 4*args.iterations**2+32*args.iterations)
    for round_index in range(args.rounds + 2):
        for name in (('before', 'after') if round_index % 2 == 0 else ('after', 'before')):
            start = time.perf_counter_ns()
            p = subprocess.run([str(directory / ('calls-' + name))], capture_output=True, check=True, timeout=60)
            elapsed = time.perf_counter_ns() - start
            assert p.stdout == expected, (name, p.stdout.hex(), expected.hex())
            report['samples' if round_index >= 2 else 'warmups'].append(
                dict(round=round_index, name=name, wall_ns=elapsed))
    report['summary'] = {}
    for name in compilers:
        times = [s['wall_ns']/1e6 for s in report['samples'] if s['name'] == name]
        report['summary'][name] = dict(median_ms=statistics.median(times), min_ms=min(times), max_ms=max(times))
    old, new = (report['summary'][name]['median_ms'] for name in ('before', 'after'))
    report['summary']['speedup'] = old/new
    report['summary']['wall_reduction_percent'] = (1-new/old)*100
    gains = []
    for round_index in range(2, args.rounds+2):
        pair = {s['name']: s['wall_ns'] for s in report['samples'] if s['round'] == round_index}
        gains.append(pair['before']/pair['after']-1)
    report['summary']['paired_gain_percent'] = dict(median=statistics.median(gains)*100,
        minimum=min(gains)*100, maximum=max(gains)*100, wins=sum(g > 0 for g in gains), rounds=args.rounds)
    (directory / 'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report['summary'], indent=2))
    for key in ('artifacts', 'application'):
        if key in report:
            print(key, {name: value['bytes'] for name, value in report[key].items()})


if __name__ == '__main__':
    main()
