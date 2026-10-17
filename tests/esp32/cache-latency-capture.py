#!/usr/bin/env python3
"""Validate measured IRQ timing without turning observations into fake parity.

The actual ELF load addresses,clock selections,raw interrupted registers and
cleanup logs are authoritative. Optional partial mode accepts only completed,
fully guarded batches and explicitly leaves the32-case matrix incomplete.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from elf32_symbols import elf32_symbols, mmu_probe_profile, mmu_paired_matrix

p = argparse.ArgumentParser(description=__doc__)
for name in ('matrix', 'backup', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--backup-sha256', required=True)
p.add_argument('--allow-partial', action='store_true')
p.add_argument('--family', choices=('latency', 'mmu'), default='latency')
p.add_argument('--unmask-near', type=int, choices=(0, 1, 2), default=0)
p.add_argument('--matched-placement', type=int, choices=(0, 1), default=0)
p.add_argument('--late-op', choices=('ps', 'sar', 'ps-nop', 'rsil'), default='ps')
p.add_argument('--paired-matrix', type=Path)
p.add_argument('--prefix-sync', type=int, choices=(0, 1), default=0)
p.add_argument('--post-kinds', type=int, choices=(0, 1, 2, 3, 4, 5, 6), nargs='+', default=[0, 1])
p.add_argument('--buses', type=int, choices=(0, 1), nargs='+', default=[0, 1])
a = p.parse_args()
assert a.late_op == 'ps' or (a.family == 'mmu' and a.matched_placement and a.unmask_near == 2), 'alternate late op requires matched repeated-write profile'
assert bool(a.paired_matrix) == bool(a.matched_placement), 'matched placement requires an explicit paired matrix'
assert not a.matched_placement or (a.family == 'mmu' and not a.prefix_sync), 'matched placement is a separate MMU experiment'
assert a.unmask_near != 2 or a.matched_placement, 'repeated PS write requires matched placement'
assert not a.unmask_near or (a.family == 'mmu' and not a.prefix_sync), 'unmask-near is a separate MMU experiment'
assert not a.prefix_sync or a.family == 'mmu', 'prefix-sync is an MMU experiment'
assert a.family != 'mmu' or a.post_kinds == [0], 'MMU sweep requires post-kind0'
assert len(set(a.post_kinds))==len(a.post_kinds) and len(set(a.buses))==len(a.buses)
sha = lambda data: hashlib.sha256(data).hexdigest()
backup = a.backup.read_bytes()
assert len(backup) == 4194304 and sha(backup) == a.backup_sha256
md5 = hashlib.md5(backup).hexdigest()
keys = ['BUS', 'MODE', 'CLOCK', 'SOURCE', 'PERIOD', 'DIV', 'ROMTICKS', 'KIND', 'ALIGN',
        'VALUE', 'SEEN', 'PC', 'BARRIER', 'LOAD', 'NEXT', 'TAIL', 'AR8', 'AR9', 'FINAL9',
        'CAUSE', 'PRO0', 'PRO3', 'EN', 'PENDING', 'AFTER', 'MMUACK']
base_keys = keys


def parsed(data, item, symbols):
    bus, mode = item['bus'], item['mode']
    clock, kind = item['clock_mhz'], item['post_kind']
    keys = base_keys + (['STARTCC', 'IRQCC'] if kind >= 5 else [])
    pattern = re.compile(('CACHE ' + a.family.upper() + ' ' + ' '.join(k + r' ([0-9a-f]{16})' for k in keys) + r'\r\n').encode())
    assert data.startswith(f'CACHE {a.family.upper()} START {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert data.endswith(f'CACHE {a.family.upper()} COMPLETE {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert b' FAIL' not in data
    matches = pattern.findall(data)
    assert len(matches) == 1
    fields = {k: int(v, 16) for k, v in zip(keys, matches[0])}
    if kind >= 5:
        assert fields['STARTCC'] <= 0xffffffff and fields['IRQCC'] <= 0xffffffff
        assert 0 < ((fields['IRQCC'] - fields['STARTCC']) & 0xffffffff) < 1000000
    assert (fields['BUS'], fields['MODE'], fields['CLOCK'], fields['KIND'], fields['ALIGN']) == (bus, mode, clock, kind, mode)
    assert (fields['SOURCE'], fields['PERIOD'], fields['DIV'], fields['ROMTICKS']) == (
        (0, 0, 0, 13) if clock == 40 else (1, 1, 0, 160))
    for key, name in [('BARRIER', 'cr_barrier'), ('LOAD', 'cr_load'), ('NEXT', 'cr_after'), ('TAIL', 'cr_tail')]:
        assert fields[key] == symbols[name]
    assert fields['NEXT'] == fields['LOAD'] + 3 and fields['LOAD'] == fields['BARRIER'] + 3
    if kind >= 3:
        assert symbols['cr_enable'] == fields['NEXT'] + 24 + (kind >= 5) * 3
    assert symbols['cr_run'] <= fields['PC'] < symbols['cr_vectors']
    expected_word = int.from_bytes(backup[0x1234:0x1238], 'little') if a.family == 'mmu' else 0xbad00bad
    assert fields['VALUE'] == expected_word and fields['FINAL9'] == 2 + (kind in (1, 3, 4, 5, 6)) * 7
    assert fields['SEEN'] == 1 and fields['CAUSE'] == 4
    assert fields['PRO0'] == (a.family == 'mmu')
    assert fields['PRO3'] == (0 if a.family == 'mmu' else 1 << (10 + bus * 4))
    assert fields['EN'] == ((1 << 21) if a.family == 'mmu' else 1 << (15 + bus * 4)) and fields['PENDING'] == 2
    assert fields['AFTER'] == 0 and fields['MMUACK'] == (a.family == 'mmu')
    assert fields['AR8'] in (expected_word, 0x13579bdf) and 1 <= fields['AR9'] <= fields['FINAL9']
    return fields


cases = []
cleanup = []
missing = []
for clock in (40, 160):
    for kind in a.post_kinds:
        folder = a.matrix / f'clock{clock}-kind{kind}'
        manifest_path = folder / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        native = json.loads((folder / 'native.json').read_text())
        assert native['pass'] and native['probe_family'] == a.family and native['NOR_unchanged']
        assert native['NOR_sha256'] == a.backup_sha256 and native['manifest_sha256'] == sha(manifest_path.read_bytes())
        assert [(c['bus'], c['mode']) for c in manifest] == [(b, m) for b in range(2) for m in range(4)]
        assert len(native['cases']) == 8 and all(c['pass'] for c in native['cases'])
        if a.matched_placement:
            mmu_paired_matrix(folder, a.paired_matrix.resolve() / folder.name, a.unmask_near, a.backup_sha256, a.late_op)
        symbols = {}
        for c in manifest:
            assert c['clock_mhz'] == clock and c['post_kind'] == kind
            if a.family == 'mmu':
                assert c['fault'] == 'mmu-invalid'
                assert c.get('prefix_sync', 0) == a.prefix_sync
                assert c.get('unmask_near', 0) == a.unmask_near
                assert c.get('late_op', 'ps') == a.late_op
                assert c.get('matched_placement', 0) == a.matched_placement
            image = (folder / c['elf']).read_bytes()
            assert sha(image) == c['sha256']
            symbols[(c['bus'], c['mode'])] = (mmu_probe_profile(image, a.prefix_sync, a.unmask_near, a.matched_placement, a.late_op) if a.family == 'mmu' else elf32_symbols(image))
        for bus in a.buses:
            assert {symbols[(bus, mode)]['cr_load'] & 3 for mode in range(4)} == {0, 1, 2, 3}
            batch = folder / ('physical-DROM' if bus == 0 else 'physical-IROM')
            proof_path = batch / 'physical.json'
            if not proof_path.exists():
                assert a.allow_partial, ('missing batch', batch)
                missing.append(str(batch))
                continue
            d = json.loads(proof_path.read_text())
            if not d['pass']:
                assert a.allow_partial, ('incomplete batch', batch)
                missing.append(str(batch))
                continue
            assert d['ram_only'] and not d['flash_write_requested'] and d['probe_family'] == a.family
            assert d['backup_sha256'] == a.backup_sha256 and d['expected_full_flash_MD5'] == md5
            assert d['before_matches'] and d['after_matches'] and d['final_reset']
            assert d['selection'] == {'first': bus * 4, 'count': 4}
            assert len(d['cases']) == 4 and all(c['completed'] and c['final_reset'] for c in d['cases'])
            for name in ('before', 'after'):
                assert any(int(s, 16) == int(md5, 16) for s in re.findall(
                    r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])', (batch / (name + '.log')).read_text()))
            assert (batch / 'final-reset.log').exists()
            assert [(c['bus'], c['mode']) for c in d['cases']] == [(bus, mode) for mode in range(4)]
            for record in d['cases']:
                mode = record['mode']
                item = manifest[bus * 4 + mode]
                assert record['sha256'] == item['sha256']
                label = f'bus{bus}-mode{mode}'
                assert (batch / (label + '-reset.log')).exists()
                physical_data = (batch / (label + '.uart')).read_bytes()
                assert sha(physical_data) == record['UART_sha256'] and physical_data.decode() == record['UART']
                physical = parsed(physical_data, item, symbols[(bus, mode)])
                n = native['cases'][bus * 4 + mode]
                assert (n['bus'], n['mode'], n['ELF_sha256']) == (bus, mode, item['sha256'])
                native_data = (folder / 'native' / (label + '.uart')).read_bytes()
                assert sha(native_data) == n['UART_sha256']
                assert sha((folder / 'native' / (label + '.stdout')).read_bytes()) == n['stdout_sha256']
                fields = parsed(native_data, item, symbols[(bus, mode)])
                differences = {k: [physical[k], fields[k]] for k in physical if physical[k] != fields[k]}
                executed_after_load = None
                if physical['NEXT'] <= physical['PC'] <= physical['TAIL'] + 12 and not (physical['PC'] - physical['NEXT']) % 3:
                    executed_after_load = (physical['PC'] - physical['NEXT']) // 3
                cases.append({'clock_mhz': clock, 'post_kind': kind, 'bus': bus, 'selector': mode,
                              'actual_load_alignment': physical['LOAD'] & 3,
                              'ELF_sha256': item['sha256'], 'physical_UART_sha256': sha(physical_data),
                              'native_UART_sha256': sha(native_data), 'physical': physical,
                              'postload_instructions_before_IRQ': executed_after_load,
                              'enable_store_address': symbols[(bus, mode)].get('cr_enable') if kind >= 3 else None,
                              'postenable_instructions_before_IRQ': (physical['PC'] - symbols[(bus, mode)]['cr_enable'] - 3) // 3 if kind >= 3 and executed_after_load is not None else None,
                              'native_difference': differences, 'raw_UART_identical': physical_data == native_data,
                              'physical_stamp_to_handler_cycles': ((physical['IRQCC']-physical['STARTCC'])&0xffffffff) if kind>=5 else None,
                              'native_stamp_to_handler_cycles': ((fields['IRQCC']-fields['STARTCC'])&0xffffffff) if kind>=5 else None})
            cleanup.append({'clock_mhz': clock, 'post_kind': kind, 'bus': bus,
                            'full4MiB_unchanged': True, 'final_reset': True})
assert cases
expected_batches = 2*len(a.post_kinds)*len(a.buses)
complete = not missing and len(cases) == expected_batches*4
if not a.allow_partial:
    aggregate = json.loads((a.matrix / 'physical-matrix.json').read_text())
    assert aggregate['pass'] and len(aggregate['batches']) == expected_batches and complete
report = {'probe_family': a.family, 'matched_placement': a.matched_placement, 'late_op': a.late_op, 'prefix_sync': a.prefix_sync, 'unmask_near': a.unmask_near, 'completed_observations_verified': True, 'matrix_complete': complete,
          'scope_complete': False, 'full_ESP32_goal_complete': False,
          'cases': cases, 'verified_batches': cleanup, 'missing_or_incomplete_batches': missing,
          'exact_native_UART_matches': sum(c['raw_UART_identical'] for c in cases),
          'full_timing_model_proven_by_capture_alone': False,
          'ROM_delay_word': {'download40MHz': 13, 'explicit_CPU160MHz': 160},
          'limits': 'Only measured alignment/instruction/clock profiles. '
                    'Recorded differences remain open;completion of the physical '
                    'matrix does not claim all pipeline/IRQ/device parity.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print(('COMPLETE' if complete else 'PARTIAL') + f':{len(cases)} verified timing observations;native exactmatches ' + str(report['exact_native_UART_matches']))
for c in cases:
    print(c['clock_mhz'], c['post_kind'], c['bus'], c['actual_load_alignment'],
          'AR8', hex(c['physical']['AR8']), 'AR9', c['physical']['AR9'],
          'postload instructions', c['postload_instructions_before_IRQ'])
