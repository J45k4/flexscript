#!/usr/bin/env python3
"""GNU-backed opt-in MEMW device pause/resume checks and defect controls."""
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
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

def run(cmd):
    return subprocess.run([str(x) for x in cmd], cwd=root, capture_output=True, timeout=20)

def checked(cmd):
    q = run(cmd)
    assert q.returncode == 0, (cmd, q.returncode, q.stdout, q.stderr)
    return q

obj, raw = work / 'GNU-barrier.o', work / 'GNU-barrier.bin'
checked([a.assembler, root / 'tests/xtensa/barrier-instructions.S', '-o', obj])
checked([a.objcopy, '-O', 'binary', '--only-section=.text', obj, raw])
assert raw.stat().st_size == 771
fixture = root / 'tests/xtensa/barrier.flex'
binary = work / 'model'
checked([a.compiler.resolve(), fixture, '-o', binary])
q = checked([binary, raw])
assert q.stdout == b'Barrier: 25 checks passed\n', q.stdout
print(q.stdout.decode().strip(), flush=True)
original = clone_source(root,'xtensa.flex')
mutations = [
    ('MEMW-watch-ignored', 'op==0x0020c0 && load64(c+304)', 'op==0x0020c0 && 0'),
    ('default-MEMW-exits', 'op==0x0020c0 && load64(c+304)', 'op==0x0020c0'),
    ('MEMW-event-retires-early', 'store64(c+312,pc);', 'store64(c+176,load64(c+176)+1);store64(c+312,pc);'),
    ('MEMW-event-advances-PC', 'store64(c+312,pc);', 'store64(c+128,pc+3);store64(c+312,pc);'),
    ('MEMW-event-consumes-loop', 'store64(c+312,pc);', 'xt_wsr(c,2,0);store64(c+312,pc);'),
    ('MEMW-watch-not-consumed', 'store64(c+304,0);store64(c+312,pc);', 'store64(c+312,pc);'),
    ('pending-step-executes', 'if load64(c+320){return 12;}', ''),
    ('pending-run-executes', 'if load64(c+320){store64(run+8,12);return 12;}', ''),
    ('ack-changes-PC', 'store64(c+320,0);store64(c+312,0);', 'store64(c+128,load64(c+128)+3);store64(c+320,0);store64(c+312,0);'),
    ('ack-keeps-pending', 'store64(c+320,0);store64(c+312,0);', ''),
    ('pending-watch-overwritten', 'if load64(c+320){return -16;}', ''),
    ('RSYNC-triggers-MEMW-watch', 'op==0x0020c0 && load64(c+304)', '(op==0x0020c0 || op==0x002010) && load64(c+304)'),
]
controls = []
for label, old, new in mutations:
    assert original.count(old) == 1, (label, original.count(old))
    directory = work / label
    directory.mkdir(exist_ok=True)
    text = original.replace(old, new)
    text = re.sub(r'^import "([^"]+)";', lambda m: 'import ' + json.dumps(str(source_path(root,m[1]))) + ';', text, flags=re.M)
    (directory / 'xtensa.flex').write_text(text)
    source = directory / 'model.flex'
    source.write_text(fixture.read_text().replace('"../../emulator/xtensa/cpu.flex"', json.dumps(str(directory / 'xtensa.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'model'
    checked([a.compiler.resolve(), source, '-o', binary])
    q = run([binary, raw])
    assert q.returncode == 1 and re.fullmatch(rb'Barrier case \d+: .+\n', q.stderr), (label, q.returncode, q.stdout, q.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': q.stderr.decode().strip()})
    print('Barrier controls:', len(controls), flush=True)
a.report.write_text(json.dumps({'pass': True, 'physical_hardware_touched': False, 'scope_complete': False,
    'checks': 25, 'controls': controls, 'GNU_instructions_sha256': sha(raw), 'compiler_sha256': sha(a.compiler),
    'source_sha256': {n: sha(root / n) for n in ('emulator/xtensa/cpu.flex', 'tests/xtensa/barrier.flex', 'tests/xtensa/barrier-instructions.S')},
    'limits': 'Generic opt-in notification only. Device write-completion timing,interrupt arbitration during waits andESP32 integration remain separate.'}, indent=2) + '\n')
print('PASS:25 MEMW device-event checks/12 defect controls')
