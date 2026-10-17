#!/usr/bin/env python3
"""Validate silicon IRQ handlers, native semantic parity and full-flash cleanup.

Raw EPCs are recorded separately. The observed restart-boundary discrepancy
remains open under T320; this validator does not claim instruction-exact IRQ
parity. All other reported fields must match.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for name in ('manifest', 'backup', 'native', 'native-report', 'report'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--batch', type=Path, action='append', required=True)
p.add_argument('--backup-sha256', required=True)
a = p.parse_args()
sha = lambda data: hashlib.sha256(data).hexdigest()
backup = a.backup.read_bytes()
assert len(backup) == 4194304 and sha(backup) == a.backup_sha256
md5 = hashlib.md5(backup).hexdigest()
manifest = json.loads(a.manifest.read_text())
assert [(c['bus'], c['mode']) for c in manifest] == [(b, m) for b in range(2) for m in range(4)]
native = json.loads(a.native_report.read_text())
assert native['pass'] and native['NOR_unchanged'] and native['NOR_sha256'] == a.backup_sha256
assert native['manifest_sha256'] == sha(a.manifest.read_bytes())
assert len(native['cases']) == 8 and all(c['pass'] for c in native['cases'])
expected = {(c['bus'], c['mode']): c for c in manifest}
seen = {}
cleanup = []
keys = ['BUS', 'MODE', 'VALUE', 'SEEN', 'SOURCE', 'PRO0', 'PRO3', 'EN',
        'PENDING', 'AFTER', 'MMUACK', 'PC', 'LIVE0', 'LIVE3', 'LIVEIRQ']
pattern = re.compile(('CACHE HANDLER ' + ' '.join(k + r' ([0-9a-f]{16})' for k in keys) + r'\r\n').encode())


def parsed(data, bus, mode):
    assert data.startswith(f'CACHE HANDLER START {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert data.endswith(f'CACHE HANDLER COMPLETE {bus:016x} MODE {mode:016x}\r\n'.encode())
    assert b' FAIL' not in data
    matches = pattern.findall(data)
    assert len(matches) == 1
    values = {k: int(v, 16) for k, v in zip(keys, matches[0])}
    assert (values['BUS'], values['MODE']) == (bus, mode)
    value = int.from_bytes(backup[0x1234:0x1238], 'little') if mode in (1, 2) else 0xbad00bad
    assert values['VALUE'] == value and not values['LIVEIRQ']
    if mode == 3:
        assert values['SOURCE'] == 0xffffffffffffffff
        assert all(not values[k] for k in keys if k not in ('BUS', 'MODE', 'VALUE', 'SOURCE'))
    else:
        flag = 1 << (10 + bus * 4) if mode == 0 else 0
        enable = 1 << (15 + bus * 4) if mode == 0 else 1 << 21
        assert values['SEEN'] == 1 and values['SOURCE'] == 68
        assert values['PRO0'] == (mode != 0) and values['PRO3'] == flag
        assert values['EN'] == enable and values['PENDING'] == 2 and not values['AFTER']
        assert values['MMUACK'] == values['LIVE0'] == (mode == 1)
        assert values['LIVE3'] == flag and 0x40080000 <= values['PC'] < 0x400a0000
    return values


for batch in a.batch:
    d = json.loads((batch / 'physical.json').read_text())
    assert d['pass'] and d['ram_only'] and not d['flash_write_requested']
    assert d['backup_sha256'] == a.backup_sha256 and d['expected_full_flash_MD5'] == md5
    assert d['before_matches'] and d['after_matches'] and d['final_reset']
    assert len(d['cases']) == d['selection']['count'] <= 4
    first = d['selection']['first']
    assert [(c['bus'], c['mode']) for c in d['cases']] == [
        (c['bus'], c['mode']) for c in manifest[first:first + d['selection']['count']]]
    for label in ('before', 'after'):
        log = (batch / (label + '.log')).read_text()
        assert any(int(s, 16) == int(md5, 16) for s in
                   re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])', log))
    assert (batch / 'final-reset.log').exists()
    for c in d['cases']:
        bus, mode = c['bus'], c['mode']
        key = (bus, mode)
        assert key in expected and key not in seen and c['completed'] and c['final_reset']
        elf = a.manifest.parent / expected[key]['elf']
        image = elf.read_bytes()
        assert sha(image) == c['sha256'] == expected[key]['sha256']
        assert image[:6] == b'\x7fELF\x01\x01'
        phoff = struct.unpack_from('<I', image, 28)[0]
        stride, count = struct.unpack_from('<HH', image, 42)
        executable = []
        for i in range(count):
            header = struct.unpack_from('<8I', image, phoff + i * stride)
            if header[0] == 1 and header[6] & 1:
                executable.append((header[2], header[2] + header[5]))
        label = f'bus{bus}-mode{mode}'
        physical_data = (batch / (label + '.uart')).read_bytes()
        assert sha(physical_data) == c['UART_sha256'] and physical_data.decode() == c['UART']
        n = next(n for n in native['cases'] if (n['bus'], n['mode']) == key)
        native_data = (a.native / (label + '.uart')).read_bytes()
        assert sha(native_data) == n['UART_sha256'] and n['ELF_sha256'] == c['sha256']
        physical_values = parsed(physical_data, bus, mode)
        native_values = parsed(native_data, bus, mode)
        if mode != 3:
            assert all(any(first <= values['PC'] < last for first, last in executable)
                       for values in (physical_values, native_values))
        assert {k: v for k, v in physical_values.items() if k != 'PC'} == {
            k: v for k, v in native_values.items() if k != 'PC'}, (key, 'native/silicon handler mismatch')
        seen[key] = {'bus': bus, 'mode': mode, 'ELF_sha256': c['sha256'],
                     'physical_UART_sha256': sha(physical_data), 'native_UART_sha256': sha(native_data),
                     'physical_EPC': physical_values['PC'], 'native_EPC': native_values['PC'],
                     'semantic_fields_identical': True,
                     'raw_UART_identical': physical_data == native_data,
                     'exact_IRQ_restart_parity': physical_values['PC'] == native_values['PC']}
    cleanup.append({'first': first, 'count': len(d['cases']),
                    'full4MiB_unchanged': True, 'final_reset': True})
assert set(seen) == set(expected)
report = {'verified': True, 'scope_complete': False, 'cases': [seen[k] for k in sorted(seen)],
          'callbacks_verified': 6, 'negative_cases_without_callback': 2,
          'semantics_identical_excluding_EPC': 8, 'exact_IRQ_restart_parity': False,
          'restart_boundary_issue': 'T320', 'cleanup': cleanup,
          'limitations': 'CPU0 level1 RAM handlers for DROM/IROM DATA. Raw EPC arrival '
                        'restart boundary differs from the emulator and remains T320. Blocked-read interrupt '
                        'arbitration, instruction-fetch errors, other buses/levels '
                        'and CPU1 remain open.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:6 silicon handlers/2 masked-bus negatives,8 native matches;fullflash unchanged/reset')
