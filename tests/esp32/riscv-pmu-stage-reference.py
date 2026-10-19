#!/usr/bin/env python3
"""Primary C6 PMU/regulator oracle and real bounded-I2C transaction model.

No C6 CPU, analog hardware or complete power/clock-startup claim.
"""
import argparse
import hashlib
import json
import re
import runpy
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    w, ref = a.work.resolve(), a.reference.resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists()
    for group in ['pmu-primary', 'regi2c-primary', 'startup-primary']:
        rows = json.loads((ref / group / 'provenance.json').read_text())
        if isinstance(rows, dict):
            rows = rows['sources']
        for row in rows:
            if 'sha256' in row:
                assert hashlib.sha256((ref / group / row['path']).read_bytes()).hexdigest() == row['sha256']

    def run(cmd):
        r = subprocess.run(list(map(str, cmd)), cwd=ROOT, capture_output=True, timeout=60)
        assert r.returncode == 0, (cmd, r.stdout[-2000:], r.stderr[-2000:])
        return r.stdout

    pmu = runpy.run_path(str(ROOT / 'tests/esp32/riscv-pmu-state-reference.py'))
    peer, inc = pmu['generate'](w, ref)
    (inc / 'modem').mkdir()
    for f in (ref / 'osi-primary/idf/components/soc/esp32c6/include/modem').glob('*.h'):
        shutil.copy2(f, inc / 'modem' / f.name)
    shutil.copy2(ref / 'regi2c-primary/i2c_ana_mst_reg.h', inc / 'soc/i2c_ana_mst_reg.h')
    shutil.copy2(ref / 'startup-primary/idf/components/soc/esp32c6/include/soc/regi2c_dig_reg.h', inc / 'soc/regi2c_dig_reg.h')
    bus = runpy.run_path(str(ROOT / 'tests/esp32/riscv-regi2c-reference.py'))['C']
    csource = w / 'oracle/all.c'
    csource.write_text(peer.read_text() + '\n' + bus.replace('int main(void)', 'static int dump_bus(void)') + '''
#include "soc/regi2c_dig_reg.h"
int main(void){
 if(dump_bus())return 1;
 uint64_t fields[4]={PMU_RF_PWC_REG,PMU_PERIF_I2C_RSTB|PMU_XPD_PERIF_I2C,EFUSE_RD_MAC_SPI_SYS_3_REG,EFUSE_RD_MAC_SPI_SYS_2_REG};
 fwrite(fields,sizeof(fields),1,stdout);
 uint32_t h=c6_pmu_bias(3,25,0),l=c6_pmu_bias(3,28,1);
 for(uint32_t i=0;i<49;i++){uint64_t row[3]={c6_pmu_row(i,0,h,l),c6_pmu_row(i,1,h,l),c6_pmu_row(i,2,h,l)};fwrite(row,sizeof(row),1,stdout);}
 uint64_t analog[3][4]={
 {I2C_DIG_REG_ENIF_RTC_DREG,I2C_DIG_REG_ENIF_RTC_DREG_MSB,I2C_DIG_REG_ENIF_RTC_DREG_LSB,1},
 {I2C_DIG_REG_ENIF_DIG_DREG,I2C_DIG_REG_ENIF_DIG_DREG_MSB,I2C_DIG_REG_ENIF_DIG_DREG_LSB,1},
 {I2C_DIG_REG_XPD_RTC_REG,I2C_DIG_REG_XPD_DIG_REG_MSB,I2C_DIG_REG_XPD_RTC_REG_LSB,0}};
 fwrite(analog,sizeof(analog),1,stdout);return ferror(stdout);
}
''')
    exe = w / 'oracle/all'
    run(['cc', '-std=c11', '-Wno-cpp', '-I', inc, csource, '-o', exe])
    raw = run([exe])
    initial = list(struct.unpack('<16Q', raw[:128]))
    pac = ref / 'regi2c-primary/pac/i2c_ana_mst'

    def shift(file, name):
        return int(re.search(r'pub fn ' + name + r'\(&mut self\).*?::new\(self, (\d+)\)',
                             (pac / file).read_text(), re.S)[1])

    initial[9:12] = [shift('i2c_ctrl.rs', n) for n in ['slave_reg_addr', 'data', 'read_write']]
    masters = (ref / 'regi2c-primary/hal-c6-regi2c.rs').read_text()
    for name, field in [('BIAS', 'bias'), ('BBPLL', 'bbpll'), ('ULP_CAL', 'ulp_cal'),
                        ('SAR_I2C', 'sar_i2c'), ('DIG_REG', 'dig_reg')]:
        block = int(re.search(r'master: REGI2C_' + name + r'\((0x[0-9a-f]+), 0\)', masters)[1], 16)
        initial += [block, shift('ana_conf1.rs', field + '_rd'), shift('ana_conf2.rs', field + '_mst_sel')]
    expected = w / 'expected.bin'
    expected.write_bytes(struct.pack('<31Q', *initial) + raw[128:])
    assert expected.stat().st_size == 194 * 8
    text = (ROOT / 'tests/esp32/riscv-pmu-stage-model.flex').read_text()
    text = text.replace('../../scripts/', str(ROOT / 'scripts') + '/').replace('../../lib/', str(ROOT / 'lib') + '/')

    def execute(name, source):
        file, binary = w / (name + '.flex'), w / name
        # Replace only this allocation call in an otherwise unchanged module.
        # This lets the full primary-register model exercise failure and retry.
        for imported in re.findall(r'^import "([^"]+)";', source, re.M):
            module_path = Path(imported)
            if not module_path.is_file():
                continue
            module = module_path.read_text()
            if 'fn esp_radio_c6_pmu_stage(cycles)' not in module:
                continue
            assert 'alloc(416)' in module
            module = module.replace('alloc(416)', 'pmu_test_alloc(416)')
            module = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(module_path.parent / m[1]) + '";', module, flags=re.M)
            instrumented = w / (name + '-allocator.flex')
            instrumented.write_text(module)
            source = source.replace(imported, str(instrumented))
        file.write_text(source)
        run(['nice', '-n', '19', a.compiler.resolve(), file, '-o', binary])
        r = subprocess.run([str(binary), str(expected)], cwd=ROOT, capture_output=True, timeout=30)
        (w / (name + '.stdout')).write_bytes(r.stdout)
        (w / (name + '.stderr')).write_bytes(r.stderr)
        return r

    protected = execute('protected', text)
    assert protected.returncode == 0, protected.stderr
    checks = struct.unpack('<Q', protected.stdout)[0]
    port = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
    original = port.read_text()
    defects = [
        ('snapshot-allocation-unchecked', 'if saved<=0{esp32_irq_restore(ps);return -12;}', ''),
        ('snapshot-published-before-check', 'let saved=alloc(416);if saved<=0', 'let saved=alloc(416);esp_radio_pmu_saved=saved;if saved<=0'),
        ('snapshot-failure-IRQ-not-restored', 'if saved<=0{esp32_irq_restore(ps);return -12;}', 'if saved<=0{return -12;}'),
        ('lease-not-published', 'esp_radio_pmu_active=1;', 'esp_radio_pmu_active=0;'),
        ('uncertain-write-not-journaled', 'esp_radio_pmu_analog_count=row+1;result=', 'result='),
        ('wrong-RF-address', '0x600b0154', '0x600b015c'),
        ('wrong-LP-calibration', 'row,hp,lp', 'row,hp,hp'),
        ('RF-state-not-restored', '0x0c000000,esp_radio_pmu_rf_before', '0x0c000000,0'),
        ('uncertain-restore-blind-replay', 'if result!=before{', 'if 1{'),
        ('regulator-restore-omitted', 'while esp_radio_pmu_analog_count{', 'while 0{'),
        ('digital-restore-omitted', 'while esp_radio_pmu_digital_count{', 'while 0{'),
        ('internal-admission-unmasked', 'let ps=esp32_irq_save();if !esp_radio_pmu_active', 'let ps=esp32_irq_save();esp32_irq_restore(ps);if !esp_radio_pmu_active'),
        ('commit-ignores-pending-bus', 'esp_radio_pmu_digital_count!=49 || esp_radio_regi2c_active', 'esp_radio_pmu_digital_count!=49'),
    ]
    detected = []
    for name, before, after in defects:
        assert before in original, name
        mutant = w / (name + '-port.flex')
        module = original.replace(before, after)
        module = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(port.parent / m[1]) + '";', module, flags=re.M)
        mutant.write_text(module)
        r = execute(name, text.replace(str(port), str(mutant)))
        assert r.returncode != 0, name + ' escaped'
        detected.append(dict(name=name, detected=True, result=r.returncode))
    # The PMU owner uses a private internal-bus admission; unrelated callers
    # must remain excluded while its staged state is held.
    bus_port = ROOT / 'lib/platform/esp32c6-radio-regi2c.flex'
    external = w / 'external-bus-port.flex'
    bus_text = bus_port.read_text()
    before = '(esp_radio_pmu_active && !esp_radio_pmu_internal) || '
    assert before in bus_text
    external.write_text(bus_text.replace(before, '').replace('"esp32-analog-state.flex"',
                       '"' + str(bus_port.parent / 'esp32-analog-state.flex') + '"'))
    wrapper = w / 'external-bus-stage.flex'
    module = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(port.parent / m[1]) + '";', original, flags=re.M)
    wrapper.write_text(module.replace(str(bus_port), str(external)))
    r = execute('external-bus-admission', text.replace(str(port), str(wrapper)))
    assert r.returncode != 0, 'external bus admission escaped'
    detected.append(dict(name='external-bus-admission', detected=True, result=r.returncode))
    report = dict(pass_all=True, checks=checks, PMU_rows=49, byte_patterns=256,
                  clock_source_and_master_modes=8, preparation_timeouts=9, rollback_timeouts=9,
                  allocation_failure_IRQ_modes=2, allocation_retry_and_snapshot_reuse=True,
                  detected_defects=detected, C6_CPU_execution=False, physical_hardware=False,
                  full_C6_power_clock_startup=False,
                  compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest())
    (w / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'PMU staging/real-I2C model checks;', len(detected), 'defects; no C6 CPU or RF proof', flush=True)


if __name__ == '__main__':
    main()
