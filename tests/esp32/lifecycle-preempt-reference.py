#!/usr/bin/env python3
"""Force real IRQ-return switches at radio lifecycle publication windows.

Copies production source, inserts software-IRQ probes, then removes one critical section
per defect control (or restores saved old functions with --before). The firmware checks observable ownership, peer
results, child entry and exact heap recovery. No emulator code is modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CASES = [
    ('domain-claim', 'esp32-radio-lifecycle-core.flex', 'esp_radio_resources_begin', 1),
    ('timer-init', 'esp32-sdk-timer-core.flex', 'esp_sdk_timer_init', 2),
    ('timer-deinit', 'esp32-sdk-timer-core.flex', 'esp_sdk_timer_deinit', 3),
    ('domain-end', 'esp32-radio-lifecycle-core.flex', 'esp_radio_resources_end', 4),
    ('task-any', 'esp32-radio-os-core.flex', 'esp_radio_cb_task_create_any', 5),
    ('task-pinned', 'esp32-radio-os-core.flex', 'esp_radio_cb_task_create', 6),
    ('allocation-tag', 'esp32-radio-os-core.flex', 'esp_radio_cb_malloc', 7),
    ('thread-semaphore', 'esp32-radio-os-core.flex', 'esp_radio_cb_thread_sem', 8),
]


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def function(text, name):
    start = re.search(r'^fn ' + name + r'\(', text, re.M)
    if not start:
        raise RuntimeError(f'missing function {name}')
    tail = re.search(r'^fn |^global ', text[start.end():], re.M)
    end = start.end() + tail.start() if tail else len(text)
    return start.start(), end


def change(path, name, transform):
    text = path.read_text()
    begin, end = function(text, name)
    path.write_text(text[:begin] + transform(text[begin:end]) + text[end:])


def once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f'mutation anchor count {text.count(old)}: {old}')
    return text.replace(old, new)


def copy_closure(entry, out):
    seen = set()
    def visit(path):
        path = path.resolve()
        rel = path.relative_to(ROOT)
        if rel in seen:
            return
        seen.add(rel)
        data = path.read_bytes()
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        for name in re.findall(rb'^import\s+"([^"]+)"', data, re.M):
            visit(path.parent / name.decode())
    visit(entry)
    return {str(p): sha(out / p) for p in sorted(seen)}


def instrument(tree):
    for _, file, name, mode in CASES:
        path = tree / 'lib/platform' / file
        def transform(text):
            if mode == 1:
                return once(text, 'if !esp_radio_irq_routes', 'lr_probe(1);if !esp_radio_irq_routes')
            if mode == 2:
                return once(text, 'esp_sdk_timer_task=esp_sdk_task_create', 'lr_probe(2);esp_sdk_timer_task=esp_sdk_task_create')
            if mode == 3:
                return once(text, 'let task=esp_sdk_timer_task;', 'lr_probe(3);let task=esp_sdk_timer_task;')
            if mode == 4:
                return once(text, 'let t=esp_sdk_timers;while t', 'lr_probe(4);let t=esp_sdk_timers;while t')
            if mode in (5, 6):
                return once(text, 'let t=esp_radio_task_owned(esp_sdk_task_create(a,d,bytes,e));',
                            f'let t=esp_sdk_task_create(a,d,bytes,e);lr_probe({mode});esp_radio_task_owned(t);')
            if mode == 7:
                expression = 'esp_radio_owned(esp_sdk_malloc(a))'
                # Retain the original locking around allocation and tag.
                statement = 'let result=' + expression if 'let result=' in text else 'return ' + expression
                return once(text, statement,
                            'let allocation=esp_sdk_malloc(a);lr_allocation=allocation;lr_probe(7);' +
                            statement.replace('esp_sdk_malloc(a)', 'allocation'))
            return once(text, 'store64(p,s);', 'lr_probe(8);store64(p,s);')
        change(path, name, transform)
    path = tree / 'tests/esp32/sdk-preempt-resources.flex'
    path.write_text(once(path.read_text(), 'global lr_expect_hooks=0;', 'global lr_expect_hooks=1;'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'driver', 'qemu', 'prefix', 'work']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--before', help='optional saved pre-fix repository root')
    args = parser.parse_args()
    work = Path(args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    if (work / 'report.json').exists():
        raise RuntimeError('choose a fresh work directory')
    env = os.environ.copy()
    (work / 'tmp').mkdir(exist_ok=True)
    env['TMPDIR'] = str(work / 'tmp')
    source = work / 'production-source'
    manifest = copy_closure(ROOT / 'tests/esp32/sdk-preempt-resources.flex', source)
    records = []
    for case in [None] + CASES:
        name = case[0] if case else 'protected'
        tree = work / name / 'source'
        shutil.copytree(source, tree)
        before_sha = None
        if case:
            _, file, name_fn, mode = case
            if args.before:
                old = Path(args.before) / 'lib/platform' / file
                if not old.exists():old=old.with_name(old.name.replace('-core.flex','.flex'))
                before_sha = sha(old)
                old_text = old.read_text()
                begin, end = function(old_text, name_fn)
                change(tree / 'lib/platform' / file, name_fn, lambda _: old_text[begin:end])
            else:
                def unprotect(text):
                    text = once(text, 'let ps=esp32_irq_save();', '')
                    if 'esp32_irq_restore(ps);' not in text:
                        raise RuntimeError('missing IRQ restoration mutation anchor')
                    return text.replace('esp32_irq_restore(ps);', '')
                change(tree / 'lib/platform' / file, name_fn, unprotect)
        instrument(tree)
        output = work / name / 'firmware'
        cmd = [args.driver, '--compiler', args.compiler, '--qemu', args.qemu,
               '--prefix', args.prefix, '--work', str(output), '--xip', 'yes',
               '--source', str(tree / 'tests/esp32/sdk-preempt-resources.flex')]
        log = work / name / 'execution.log'
        with log.open('w') as stream:
            result = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=45)
        text = log.read_text()
        expected = f'LIFECYCLE FAIL {100 + case[3]:016x}' if case else 'hooks=0000000000000020 masked=0000000000000020'
        success = result.returncode == (1 if case else 0) and expected in text
        if case:
            trace = output / 'qmp-failure.log'
            success = success and 'main returned zero' in text and trace.exists() and 'SHUTDOWN' in trace.read_text()
        record = dict(case=name, expected_behavior=success, exit_code=result.returncode,
                      expected_uart=expected, log=str(log), log_sha256=sha(log),
                      old_file_sha256=before_sha)
        records.append(record)
        print(json.dumps(record), flush=True)
        report = dict(pass_all=all(r['expected_behavior'] for r in records),
                      cases=records, source_sha256=manifest,
                      tool_sha256={str(Path(p).resolve()): sha(p) for p in
                                   [args.driver, args.compiler, args.qemu, __file__]},
                      physical_hardware=False, emulator_changes=False)
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if not success:
            raise RuntimeError(f'{name}: expected behavior missing; see {log}')
    print('Protected32 publication windows pass; all eight isolated defect controls fail')


if __name__ == '__main__':
    main()
