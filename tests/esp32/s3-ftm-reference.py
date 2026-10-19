#!/usr/bin/env python3
"""Check S3 FTM data against the matching vendor C header and linked ELF.

The target C compiler supplies the independent uint16_t values. No radio,
emulator model or physical device is used by this check.
"""
import argparse, hashlib, json, os, struct, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEADER_SHA = 'e3f3fc0a1e1fb3142f74c825098328c2c25238670e812b17ae0dc0b0cffa8eed'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def sections(data):
    assert data[:7] == b'\x7fELF\x01\x01\x01'
    at = struct.unpack_from('<I', data, 32)[0]
    count, names = struct.unpack_from('<HH', data, 48)
    rows = [struct.unpack_from('<10I', data, at + 40*i) for i in range(count)]
    names = data[rows[names][4]:rows[names][4]+rows[names][5]]
    return rows, {names[r[0]:].split(b'\0', 1)[0].decode(): r for r in rows}

def symbol_table(data):
    rows, named = sections(data)
    sym = named['.symtab']; strings = rows[sym[6]]
    strings = data[strings[4]:strings[4]+strings[5]]
    result = {}
    for at in range(sym[4], sym[4]+sym[5], 16):
        name, value, size, info, other, section = struct.unpack_from('<IIIBBH', data, at)
        name = strings[name:].split(b'\0', 1)[0].decode()
        if section and section < len(rows):
            row = rows[section]
            offset = row[4]+value-row[3]
            result[name] = (offset, size, info, at)
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for k in ['compiler', 'prefix', 'reference', 'elf', 'work']:
        p.add_argument('--'+k, required=True)
    a = p.parse_args(); w = Path(a.work).resolve(); w.mkdir(parents=True, exist_ok=True)
    assert not (w/'report.json').exists(), 'choose a fresh work directory'
    (w/'tmp').mkdir(exist_ok=True); env = os.environ.copy(); env['TMPDIR'] = str(w/'tmp')
    header = Path(a.reference).resolve()/'vendor-ftm_calibration_data.h'
    assert sha(header) == HEADER_SHA
    compiler = Path(a.compiler).resolve(); image = Path(a.elf).resolve()
    def run(command, name, expected=0):
        r = subprocess.run(list(map(str, command)), cwd=ROOT, env=env, capture_output=True, timeout=60)
        (w/(name+'.log')).write_bytes(r.stdout+r.stderr)
        assert r.returncode == expected, (name, r.returncode, (r.stdout+r.stderr)[-1500:])
    # Enumerate the ABI independently of the production coefficient list.
    names = ['est_PHY_'+phase+'_FTM_COMP_'+band+direction+'_MHZ'+suffix
             for band in ['20_20', '20_40', '40_40'] for phase in ['INIT', 'RESP']
             for direction in ['U', 'D'] for suffix in ['', '_DIS']]
    assert len(names) == 24
    (w/'sdkconfig.h').write_text('#define CONFIG_ESP_WIFI_FTM_ENABLE 1\n#define CONFIG_IDF_TARGET_ESP32S3 1\n')
    oracle = w/'oracle.c'
    oracle.write_text('#include <stdint.h>\n#include '+json.dumps(str(header))+'\n'
        '__attribute__((section(".rodata.ftm"),used)) const uint16_t ftm_values[]={\n'+
        ',\n'.join(n.replace('est_PHY_', 'EST_PHY_') for n in names)+'\n};\n')
    run([a.prefix+'gcc', '-I', w, '-Os', '-ffreestanding', '-c', oracle, '-o', w/'oracle.o'], 'oracle')
    run([a.prefix+'objcopy', '-O', 'binary', '-j', '.rodata.ftm', w/'oracle.o', w/'oracle.bin'], 'values')
    values = struct.unpack('<24H', (w/'oracle.bin').read_bytes())
    expected = dict(zip(names, values)); data = image.read_bytes(); symbols = symbol_table(data)
    def verify(payload, table):
        for name, value in expected.items():
            offset, size, info, _ = table[name]
            assert size == 2 and info == 17, (name, size, info)
            assert struct.unpack_from('<H', payload, offset)[0] == value, name
    verify(data, symbols)
    detected = []
    for name in names:
        damaged = bytearray(data); damaged[symbols[name][0]] ^= 1
        try: verify(damaged, symbols)
        except AssertionError: detected.append(name+':value')
        else: raise AssertionError(name+' value defect escaped')
        damaged = bytearray(data); struct.pack_into('<I', damaged, symbols[name][3]+8, 4)
        try: verify(damaged, symbol_table(damaged))
        except AssertionError: detected.append(name+':width')
        else: raise AssertionError(name+' width defect escaped')
    tool = w/'data-object'
    run([compiler, ROOT/'scripts/esp32-data-object.flex', '-o', tool], 'tool')
    successes = []
    for size, value in [(1,0),(1,255),(2,65535),(3,16777215),(4,4294967295),(484,None),(32768,None)]:
        dest = w/f'object-{size}-{value}.o'
        command = [tool, '--symbol', 'test_data', '--size', size, '--output', dest]
        if value is not None: command += ['--value', value]
        run(command, dest.stem)
        payload = dest.read_bytes(); offset, extent, info, _ = symbol_table(payload)['test_data']
        assert extent == size and info == 17
        assert payload[offset:offset+size] == (value or 0).to_bytes(size, 'little')
        saved = sha(dest); run(command, dest.stem+'-repeat'); assert sha(dest) == saved
        successes.append([size, value])
    rejections = []
    for size, value in [(0,None),(32769,None),(5,1),(1,-1),(1,256),(2,65536),(3,16777216),(4,4294967296)]:
        dest = w/'preserved.o'; dest.write_bytes(b'preserve existing output\n'); before = sha(dest)
        command = [tool, '--symbol', 'test_data', '--size', size, '--output', dest]
        if value is not None: command += ['--value', value]
        run(command, f'reject-{size}-{value}', 1); assert sha(dest) == before
        rejections.append([size, value])
    report = dict(pass_all=True, coefficients=expected, header_sha256=sha(header), elf_sha256=sha(image),
        oracle_sha256=sha(w/'oracle.o'), defects=detected, initialized_and_zero_objects=successes,
        preserved_output_rejections=rejections, physical_hardware=False, emulator_changes=False,
        source_sha256={str(p):sha(p) for p in [Path(__file__), ROOT/'scripts/esp32-data-object.flex', ROOT/'scripts/lib/esp32s3-ftm.flex']})
    (w/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS: 24 vendor-header uint16 coefficients, 48 isolated defects, 7 object boundaries, 8 preserved-output rejections')

if __name__ == '__main__':
    main()
