#!/usr/bin/env python3
"""GNU-backed opt-in precommit MMIO interrupt tests and defect controls."""
from emulator_sources import source_path, clone_source
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('compiler', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--as', dest='assembler', required=True)
p.add_argument('--objcopy', required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()


def run(command):
    return subprocess.run([str(x) for x in command], cwd=root, capture_output=True, timeout=20)


def checked(command):
    q = run(command)
    assert q.returncode == 0, (command, q.returncode, q.stdout, q.stderr)
    return q


sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
obj, raw = work / 'GNU-preempt.o', work / 'GNU-preempt.bin'
checked([a.assembler, root / 'tests/xtensa/preempt-instructions.S', '-o', obj])
checked([a.objcopy, '-O', 'binary', '--only-section=.text', obj, raw])
assert raw.stat().st_size == 12
fixture = root / 'tests/xtensa/preempt-mmio.flex'
binary = work / 'model'
checked([compiler, fixture, '-o', binary])
q = checked([binary, raw])
assert q.stdout == b'Preempt CPU MMIO: 25 checks passed\n'
print(q.stdout.decode().strip(), flush=True)
modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-memory-pages.flex', 'xtensa-window.flex',
           'xtensa-user.flex', 'emulator-memory.flex')
sources = {n: clone_source(root,n) for n in modules}
changes = [
    ('missing-pending-read-guard', ' || !load64(c+192)', ''),
    ('faulted-read-can-be-preempted', ' || load64(c+160)', ''),
    ('interrupt-not-pending', 'if !(xt_sr(c,226)&xt_sr(c,228)&0x82)', 'if 0'),
    ('CPU-INTENABLE-ignored', 'xt_sr(c,226)&xt_sr(c,228)&0x82', 'xt_sr(c,226)&0x82'),
    ('INTLEVEL-mask-ignored', '(xt_sr(c,230)&31)', '(xt_sr(c,230)&16)'),
    ('EXCM-mask-ignored', '(xt_sr(c,230)&31)', '(xt_sr(c,230)&15)'),
    ('pending-reply-retained', 'store64(c+192,0);', ''),
    ('destination-committed-before-IRQ', 'store64(c+192,0);',
     'xt_setreg(c,load64(c+192)-1,load64(load64(c+224)+40));store64(c+192,0);'),
    ('faulting-PC-skipped', 'store64(c+192,0);',
     'store64(c+128,load64(c+208));store64(c+192,0);'),
    ('read-retired-before-IRQ', 'store64(c+192,0);',
     'store64(c+176,load64(c+176)+1);store64(c+192,0);'),
    ('preemption-clears-interrupt-source', 'store64(c+192,0);',
     'xt_interrupt(c,0);store64(c+192,0);'),
]
controls = []
for label, before, after in changes:
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        if name == 'xtensa.flex':
            head, marker, tail = text.partition('fn xt_mmio_preempt(c)')
            body, end, rest = tail.partition('\n// B4CONST')
            assert marker and end and before in body, label
            text = head + marker + body.replace(before, after) + end + rest
        (directory / name).write_text(text)
    source = directory / 'model.flex'
    source.write_text(fixture.read_text().replace('"../../emulator/xtensa/cpu.flex"',
                      json.dumps(str(directory / 'xtensa.flex'))).replace(
                      '"../../scripts/lib/host.flex"',
                      json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'model'
    checked([compiler, source, '-o', binary])
    q = run([binary, raw])
    assert q.returncode == 1 and re.fullmatch(rb'Preempt MMIO case \d+: .+\n', q.stderr), (
        label, q.returncode, q.stdout, q.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': q.stderr.decode().strip()})
    print('Preempt controls:', len(controls), flush=True)
report = {'pass': True, 'physical_hardware': False, 'checks': 25,
          'defect_controls': controls, 'compiler_sha256': sha(compiler),
          'GNU_instructions_sha256': sha(raw),
          'source_sha256': {n: hashlib.sha256(s.encode()).hexdigest() for n, s in sources.items()},
          'scope': 'Explicit pending-read IRQ preemption,mask/fault/pending guards, '
                   'uncommitted registers/PC/loop,per-CPU isolation,RFE retry and '
                   'default/store behavior. Device-specific restart policies '
                   'require separate physical evidence.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:25 generic precommit MMIO checks/', len(controls), 'defect controls')
