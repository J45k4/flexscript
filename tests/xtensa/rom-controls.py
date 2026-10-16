#!/usr/bin/env python3
"""Verify ROM-profile checks detect broken mappings and startup execution.

The independent expected RAM comes from QEMU booted from reset, not this
module's data parser. Supply existing tools and ROM artifacts explicitly.
"""
from emulator_sources import source_path, clone_source
import argparse, hashlib, json, re, subprocess
from pathlib import Path
p = argparse.ArgumentParser(description=__doc__)
for flag in ('compiler', 'rom', 'qemu-reference', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler, rom, reference = a.compiler.resolve(), a.rom.resolve(), a.qemu_reference.resolve()
modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-window.flex', 'xtensa-user.flex', 'xtensa-memory-pages.flex', 'emulator-memory.flex', 'esp32-rom.flex')
sources = {name: clone_source(root,name) for name in modules}
fixture = (root / 'tests/xtensa/rom.flex').read_text()
mutations = [
    ('wrong-DROM-alias', 'em_copy(data,code+0x60000,0x10000);', 'em_copy(data,code+0x50000,0x10000);'),
    ('writable-DROM', 'xt_map(c,0x3ff90000,0x10000,1)', 'xt_map(c,0x3ff90000,0x10000,3)'),
    ('non-executable-IROM', 'xt_map(c,0x40000000,0x70000,5)', 'xt_map(c,0x40000000,0x70000,1)'),
    ('nonzero-ROM-padding', 'em_copy(code,bytes,size);', 'em_copy(code,bytes,size);store8(code+size,1);'),
    ('ignored-map-overlap', 'if address<load64(p)+load64(p+8) && load64(p)<address+size{return 0;}', ''),
    ('wrong-reserved-RAM-range', 'xt_map(c,0x3ffae000,0x2000,3)', 'xt_map(c,0x3ffad000,0x2000,3)'),
    ('skipped-startup-prologue', 'store64(c+128,0x400004fb);', 'store64(c+128,0x40000501);'),
    ('skipped-startup-execution', 'let reason=xt_step(c);', 'let reason=0;store64(c+128,0x40000526);'),
    ('wrong-startup-core', 'xt_wsr(c,235,0xcdcd);', 'xt_wsr(c,235,0xabab);'),
    ('lost-startup-table-entry', 'if !error{em_copy(c,saved,4096);}', 'if !error{xt_write(c,0x3ffae0cc,4,0);em_copy(c,saved,4096);}'),
    ('lost-startup-delay-multiplier', 'if !error{em_copy(c,saved,4096);}', 'if !error{xt_write(c,0x3ffe01e0,4,0);em_copy(c,saved,4096);}'),
    ('CPU-state-not-restored', 'if !error{em_copy(c,saved,4096);}', 'if !error{}'),
    ('live-CPU-startup-allowed', 'load64(c+176) || ', ''),
    ('app-core-profile-accepted', '(xt_sr(c,235) && xt_sr(c,235)!=0xcdcd) || ', ''),
    ('off-by-one-startup-retirement', 'return count;', 'return count+1;'),
]
controls = []
for label, old, new in mutations:
    assert sources['esp32-rom.flex'].count(old) == 1, (label, 'mutation anchor count')
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        (directory / name).write_text(text.replace(old, new) if name == 'esp32-rom.flex' else text)
    source = directory / 'test.flex'
    source.write_text(fixture.replace('"../../emulator/esp32/rom.flex"', json.dumps(str(directory / 'esp32-rom.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'test'
    q = subprocess.run([str(compiler), str(source), '-o', str(binary)], cwd=root, capture_output=True, timeout=25)
    assert q.returncode == 0, (label, 'defect must compile', q.stderr)
    q = subprocess.run([str(binary), str(rom), str(directory / 'native'), str(reference)], cwd=root, capture_output=True, timeout=25)
    assert q.returncode == 1 and re.search(rb'ROM check \d+:', q.stderr), (label, 'defect not rejected by assertion', q.returncode, q.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': q.stderr.decode().strip()})
    print('ROM defect controls:', len(controls), flush=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
a.report.write_text(json.dumps({'pass': True, 'physical_hardware': False, 'controls': controls, 'compiler_sha256': sha(compiler), 'ROM_sha256': sha(rom), 'QEMU_reference_sha256': {name: sha(reference / name) for name in ('low.bin', 'high.bin')}, 'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()}}, indent=2) + '\n')
print('PASS:', len(controls), 'ROM profile defect controls detected')
