#!/usr/bin/env python3
"""Verify PRO cache-line semantics and clean rejection of broken device models.

GNU emits the instruction fixture. The device has synthetic bounded NOR bytes;
no platform drivers/compiler encoders, board access or downloads are used.
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
compiler = a.compiler.resolve()


def run(command):
    return subprocess.run([str(x) for x in command], cwd=root,
                          capture_output=True, timeout=20)


def checked(command):
    q = run(command)
    assert q.returncode == 0, (command, q.returncode, q.stdout, q.stderr)
    return q


sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
obj, raw = work / 'GNU-lines.o', work / 'GNU-lines.bin'
checked([a.assembler, root / 'tests/xtensa/cache-line-instructions.S', '-o', obj])
checked([a.objcopy, '-O', 'binary', '--only-section=.text', obj, raw])
assert raw.stat().st_size == 9
fixture = root / 'tests/xtensa/cache-lines.flex'
binary = work / 'model'
checked([compiler, fixture, '-o', binary])
q = checked([binary, raw])
assert re.fullmatch(rb'Cache lines: 813 checks passed\n', q.stdout), q.stdout
print(q.stdout.decode().strip(), flush=True)
modules = ('esp32-emulator.flex', 'esp32-cache-emulator.flex',
           'esp32-clock-emulator.flex', 'esp32-gpio-emulator.flex',
           'esp32-gpio-pads.flex', 'esp32-spi-emulator.flex',
           'esp32-rmt-emulator.flex', 'esp32-i2c-emulator.flex', 'esp32-i2s-emulator.flex')
sources = {name: clone_source(root,name) for name in modules}
mutations = [
    ('QEMU-illegal-fill-used', 'esp32-cache-emulator.flex', '0xbad00bad', '0xbaadbaad'),
    ('MMU-invalid-bit-ignored', 'esp32-cache-emulator.flex',
     'store64(at,value&511)', 'store64(at,value&255)'),
    ('cache-hit-clears-MMU-result', 'esp32-cache-emulator.flex',
     'store64(p+1672,load64(p+1672)+1);',
     'store64(p+1576,0);store64(p+1672,load64(p+1672)+1);'),
    ('held-clear-is-ignored', 'esp32-cache-emulator.flex',
     ' && !(load64(p+56+app*32)&8192)', ''),
    ('flush-clears-MMU-result', 'esp32-cache-emulator.flex',
     'em_zero(load64(p+1568),49152);',
     'store64(p+1576,0);em_zero(load64(p+1568),49152);'),
    ('repeated-invalid-lookup-completes', 'esp32-cache-emulator.flex',
     'if (entry&256) && se_cache_mmu_error(p,0)', 'if 0'),
    ('valid-lookup-keeps-old-MMU-result', 'esp32-cache-emulator.flex',
     'store64(p+1576,entry);', 'if entry&256{store64(p+1576,entry);}'),
    ('line-offset-ignored', 'esp32-cache-emulator.flex',
     '(offset&65504)', '0'),
    ('IROM-uses-DROM-MMU-bank', 'esp32-cache-emulator.flex', 'bank=64;', 'bank=0;'),
    ('line-fill-is-half-a-block', 'esp32-cache-emulator.flex',
     'em_copy(data,load64(p)+physical,32);', 'em_copy(data,load64(p)+physical,16);'),
    ('line-hit-reads-live-NOR', 'esp32-cache-emulator.flex',
     'return lines+8192+(slot+way)*32;',
     'return load64(p)+65536+(base&65535);'),
    ('eviction-keeps-warm-fetch-metadata', 'esp32-cache-emulator.flex',
     'if previous{se_cache_fetch_mark(p,previous&~31,1);}', ''),
    ('fetch-fill-does-not-publish-warm-unit', 'esp32-cache-emulator.flex',
     'se_cache_fetch_mark(p,base,0);', ''),
    ('last-way-replacement-not-updated', 'esp32-cache-emulator.flex',
     'store64(lines+40960+set*8,way);', ''),
    ('out-of-NOR-line-wraps', 'esp32-cache-emulator.flex',
     'if physical+32>load64(p+8){return -14;}', 'physical=physical%load64(p+8);'),
    ('DROM-CPU-route-missing', 'esp32-cache-emulator.flex',
     'xt_pages_route_reads(cpu,0x3f400000,1)', '0'),
    ('IROM-CPU-route-missing', 'esp32-cache-emulator.flex',
     'xt_pages_route_reads(cpu,0x400d0000,1)', '0'),
    ('source68-not-delivered', 'esp32-emulator.flex',
     'if !se_chip(s) && se_source(s,68,se_cache_irq(s)){active=active|se_source_mask(s,68);}', ''),
    ('MMU-IRQ-uses-wrong-enable', 'esp32-cache-emulator.flex',
     'ena&(1<<21)', 'ena&(1<<20)'),
    ('disabled-flag-cleared-on-enable', 'esp32-cache-emulator.flex',
     'store64(p+64,enabled && !(cfg&16));',
     'if enabled{store64(p+1592,0);}store64(p+64,enabled && !(cfg&16));'),
    ('retry-commits-fabricated-data', 'esp32-emulator.flex',
     'if reply==0x100000000{return 11;}', 'if reply==0x100000000{reply=0;}'),
    ('cache-source-route-ignored', 'esp32-cache-emulator.flex',
     ' || !se_source(s,68,1)', ''),
    ('cache-policy-uses-software-IRQ', 'esp32-cache-emulator.flex',
     'if !xt_irq_level_mask(c,xt_cycle_eligible(c,pending))', 'if !xt_irq_level(c)'),
    ('MMU-enable-ignored-for-preemption', 'esp32-cache-emulator.flex',
     'se_cache_mmu_error(p,0) && (enable&(1<<21))', 'se_cache_mmu_error(p,0)'),
    ('blocked-load-loses-pending-register', 'esp32-emulator.flex',
     'store64(cache+1632,1);return 11;',
     'store64(cpu+192,0);store64(cache+1632,1);return 11;'),
]
controls = []
for label, module, before, after in mutations:
    assert before in sources[module], label
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, original in sources.items():
        source = original.replace(before, after) if name == module else original
        if name == module and label == 'cache-source-route-ignored':
            # Remove both route checks so an unrelated CPU1 assertion can
            # exercise the existing wrong-route guard case.
            assert source.count('se_source_mask(s,68)') == 1
            source = source.replace('se_source_mask(s,68)', '2')
        source = source.replace('"xtensa.flex"', json.dumps(str(source_path(root,'xtensa.flex'))))
        (directory / name).write_text(source)
    source = directory / 'model.flex'
    source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',
                      json.dumps(str(directory / 'esp32-emulator.flex'))).replace(
                      '"../../scripts/lib/host.flex"',
                      json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'model'
    checked([compiler, source, '-o', binary])
    q = run([binary, raw])
    assert q.returncode == 1 and re.fullmatch(rb'Cache line case \d+: .+\n', q.stderr), (
        label, 'defect must trigger an explicit assertion', q.returncode, q.stdout, q.stderr)
    controls.append({'control': label, 'detected': True,
                     'diagnostic': q.stderr.decode().strip()})
    print('Cache-line controls:', len(controls), flush=True)
report = {'pass': True, 'scope_complete': False, 'physical_hardware': False,
          'checks': 813, 'defect_controls': controls, 'compiler_sha256': sha(compiler),
          'GNU_instructions_sha256': sha(raw),
          'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest()
                            for name, text in sources.items()},
          'scope': 'Functional PRO cache data transactions, measured invalid-MMU '
                   'sequences, blocked-load retirement, valid instruction line '
                   'fills/eviction and source68 level routing. Silicon IRQ-handler '
                   'delivery, invalid instruction fetch, CPU1, replacement and '
                   'cycle timing remain unverified.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:813 cache-line checks/', len(controls), 'clean defect controls')
