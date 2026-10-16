#!/usr/bin/env python3
"""GNU-backed CPU data routing and instruction-fetch preflight verification.

Runs normal and deliberately broken CPUs. A defect counts only when a compiled
fixture rejects it through an explicit assertion. No physical board or network.
"""
from emulator_sources import source_path, clone_source
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
for name in ('compiler', 'work', 'report'):
    parser.add_argument('--' + name, type=Path, required=True)
parser.add_argument('--as', dest='assembler', required=True)
parser.add_argument('--objcopy', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = args.compiler.resolve()


def run(command, timeout=35):
    return subprocess.run([str(part) for part in command], cwd=root,
                          capture_output=True, timeout=timeout)


def checked(command, timeout=35):
    result = run(command, timeout)
    assert result.returncode == 0, (command, result.returncode,
                                     result.stdout, result.stderr)
    return result


sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assembly = root / 'tests/xtensa/routed-page-instructions.S'
obj = work / 'GNU-device.o'
raw = work / 'GNU-device.bin'
checked([args.assembler, '--text-section-literals', assembly, '-o', obj])
checked([args.objcopy, '-O', 'binary', '--only-section=.text', obj, raw])
assert raw.stat().st_size == 25
fixtures = {name: (root / 'tests/xtensa' / (name + '-pages.flex')).read_text()
            for name in ('routed', 'preflight')}
checks = {}
for name in fixtures:
    binary = work / (name + '-model')
    checked([compiler, root / 'tests/xtensa' / (name + '-pages.flex'), '-o', binary])
    result = checked([binary, raw])
    match = re.fullmatch((name.capitalize() + r' CPU pages: (\d+) checks passed\n').encode(),
                         result.stdout)
    assert match, (name, result.stdout)
    checks[name] = int(match[1])
    assert checks[name] == {'routed': 45, 'preflight': 10116}[name]
    print(result.stdout.decode().strip(), flush=True)

modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-window.flex', 'xtensa-user.flex',
           'xtensa-memory-pages.flex', 'emulator-memory.flex')
sources = {name: clone_source(root,name) for name in modules}
changes = [
    ('routed', 'data-routing-ignored', 'xtensa.flex',
     'if device && permission==1 && load64(load64(p+16)+64){return 0;}', ''),
    ('routed', 'host-inspection-routed', 'xtensa.flex',
     'return xt_pointer_mode(c,address,n,permission,0);',
     'return xt_pointer_mode(c,address,n,permission,1);'),
    ('routed', 'route-bypasses-read-only-permissions', 'xtensa.flex',
     'if (load64(p+24)&permission)!=permission', 'if 0'),
    ('routed', 'route-bypasses-region-bounds', 'xtensa.flex',
     'if n>size-(address-base)', 'if 0'),
    ('routed', 'MMIO-halfword-sign-lost', 'xtensa.flex',
     'if load64(c+232){value=(value<<48)>>48;}', ''),
    ('routed', 'pending-reply-allows-policy-change', 'xtensa-memory-pages.flex',
     'if load64(c+192){return -16;}', ''),
    ('routed', 'detach-erases-device-route', 'xtensa-memory-pages.flex',
     'store64(d+72,0);store64(d+80,0);return 0;}',
     'store64(d+64,0);store64(d+72,0);store64(d+80,0);return 0;}'),
    ('routed', 'pending-data-load-retires-early', 'xtensa.flex',
     'store64(c+192,r+1);store64(c+200,n);',
     'store64(c+176,load64(c+176)+1);store64(c+192,r+1);store64(c+200,n);'),
    ('preflight', 'metadata-uses-translation-page-shift', 'xtensa-memory-pages.flex',
     'let granule=load64(d+72);', 'let granule=load64(d+16);'),
    ('preflight', 'silent-hit-notification-removed', 'xtensa-memory-pages.flex',
     'if kind==2 && !metadata && (load64(d+80)&1){return 0;}', ''),
    ('preflight', 'fetch-only-policy-observes-data', 'xtensa-memory-pages.flex',
     'if !(options&4) || permission==5', 'if 1'),
    ('preflight', 'prefix-decodes-before-device-fill', 'xtensa.flex',
     'if !p{return xt_fault(c,-14,pc);}if load64(c+296){store64(c+296,0);return 10;}let low=',
     'if !p{return xt_fault(c,-14,pc);}let low='),
    ('preflight', 'instruction-tail-decodes-before-device-fill', 'xtensa.flex',
     'if !p{return xt_fault(c,-14,pc);}if load64(c+296){store64(c+296,0);return 10;}let op=',
     'if !p{return xt_fault(c,-14,pc);}let op='),
    ('preflight', 'notification-unit-address-shifted', 'xtensa-memory-pages.flex',
     'at=load64(region)+(unit<<granule);', 'at=address;'),
    ('preflight', 'cross-unit-summary-loses-prefix', 'xtensa-memory-pages.flex',
     'store64(event+48,load64(event+48)|metadata);', 'store64(event+48,metadata);'),
    ('preflight', 'metadata-alias-size-uses-translation-pages', 'xtensa-memory-pages.flex',
     'let units=load64(r+8)>>load64(host+72);',
     'let units=load64(r+8)>>load64(host+16);'),
    ('preflight', 'new-metadata-alias-check-omitted', 'xtensa-memory-pages.flex',
     ' || (attributes && xt_pages_overlap(event,64,attributes,count*8))', ''),
    ('preflight', 'ack-keeps-stale-fetch-request', 'xtensa-memory-pages.flex',
     'if !pending{store64(c+296,0);}', ''),
    ('preflight', 'preflight-request-not-consumed', 'xtensa.flex',
     'store64(c+296,0);return 10;', 'return 10;'),
    ('preflight', 'blocked-fetch-increments-retired', 'xtensa.flex',
     'store64(c+296,0);return 10;',
     'store64(c+296,0);store64(c+176,load64(c+176)+1);return 10;'),
]
controls = []
for fixture, label, module, before, after in changes:
    assert before in sources[module], (label, 'missing mutation anchor')
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, source in sources.items():
        (directory / name).write_text(source.replace(before, after)
                                     if name == module else source)
    source = directory / 'model.flex'
    source.write_text(fixtures[fixture].replace('"../../emulator/xtensa/cpu.flex"',
                      json.dumps(str(directory / 'xtensa.flex'))).replace(
                      '"../../scripts/lib/host.flex"',
                      json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'model'
    checked([compiler, source, '-o', binary])
    result = run([binary, raw])
    expected = (fixture.capitalize() + r' page case \d+: .+\n').encode()
    assert result.returncode == 1 and re.fullmatch(expected, result.stderr), (
        label, 'defect must produce a clean assertion failure',
        result.returncode, result.stdout, result.stderr)
    controls.append({'control': label, 'fixture': fixture, 'detected': True,
                     'diagnostic': result.stderr.decode().strip()})
    print('Device-page defect controls:', len(controls), flush=True)

# Preserve the existing strict and default-observation contracts with their
# independent defective models, in addition to the new optional policy tests.
prior_report = work / 'default-pages.json'
result = checked(['python3', root / 'tests/xtensa/observed-page-reference.py',
                  '--compiler', compiler, '--as', args.assembler,
                  '--objcopy', args.objcopy, '--work', work / 'default-pages',
                  '--report', prior_report], timeout=180)
print(result.stdout.decode().strip(), flush=True)
prior = json.loads(prior_report.read_text())
assert prior['pass'] and prior['checks'] == 10421
assert prior['strict_page_checks'] == 207257
report = {'pass': True, 'scope_complete': False, 'physical_hardware': False,
          'ESP32_device_integration': False, 'checks': checks,
          'defect_controls': controls, 'default_pages': prior,
          'compiler_sha256': sha(compiler), 'GNU_instructions_sha256': sha(raw),
          'source_sha256': {str(path.relative_to(root)): sha(path) for path in
                           [source_path(root,name) for name in modules] +
                           [root / 'tests/xtensa' / (name + '-pages.flex')
                            for name in fixtures] + [assembly, Path(__file__)]},
          'scope': 'Opt-in pre-retirement CPU DATA routing and fine-grained '
                   'instruction-fetch preflight. ESP32 cache fill, blocked '
                   'lookup, architectural errors and hardware IRQ integration '
                   'remain open.'}
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:', checks, '/', len(controls), 'controls; default 10421/14; strict 207257/14')
