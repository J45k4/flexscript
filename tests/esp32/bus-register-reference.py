#!/usr/bin/env python3
"""Compare unchanged ESP32 drivers to pinned Espressif C register declarations.

Supply a local directory containing the official headers listed in
bus-oracle/sources.json (basenames preserved). No compiler or vendor download.
"""
import argparse, hashlib, json, struct, subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--reference', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
p.add_argument('--report', type=Path)
p.add_argument('--cc', default='cc')
a = p.parse_args()
r = Path(__file__).resolve().parents[2]
w = a.work.resolve()
w.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()
def run(args):
    return subprocess.run([str(x) for x in args], cwd=r, capture_output=True)
def checked(args):
    result = run(args)
    assert result.returncode == 0, (args, result.stderr.decode(errors='replace'))
    return result
required = {'spi_struct.h', 'i2c_struct.h', 'spi_reg.h', 'i2c_reg.h', 'dport_reg.h', 'gpio_sig_map.h', 'reg_base.h', 'dport_access.h', 'dport_access.c', 'rtc_io_reg.h'}
headers = {}
for source in json.loads((r/'tests/esp32/bus-oracle/sources.json').read_text()):
    name = Path(source['path']).name
    if name in required:
        data = (a.reference/name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == source['sha256'], name+' reference checksum mismatch'
        headers[name] = source['sha256']
assert set(headers) == required
# Confirm the protected read ordering against the independently pinned source.
dport = (a.reference/'dport_access.c').read_text()
sequence = ['"rsil %[LVL]', '0x3ff40078', '"l32i %[APB]', '"l32i %[REG]', '"wsr  %[LVL]', '"rsync']
position = 0
for instruction in sequence:
    position = dport.index(instruction, position)+len(instruction)

oracle = w/'register-reference'
checked([a.cc, '-std=gnu11', '-O2', '-I'+str(r/'tests/esp32/bus-oracle'), '-I'+str(a.reference.resolve()), r/'tests/esp32/bus-oracle/register-reference.c', '-o', oracle])
reference = w/'reference.bin'
reference.write_bytes(checked([oracle]).stdout)
assert len(reference.read_bytes()) == 984
fixture = r/'tests/esp32/bus-register-model.flex'
model = w/'register-model'
checked([compiler, fixture, '-o', model])
result = checked([model, reference])
assert len(result.stdout) == 8 and not result.stderr
checks, = struct.unpack('<Q', result.stdout)
assert checks >= 9000
controls = []
for label, module, old, new in [
    ('wrong-spi-clock-edge', 'esp32-spi.flex', '((mode&1)^cpol)<<7', '((mode&1)^cpol)<<9'),
    ('wrong-i2c-stop-opcode', 'esp32-i2c.flex', 'esp_i2c_command(base,cmd,3,0,0);', 'esp_i2c_command(base,cmd,2,0,0);'),
    ('old-buffer-bound', 'esp32-common.flex', '0x3ffe0000', '0x3ffd0000'),
    ('wrong-i2c-tx-alias', 'esp32-i2c.flex', '0x6001301c+bus*81920', 'esp_i2c_base(bus)+28'),
    ('missing-i2c-preread', 'esp32-i2c.flex', 'esp32_load32(0x3ff40078);', ''),
    ('unmasked-i2c-rx', 'esp32-i2c.flex', 'fn ei_rx_byte(base) {let ps=esp32_irq_save();', 'fn ei_rx_byte(base) {let ps=0;'),
    ('old-rtc-gpio-pulls', 'esp32.flex', 'let reg=esp_gpio_rtc_descriptor(pin)&255;let bits=384;', 'let reg=0;let bits=384;'),
    ('input-only-rtc-corruption', 'esp32.flex', 'if pin>=34 {if pull {return -22;}return 0;}let address=', 'if pin>=34 && pull {return -22;}let address='),
]:
    directory = w/label
    directory.mkdir(exist_ok=True)
    for name in ['esp32-spi.flex', 'esp32-i2c.flex', 'esp32-common.flex', 'esp32.flex']:
        text = (r/'lib/platform'/name).read_text()
        if name == module:
            assert old in text, label+' control pattern missing'
            text = text.replace(old, new)
        (directory/name).write_text(text)
    text = fixture.read_text()
    for name in ['esp32-spi.flex', 'esp32-i2c.flex']:
        text = text.replace('"../../lib/platform/'+name+'"', json.dumps(str(directory/name)))
    source = directory/'model.flex'
    source.write_text(text)
    binary = directory/'model'
    checked([compiler, source, '-o', binary])
    rejected = run([binary, reference])
    assert rejected.returncode == 1 and len(rejected.stderr) == 16, label+' defect went undetected'
    assertion, count = struct.unpack('<QQ', rejected.stderr)
    controls.append({'control': label, 'detected': True, 'assertion': assertion})
report = {'pass': True, 'native_checks': checks, 'official_register_values': 121, 'reference_headers': headers, 'negative_controls': controls, 'physical_hardware': False}
if a.report:
    a.report.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))
