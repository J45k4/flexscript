#!/usr/bin/env python3
"""Validate GNU raw-register observations and compare precommit implementation.

A valid observation report is not full restart parity. Known remaining DROM
asynchronous delivery differences are preserved explicitly,not normalized away.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('manifest', 'backup', 'baseline', 'baseline-report', 'current', 'current-report', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--batch', type=Path, action='append', required=True)
p.add_argument('--backup-sha256', required=True)
a = p.parse_args()
sha = lambda data: hashlib.sha256(data).hexdigest()
backup = a.backup.read_bytes()
assert len(backup) == 4194304 and sha(backup) == a.backup_sha256
md5 = hashlib.md5(backup).hexdigest()
manifest = json.loads(a.manifest.read_text())
assert [(v['bus'], v['mode']) for v in manifest] == [(b, m) for b in range(2) for m in range(4)]
expected = {(v['bus'], v['mode']): v for v in manifest}
keys = ['BUS', 'MODE', 'VALUE', 'SEEN', 'PC', 'BARRIER', 'LOAD', 'NEXT', 'TAIL',
        'AR8', 'AR9', 'FINAL9', 'CAUSE', 'PRO0', 'PRO3', 'EN', 'PENDING', 'AFTER', 'MMUACK']
pattern = re.compile(('CACHE RESTART ' + ' '.join(k + r' ([0-9a-f]{16})' for k in keys) + r'\r\n').encode())


def symbols(image):
    assert image[:6] == b'\x7fELF\x01\x01'
    offset = struct.unpack_from('<I', image, 32)[0]
    stride, count = struct.unpack_from('<HH', image, 46)
    sections = [struct.unpack_from('<10I', image, offset + i * stride) for i in range(count)]
    result = {}
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        table = image[strings[4]:strings[4] + strings[5]]
        for at in range(section[4], section[4] + section[5], section[9]):
            name, value, size, info, other, index = struct.unpack_from('<IIIBBH', image, at)
            result[table[name:table.find(b'\0', name)].decode()] = value
    return result


def parsed(data, bus, mode):
    assert data.startswith(f'CACHE RESTART START {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert data.endswith(f'CACHE RESTART COMPLETE {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert b' FAIL' not in data
    matches = pattern.findall(data)
    assert len(matches) == 1
    fields = {k: int(v, 16) for k, v in zip(keys, matches[0])}
    assert (fields['BUS'], fields['MODE']) == (bus, mode)
    elf = a.manifest.parent / expected[(bus, mode)]['elf']
    image = elf.read_bytes()
    assert sha(image) == expected[(bus, mode)]['sha256']
    table = symbols(image)
    for key, name in [('BARRIER', 'cr_barrier'), ('LOAD', 'cr_load'), ('NEXT', 'cr_after'), ('TAIL', 'cr_tail')]:
        assert fields[key] == table[name]
    assert fields['NEXT'] == fields['LOAD'] + 3 and fields['LOAD'] == fields['BARRIER'] + 3
    assert fields['FINAL9'] == 2
    value = int.from_bytes(backup[0x1234:0x1238], 'little') if mode in (1, 2) else 0xbad00bad
    assert fields['VALUE'] == value
    if mode == 3:
        assert all(fields[k] == 0 for k in ('SEEN', 'PC', 'AR8', 'AR9', 'CAUSE', 'PRO0', 'PRO3', 'EN', 'PENDING', 'AFTER', 'MMUACK'))
    else:
        assert fields['SEEN'] == 1 and fields['CAUSE'] == 4
        assert fields['PRO0'] == (mode != 0)
        assert fields['PRO3'] == ((1 << (10 + bus * 4)) if mode == 0 else 0)
        assert fields['EN'] == ((1 << (15 + bus * 4)) if mode == 0 else (1 << 21))
        assert fields['PENDING'] == 2 and fields['AFTER'] == 0 and fields['MMUACK'] == (mode == 1)
        assert fields['AR8'] in (0x13579bdf, value) and fields['AR9'] in (1, 2)
        assert fields['BARRIER'] <= fields['PC'] <= fields['TAIL'] + 32
    return fields


def native(directory, report_path):
    proof = json.loads(report_path.read_text())
    assert proof['pass'] and proof['probe_family'] == 'restart' and proof['NOR_unchanged']
    assert proof['NOR_sha256'] == a.backup_sha256
    assert proof['manifest_sha256'] == sha(a.manifest.read_bytes())
    assert len(proof['cases']) == 8 and all(c['pass'] for c in proof['cases'])
    result = {}
    for c in proof['cases']:
        key = (c['bus'], c['mode'])
        assert key in expected and key not in result and c['ELF_sha256'] == expected[key]['sha256']
        label = f'bus{key[0]}-mode{key[1]}'
        data = (directory / (label + '.uart')).read_bytes()
        assert sha(data) == c['UART_sha256']
        assert sha((directory / (label + '.stdout')).read_bytes()) == c['stdout_sha256']
        result[key] = (data, parsed(data, *key))
    return result


baseline = native(a.baseline, a.baseline_report)
current = native(a.current, a.current_report)
seen = {}
cleanup = []
for batch in a.batch:
    report = json.loads((batch / 'physical.json').read_text())
    assert report['pass'] and report['ram_only'] and not report['flash_write_requested']
    assert report['probe_family'] == 'restart' and report['backup_sha256'] == a.backup_sha256
    assert report['expected_full_flash_MD5'] == md5
    assert report['before_matches'] and report['after_matches'] and report['final_reset']
    count = report['selection']['count']
    first = report['selection']['first']
    assert 1 <= count <= 4 and len(report['cases']) == count
    assert [(v['bus'], v['mode']) for v in report['cases']] == [
        (v['bus'], v['mode']) for v in manifest[first:first + count]]
    for name in ('before', 'after'):
        assert any(int(v, 16) == int(md5, 16) for v in re.findall(
            r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])', (batch / (name + '.log')).read_text()))
    assert (batch / 'final-reset.log').exists()
    for case in report['cases']:
        key = (case['bus'], case['mode'])
        assert key in expected and key not in seen and case['completed'] and case['final_reset']
        assert case['sha256'] == expected[key]['sha256']
        label = f'bus{key[0]}-mode{key[1]}'
        data = (batch / (label + '.uart')).read_bytes()
        assert sha(data) == case['UART_sha256'] and data.decode() == case['UART']
        physical = parsed(data, *key)
        if key[1] in (1, 2) or key == (1, 0):
            assert physical['PC'] == physical['LOAD'] and physical['AR8'] == 0x13579bdf and physical['AR9'] == 1
        elif key == (0, 0):
            assert physical['PC'] == physical['TAIL'] and physical['AR8'] == 0xbad00bad and physical['AR9'] == 2
        original_difference = {k: [physical[k], baseline[key][1][k]] for k in keys if physical[k] != baseline[key][1][k]}
        difference = {k: [physical[k], current[key][1][k]] for k in keys if physical[k] != current[key][1][k]}
        if key != (0, 0):
            assert not difference and data == current[key][0], (key, 'precommit register-state regression', difference)
        elif difference:
            # Preserve the known asynchronous DROM delay,while accepting a
            # later implementation which actually eliminates this mismatch.
            assert set(difference) == {'PC', 'AR9'}
            assert current[key][1]['PC'] == physical['NEXT'] and current[key][1]['AR9'] == 1
        seen[key] = {'bus': key[0], 'mode': key[1], 'ELF_sha256': case['sha256'],
                     'physical': physical, 'physical_UART_sha256': sha(data),
                     'baseline_difference': original_difference, 'current_difference': difference,
                     'raw_UART_identical': data == current[key][0]}
    cleanup.append({'first': first, 'count': count, 'full4MiB_unchanged': True, 'final_reset': True})
assert set(seen) == set(expected)
report = {'observations_verified': True, 'scope_complete': False,
          'physical_precommit_cases': 5, 'physical_postcommit_cases': 1,
          'negative_cases': 2, 'exact_current_UART_matches': sum(v['raw_UART_identical'] for v in seen.values()),
          'exact_probe_parity': all(not v['current_difference'] for v in seen.values()),
          'cases': [seen[k] for k in sorted(seen)], 'cleanup': cleanup,
          'remaining': 'DROM disabled-access asynchronous IRQ latency and earlier '
                       'compiler MEMW restart boundary remain T320. This GNU probe '
                       'does not establish all pipeline/IRQ/CPU1 parity.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:8 raw GNU observations;current UART exact matches', report['exact_current_UART_matches'], '/8;T320 remains open')
