#!/usr/bin/env python3
"""Check clock domains against pinned C fields and deliberately broken models.

All tools and primary-source references must already exist; no downloads,
compiler bootstrap, physical hardware access, or firmware-driver imports.
"""
from emulator_sources import source_path, clone_source
import argparse, hashlib, json, re, shutil, subprocess
from pathlib import Path
p = argparse.ArgumentParser(description=__doc__)
for flag in ('compiler', 'reference', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
p.add_argument('--cc', default='cc')
p.add_argument('--skip-controls', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work, refs, compiler = a.work.resolve(), a.reference.resolve(), a.compiler.resolve()
work.mkdir(parents=True, exist_ok=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
headers = {}
for row in json.loads((root / 'tests/xtensa/clock-oracle/sources.json').read_text()):
    assert sha(refs / row['name']) == row['sha256'], row['name'] + ' reference mismatch'
    headers[row['name']] = row['sha256']
def run(args):
    return subprocess.run([str(v) for v in args], cwd=root, capture_output=True, timeout=30)
def checked(args):
    q = run(args)
    assert q.returncode == 0, (args, q.stdout, q.stderr)
    return q
include = work / 'include'
include.mkdir(exist_ok=True)
for original, name in [('sdk-apb-ctrl-reg.h','apb_ctrl_reg.h'), ('sdk-dport-reg.h','dport_reg.h'), ('sdk-regi2c-bbpll.h','regi2c_bbpll.h'), ('soc-rtc-cntl-reg.h','rtc_cntl_reg.h'), ('soc-reg-base.h','reg_base.h')]:
    shutil.copyfile(refs / original, include / name)
constants = [line for line in (refs / 'sdk-clk-tree-ll.h').read_text().splitlines() if line.startswith('#define CLK_LL_BBPLL_')]
assert len(constants) == 9, 'pinned PLL constant definitions'
for name in ('DR_REG_ANA_BASE', 'DR_REG_DPORT_APB_BASE'):
    definitions = [line for line in (refs / 'qemu-reg.h').read_text().splitlines() if line.startswith('#define ' + name + ' ')]
    assert len(definitions) == 1, name
    constants += definitions
(include / 'pll-constants.h').write_text('// Constants copied verbatim from pinned SDK/QEMU sources.\n' + '\n'.join(constants) + '\n')
program = work / 'reference'
checked([a.cc, '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-cpp', '-I' + str(root / 'tests/xtensa/soc-oracle'), '-I' + str(include), root / 'tests/xtensa/clock-oracle/reference.c', '-o', program])
reference = work / 'reference.bin'
reference.write_bytes(checked([program]).stdout)
assert reference.stat().st_size == 41464
fixture = root / 'tests/xtensa/clock-model.flex'
binary = work / 'clock-test'
checked([compiler, fixture, '-o', binary])
q = checked([binary, reference])
match = re.fullmatch(rb'Clock model: (\d+) checks passed\n', q.stdout)
assert match
checks = int(match[1])
modules = ('esp32-emulator.flex', 'esp32-gpio-emulator.flex', 'esp32-gpio-pads.flex', 'esp32-spi-emulator.flex', 'esp32-rmt-emulator.flex', 'esp32-i2c-emulator.flex', 'esp32-i2s-emulator.flex', 'esp32-clock-emulator.flex','esp32-cache-emulator.flex')
sources = {name: clone_source(root,name) for name in modules}
mutations = [
 ('download-profile-has-PLL', 'esp32-clock-emulator.flex', 'if download{se_raw(s,0x3ff48070,1,0x3210);', 'if download{se_raw(s,0x3ff48070,1,0x08003210);'),
 ('ignored-PLL-powerdown', 'esp32-clock-emulator.flex', 'if se_raw(s,0x3ff48000,0,0)&0x40540{return 0;}', ''),
 ('incomplete-PLL-accepted', 'esp32-clock-emulator.flex', 'se_bbpll_byte(s,5)!=0xc6 || ', ''),
 ('wrong-PLL-mode-divider', 'esp32-clock-emulator.flex', 'se_bbpll_byte(s,3)==28', 'se_bbpll_byte(s,3)==32'),
 ('wrong-XTAL-divider', 'esp32-clock-emulator.flex', 'let factor=2*((se_raw(s,0x3ff66000,0,0)&1023)+1);', 'let factor=2;'),
 ('wrong-CPU-period', 'esp32-clock-emulator.flex', 'qpc=6/(period+1);', 'qpc=6;'),
 ('missing-CPU-fraction', 'esp32-clock-emulator.flex', 'store64(p+24,units%6);', 'store64(p+24,0);'),
 ('deadline-rounds-down', 'esp32-clock-emulator.flex', '(units+se_clock_qpc(s)-1)/se_clock_qpc(s)', 'units/se_clock_qpc(s)'),
 ('WAITI-counts-reference-ticks', 'esp32-clock-emulator.flex', 'xt_ccount_advance(cpu,units/se_clock_qpc(s))', 'xt_ccount_advance(cpu,ticks)'),
 ('idle-partial-cycle-counted-twice', 'esp32-clock-emulator.flex', '+load64(p+24)-load64(p+32)', '+load64(p+24)'),
 ('zero-idle-loses-fraction', 'esp32-clock-emulator.flex', 'if !ticks{return se_advance(s,0);}', ''),
 ('missing-live-transition-guard', 'esp32-clock-emulator.flex', 'if (qpc!=load64(p+8) && load64(p+32)) || ((factor!=load64(p+16) || pll!=load64(p+40)) && se_clock_busy(s)){return -16;}', ''),
 ('analog-busy-ignored', 'esp32-clock-emulator.flex', 'if load64(p+64){return -16;}', ''),
 ('wrong-analog-busy-bit', 'esp32-clock-emulator.flex', '(load64(p+64)<<25)', '(load64(p+64)<<24)'),
 ('wrong-analog-data-shift', 'esp32-clock-emulator.flex', '(load8(at)<<16)', '(load8(at)<<8)'),
 ('ignored-analog-delay', 'esp32-clock-emulator.flex', 'load64(s+16)+load64(p+48)', 'load64(s+16)+1'),
 ('missing-analog-power-check', 'esp32-clock-emulator.flex', 'if se_raw(s,0x3ff48000,0,0)&0x40540{return -5;}', ''),
 ('missing-analog-DPORT-alias', 'esp32-clock-emulator.flex', ' || address==0x3ff4e010', ''),
 ('late-analog-event-on-large-advance', 'esp32-emulator.flex', '|load64(se_clock(s)+64)', ''),
 ('timer-ignores-APB-rate', 'esp32-emulator.flex', 'if !se_chip(s){d=d*se_apb_factor(s);}', ''),
 ('UART-ignores-APB-rate', 'esp32-emulator.flex', 'if load64(u+72)&(1<<27){return se_apb_factor(s);}', 'if load64(u+72)&(1<<27){return 1;}'),
 ('UART-reference-follows-APB', 'esp32-emulator.flex', 'return 80;}let clock=', 'return 80*se_apb_factor(s);}let clock='),
 ('SPI-ignores-APB-rate', 'esp32-spi-emulator.flex', 'let factor=se_apb_factor(s);', 'let factor=1;'),
 ('RMT-ignores-APB-rate', 'esp32-rmt-emulator.flex', 'else{n=n*se_apb_factor(s);}', ''),
 ('RMT-filter-ignores-APB-rate', 'esp32-rmt-emulator.flex', 'filter*se_apb_factor(s)', 'filter'),
 ('I2C-fields-ignore-APB-rate', 'esp32-i2c-emulator.flex', 'let scale=se_apb_factor(s);', 'let scale=1;'),
 ('I2C-low-convention-ignores-APB-rate', 'esp32-i2c-emulator.flex', 'em_u32(p+1280)+se_apb_factor(s)', 'em_u32(p+1280)+1'),
 ('I2C-high-convention-ignores-APB-rate', 'esp32-i2c-emulator.flex', '7*se_apb_factor(s)', '7'),
 ('I2C-initial-timeout-ignores-APB-rate', 'esp32-i2c-emulator.flex', 'se_i2c_get(s,bus,12)*se_apb_factor(s)', 'se_i2c_get(s,bus,12)'),
]
controls = []
if not a.skip_controls:
 for label, module, old, new in mutations:
    # Known repeated anchors change together in these defects.
    expected = 2 if label in ('missing-analog-DPORT-alias','I2C-low-convention-ignores-APB-rate','missing-CPU-fraction') else 1
    assert sources[module].count(old) == expected, (label, sources[module].count(old))
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        if name == module:
            text = text.replace(old, new)
        (directory / name).write_text(text.replace('"xtensa.flex"', json.dumps(str(source_path(root,'xtensa.flex')))))
    test = directory / 'test.flex'
    test.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"', json.dumps(str(directory / 'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    mutant = directory / 'test'
    checked([compiler, test, '-o', mutant])
    q = run([mutant, reference])
    assert q.returncode == 1 and re.search(rb'Clock context \d+ check \d+:', q.stderr), (label, 'defect not rejected cleanly', q.returncode, q.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': q.stderr.decode().strip()})
    print('Clock defect controls:', len(controls), flush=True)
report = {'pass': True, 'physical_hardware': False, 'checks': checks, 'C_and_primary_ROM_QEMU_values': 45, 'XTAL_prescalers': 1024, 'PLL_CPU_frequencies_MHz': [80,160,240], 'controls': controls, 'reference_headers': headers, 'reference_sha256': sha(reference), 'compiler_sha256': sha(compiler), 'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest() for name,text in sources.items()}, 'scope': 'Functional40MHz XTAL/SDK PLL tuples,CPU phase,quiescent APB transitions,active CPU-only transitions,analog request scheduling. Electrical timing and live APB phase remain open.'}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:', checks, 'clock checks and', len(controls), 'defect controls')
