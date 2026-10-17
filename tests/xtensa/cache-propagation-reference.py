#!/usr/bin/env python3
"""GNU-backed CPU-cycle IRQ scheduling and explicit broken-model controls.

No physical access or compiler encoders. The32 physical raw snapshots are
validated separately;these tests cover scheduling invariants beyond that matrix.
"""
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

def checked(args):
    q = subprocess.run([str(x) for x in args], cwd=root, capture_output=True, timeout=25)
    assert q.returncode == 0, (args, q.returncode, q.stdout, q.stderr)
    return q

obj, raw = work / 'GNU-propagation.o', work / 'GNU-propagation.bin'
checked([a.assembler, root / 'tests/xtensa/cache-propagation-instructions.S', '-o', obj])
checked([a.objcopy, '-O', 'binary', '--only-section=.text', obj, raw])
assert raw.stat().st_size == 1795
fixture = root / 'tests/xtensa/cache-propagation.flex'
binary = work / 'model'
checked([a.compiler.resolve(), fixture, '-o', binary])
q = checked([binary, raw])
match = re.fullmatch(rb'Cache propagation: (\d+) checks passed\n', q.stdout)
assert match and int(match[1]) > 1385, q.stdout
checks = int(match[1])
print(q.stdout.decode().strip(), flush=True)
modules = ('esp32-emulator.flex', 'esp32-clock-emulator.flex', 'esp32-cache-emulator.flex',
           'esp32-gpio-emulator.flex', 'esp32-gpio-pads.flex', 'esp32-spi-emulator.flex',
           'esp32-rmt-emulator.flex', 'esp32-i2c-emulator.flex', 'esp32-i2s-emulator.flex')
sources = {name: clone_source(root,name) for name in modules}
mutations = [
    ('fractional-profile-reset-allowed', 'esp32-clock-emulator.flex',
     ' || load64(se_clock(s)+24) || load64(se_clock(s)+32) || load64(se_clock(s)+152)', ''),
    ('CPU-write-transport-missing', 'esp32-cache-emulator.flex', 'se_cpu_cycles(s)+4', 'se_cpu_cycles(s)+0'),
    ('latched-IROM-IRQ-is-immediate', 'esp32-cache-emulator.flex',
     ' && (!load64(p+1720) || se_cpu_cycles(s)>=load64(p+1712))', ''),
    ('MEMW-flushes-without-waiting', 'esp32-cache-emulator.flex',
     'let cycles=se_cache_posted_cycles(s);while cycles>0 && !se_awake(s){',
     'store64(p+1736,se_cpu_cycles(s));se_cache_posted_tick(s);let cycles=se_cache_posted_cycles(s);while cycles>0 && !se_awake(s){'),
    ('MEMW-event-not-acknowledged', 'esp32-cache-emulator.flex',
     'let result=xt_barrier_ack(c);if result{return result;}', 'let result=0;'),
    ('second-write-loses-first', 'esp32-cache-emulator.flex',
     'let wait=se_cache_posted_cycles(s);if wait>0{let result=', 'let wait=0;if wait>0{let result='),
    ('readback-bypasses-pending-write', 'esp32-cache-emulator.flex',
     'fn se_cache_cpu_read_wait(s){let wait=se_cache_posted_cycles(s);', 'fn se_cache_cpu_read_wait(s){let wait=0;'),
    ('early-DROM-arrival', 'esp32-cache-emulator.flex', 'se_cpu_cycles(s)+2+commit', 'se_cpu_cycles(s)+1+commit'),
    ('late-DROM-arrival', 'esp32-cache-emulator.flex', 'se_cpu_cycles(s)+2+commit', 'se_cpu_cycles(s)+3+commit'),
    ('programmable-CCOUNT-deadline', 'esp32-clock-emulator.flex',
     'return load64(load64(s)+176)+load64(se_clock(s)+152);', 'return xt_sr(load64(s),234);'),
    ('idle-cycles-missing-from-time', 'esp32-clock-emulator.flex',
     'return load64(load64(s)+176)+load64(se_clock(s)+152);', 'return load64(load64(s)+176);'),
    ('idle-cycle-IRQ-published-late', 'esp32-clock-emulator.flex',
     'store64(p+152,load64(p+152)+cycles);let result=se_advance(s,units/6);',
     'let result=se_advance(s,units/6);store64(p+152,load64(p+152)+cycles);'),
    ('fractional-cycle-rounds-up', 'esp32-clock-emulator.flex',
     'let result=se_advance(s,units/6);', 'let result=se_advance(s,(units+5)/6);'),
    ('partial-CPU-cycle-debt-ignored', 'esp32-clock-emulator.flex',
     'units=units+load64(se_clock(s)+24)-load64(se_clock(s)+32);',
     'units=units+load64(se_clock(s)+24);'),
    ('fractional-CPU-phase-ignored', 'esp32-clock-emulator.flex',
     'units=units+load64(se_clock(s)+24)-load64(se_clock(s)+32);',
     'units=units-load64(se_clock(s)+32);'),
    ('CPU-slice-overshoots-fractional-IRQ', 'esp32-emulator.flex',
     'if cycles>0 && cycles<stop-load64(cpu+176){stop=load64(cpu+176)+cycles;}', ''),
    ('WAITI-rounded-to-reference-tick', 'esp32-emulator.flex',
     'if cycles>=0 && (wait<0 || se_clock_cycle_units(s,cycles)<=wait*6)', 'if 0'),
    ('EN0-keeps-stale-propagation', 'esp32-cache-emulator.flex', 'if !(ena&bit){store64(armed,0);}', 'if !(ena&bit){}'),
    ('repeated-read-postpones-IRQ', 'esp32-cache-emulator.flex', 'if !load64(p+1704){', 'if 1{'),
    ('load-commit-cycle-not-counted', 'esp32-cache-emulator.flex', 'se_cpu_cycles(s)+2+commit', 'se_cpu_cycles(s)+2'),
    ('propagation-uses-APB-period', 'esp32-cache-emulator.flex', 'se_cpu_cycles(s)+2+commit', 'se_cpu_cycles(s)+se_apb_factor(s)*2+commit'),
]
controls = []
for label, module, old, new in mutations:
    assert sources[module].count(old) == 1, (label, sources[module].count(old))
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, original in sources.items():
        text = original.replace(old, new) if name == module else original
        (directory / name).write_text(text.replace('"xtensa.flex"', json.dumps(str(source_path(root,'xtensa.flex')))))
    source = directory / 'model.flex'
    source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',
                     json.dumps(str(directory / 'esp32-emulator.flex'))).replace(
                     '"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'model'
    checked([a.compiler.resolve(), source, '-o', binary])
    q = subprocess.run([str(binary), str(raw)], capture_output=True, timeout=25)
    assert q.returncode == 1 and re.fullmatch(rb'Cache propagation case \d+: .+\n', q.stderr), (
        label, q.returncode, q.stdout, q.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': q.stderr.decode().strip()})
    print('Propagation controls:', len(controls), flush=True)
a.report.write_text(json.dumps({'pass': True, 'scope_complete': False, 'physical_hardware': False,
    'checks': checks, 'controls': controls, 'compiler_sha256': sha(a.compiler),
    'GNU_instructions_sha256': sha(raw), 'source_sha256': {
        name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
    'limits': 'Functional one-cycle retirement and CPU-cycle idle scheduling. '
              'ENA-edge propagation is a functional policy requiring silicon verification. '
              'Full CPI/pipeline,WAITI latency,electrical timing andCPU1 are not established here.'}, indent=2) + '\n')
print(f'PASS:{checks} CPU-cycle propagation checks/21 clean defect controls')
