#!/usr/bin/env python3
"""Build isolated cache-error IRQ RAM probes with explicitly supplied tools.

Only expected NOR words are copied into private generated wrappers. No device
access, downloads, compiler bootstrap or source credential storage.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from elf32_symbols import elf32_symbols, mmu_probe_profile

p = argparse.ArgumentParser(description=__doc__)
for name in ('compiler', 'linker', 'ld', 'rom-ld', 'backup', 'work', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--backup-sha256', required=True)
p.add_argument('--family', choices=('handler', 'restart', 'latency', 'mmu'), default='handler')
p.add_argument('--as', dest='assembler', type=Path)
p.add_argument('--clock', type=int, choices=(40, 160), default=40)
p.add_argument('--unmask-near', type=int, choices=(0, 1, 2), default=0)
p.add_argument('--matched-placement', type=int, choices=(0, 1), default=0)
p.add_argument('--late-op', choices=('ps', 'sar', 'ps-nop', 'rsil'), default='ps')
p.add_argument('--prefix-sync', type=int, choices=(0, 1), default=0)
p.add_argument('--post-kind', type=int, choices=(0, 1, 2, 3, 4, 5, 6), default=0)
a = p.parse_args()
assert a.late_op == 'ps' or (a.family == 'mmu' and a.matched_placement and a.unmask_near == 2), 'alternate late op requires matched repeated-write profile'
assert not a.matched_placement or (a.family == 'mmu' and not a.prefix_sync), 'matched placement is a separate MMU experiment'
assert a.unmask_near != 2 or a.matched_placement, 'repeated PS write requires matched placement'
assert not a.unmask_near or (a.family == 'mmu' and not a.prefix_sync), 'unmask-near is a separate MMU experiment'
assert not a.prefix_sync or a.family == 'mmu', 'prefix-sync is an MMU experiment'
assert a.family != 'mmu' or a.post_kind == 0, 'MMU alignment sweep uses the plain postload profile'
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
backup = a.backup.read_bytes()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert len(backup) == 4194304 and sha(a.backup) == a.backup_sha256
source = root / ('tests/esp32/cache-' + a.family + '-observe.flex')
prefix = {'handler': 'ch', 'restart': 'cr', 'latency': 'lt', 'mmu': 'ma'}[a.family]
inputs = set()


def imports(path):
    path = path.resolve()
    if path in inputs:
        return
    inputs.add(path)
    for relative in re.findall(r'^import\s+"([^"]+)";', path.read_text(), re.M):
        imports(path.parent / relative)


imports(source)
inputs.add(root / "tests/esp32/elf32_symbols.py")
obj = None
if a.family in ('restart', 'latency', 'mmu'):
    assert a.assembler, '--family restart requires an explicit --as executable'
    assembly = root / 'tests/xtensa/cache-oracle/restart.S'
    inputs.add(assembly)
    obj = work / 'restart.o'
    if a.family == 'restart':
        q = subprocess.run([str(a.assembler.resolve()), '--text-section-literals', str(assembly),
                            '-o', str(obj)], capture_output=True, timeout=25)
        assert q.returncode == 0, (q.stdout, q.stderr)
before = {str(path.relative_to(root)): sha(path) for path in inputs}
manifest = []
for bus in range(2):
    for mode in range(4):
        label = f'bus{bus}-mode{mode}'
        wrapper = work / (label + '.flex')
        word0 = int.from_bytes(backup[0x1234:0x1238], 'little')
        word1 = int.from_bytes(backup[0x11234:0x11238], 'little')
        wrapper.write_text('import ' + json.dumps(str(source)) + ';\n' +
                           f'fn {prefix}_bus(){{return {bus};}}\nfn {prefix}_mode(){{return {mode};}}\n' +
                           f'fn {prefix}_word(page){{if page{{return {word1};}}return {word0};}}\n')
        if a.family in ('latency', 'mmu'):
            wrapper.write_text(wrapper.read_text() + f'fn {prefix}_clock(){{return {a.clock};}}\n')
            obj = work / (label + '-restart.o')
            q = subprocess.run([str(a.assembler.resolve()), '--text-section-literals',
                                '--defsym', '.Lcr_profile=1', '--defsym', f'.Lcr_alignment={mode}',
                                '--defsym', f'.Lcr_post_kind={a.post_kind}', '--defsym', f'.Lcr_bus={bus}',
                                '--defsym', f'.Lcr_prefix_sync={a.prefix_sync}', '--defsym', f'.Lcr_unmask_near={a.unmask_near}', '--defsym', f'.Lcr_matched_placement={a.matched_placement}', '--defsym', f'.Lcr_late_op={dict(ps=0, sar=1, **{"ps-nop": 2}, rsil=3)[a.late_op]}', str(assembly),
                                '-o', str(obj)], capture_output=True, timeout=25)
            assert q.returncode == 0, (q.stdout, q.stderr)
        unlinked = work / (label + '-unlinked.elf')
        elf = work / (label + '.elf')
        link_command = [a.linker.resolve(), '--firmware', unlinked, '--output', elf]
        if obj:
            link_command.extend(['--object', obj])
        link_command.extend(['--ld', a.ld.resolve(), '--rom', a.rom_ld.resolve()])
        commands = [[a.compiler.resolve(), '--target', 'esp32-radio-elf', wrapper, '-o', unlinked],
                    link_command]
        for command in commands:
            q = subprocess.run([str(x) for x in command], cwd=root,
                               capture_output=True, timeout=25)
            assert q.returncode == 0, (label, q.stdout, q.stderr)
        item = {'bus': bus, 'mode': mode, 'elf': elf.name, 'sha256': sha(elf)}
        if a.family in ('latency', 'mmu'):
            item.update(clock_mhz=a.clock, post_kind=a.post_kind)
            if a.family == 'mmu':
                item['fault'] = 'mmu-invalid'
                item['prefix_sync'] = a.prefix_sync
                item['unmask_near'] = a.unmask_near
                if a.late_op != 'ps':
                    item['late_op'] = a.late_op
                if a.matched_placement:
                    item['matched_placement'] = a.matched_placement
        manifest.append(item)
if a.family in ('latency', 'mmu'):
    for bus in (0, 1):
        if a.post_kind >= 3:
            for c in manifest:
                symbols = elf32_symbols((work / c['elf']).read_bytes())
                assert symbols['cr_enable'] == symbols['cr_after'] + 24 + (a.post_kind >= 5) * 3, 'settled enable edge required'
        residues = [elf32_symbols((work / c['elf']).read_bytes())['cr_load'] & 3
                    for c in manifest if c['bus'] == bus]
        assert set(residues) == {0, 1, 2, 3}, ('actual GNU load alignment coverage', bus, residues)
    if a.family == 'mmu':
        for c in manifest:
            mmu_probe_profile((work / c['elf']).read_bytes(), a.prefix_sync, a.unmask_near, a.matched_placement, a.late_op)
assert before == {str(path.relative_to(root)): sha(path) for path in inputs}
(work / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
report = {'pass': True, 'probe_family': a.family, 'physical_hardware': False, 'images': manifest,
          'source_sha256': before, 'compiler_sha256': sha(a.compiler),
          'linker_sha256': sha(a.linker), 'GNU_ld_sha256': sha(a.ld),
          'ROM_ld_sha256': sha(a.rom_ld), 'backup_sha256': a.backup_sha256}
if a.assembler:
    report['GNU_assembler_sha256'] = sha(a.assembler)
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:8 isolated RAM cache IRQ images built (' + a.family + ')')
