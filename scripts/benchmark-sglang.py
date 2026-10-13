"""Time SGLang streaming requests using input IDs from a Flexscript benchmark report."""
import argparse
import concurrent.futures
import json
import pathlib
import statistics
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--url', default='http://127.0.0.1:30080')
parser.add_argument('--rounds', type=int, default=3)
parser.add_argument('--concurrency', type=int, default=1)
parser.add_argument('--output', default='build/sglang/results')
parser.add_argument('--fixture', default='build/gpu-os/flexscript-scheduler-benchmark/results.json')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
assert args.rounds > 0 and args.concurrency > 0
output = pathlib.Path(args.output)
output.mkdir(parents=True, exist_ok=True)
fixture = json.loads((root / args.fixture).read_text())
prompts = []
for sample in fixture['samples']:
    done = sample['done']
    if not any(p['input_ids'] == done['input_ids'] for p in prompts):
        prompts.append({'input_ids': done['input_ids'], 'reference_ids': done['generated_ids']})
assert len(prompts) == 2


def api(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(args.url + path, data=data,
                                     headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.load(response)


def run(prompt):
    body = {'input_ids': prompt['input_ids'], 'sampling_params': {
        'temperature': 0, 'max_new_tokens': 128, 'ignore_eos': True}, 'stream': True}
    request = urllib.request.Request(args.url + '/generate', data=json.dumps(body).encode(),
                                     headers={'Content-Type': 'application/json'})
    start = time.perf_counter_ns()
    first = None
    last = None
    count = 0
    first_count = None
    ids = []
    events = []
    with urllib.request.urlopen(request, timeout=180) as response:
        for line in response:
            if not line.startswith(b'data: '):
                continue
            line = line[6:].strip()
            if line == b'[DONE]':
                break
            event = json.loads(line)
            if 'error' in event:
                raise RuntimeError(event['error'])
            now = time.perf_counter_ns()
            meta = event.get('meta_info', {})
            next_count = meta.get('completion_tokens', len(event.get('output_ids', [])))
            if next_count > count:
                if first is None:
                    first = now
                    first_count = next_count
                last = now
                count = next_count
            if 'output_ids' in event:
                ids = event['output_ids']
            events.append({'arrival_us': (now-start)/1000, 'event': event})
    end = time.perf_counter_ns()
    assert count == 128 and first is not None and last > first, (count, events[-1:])
    result = {'prompt_tokens': len(prompt['input_ids']), 'completion_tokens': count,
              'first_chunk_tokens': first_count,
              'first_token_us': (first-start)/1000, 'elapsed_us': (end-start)/1000,
              'decode_steps_per_second': (count-first_count)*1e9/(last-first),
              'generated_ids': ids, 'meta_info': meta, 'events': events}
    result['matches_flexscript_ids'] = ids == prompt['reference_ids']
    return result


report = {'server_info': api('/get_server_info'),
          'timing': 'SSE arrival timing; decode excludes prefill/first chunk; includes serving, sampling and output publication. Runtime settings are recorded in server_info.',
          'fixture': str(args.fixture),
          'concurrency': args.concurrency, 'rounds': args.rounds, 'samples': [], 'summaries': []}
for p, prompt in enumerate(prompts):
    for round in range(args.rounds+1):
        start = time.perf_counter_ns()
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            results = list(pool.map(run, [prompt] * args.concurrency))
        elapsed = (time.perf_counter_ns()-start)/1e9
        aggregate = {'prompt': p, 'round': round, 'results': results,
                     'aggregate_output_tokens_per_second': 128*args.concurrency/elapsed}
        report['samples'].append(aggregate)
        (output/'results.json').write_text(json.dumps(report, indent=2))
        print('prompt', p, 'round', round, 'decode',
              [value['decode_steps_per_second'] for value in results],
              'aggregate', aggregate['aggregate_output_tokens_per_second'], flush=True)
    rates = [r['decode_steps_per_second'] for s in report['samples']
             if s['prompt'] == p and s['round'] > 0 for r in s['results']]
    report['summaries'].append({'prompt_tokens': len(prompt['input_ids']),
                               'decode_steps_per_second_median': statistics.median(rates),
                               'min': min(rates), 'max': max(rates)})
(output/'results.json').write_text(json.dumps(report, indent=2))
print(report['summaries'], flush=True)
