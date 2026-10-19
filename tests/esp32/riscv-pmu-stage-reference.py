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
    p.add_argument('--inputs-only', action='store_true', help='emit primary oracle inputs without running model/defect cases')
    a = p.parse_args()
    w, ref = a.work.resolve(), a.reference.resolve()
    w.mkdir(parents=True, exist_ok=True)
    assert not (w / 'report.json').exists()
    for group in ['pmu-primary', 'regi2c-primary', 'startup-primary', 'osi-primary']:
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
    shutil.copy2(ref / 'startup-primary/idf/components/soc/esp32c6/include/soc/regi2c_lp_bias.h', inc / 'soc/regi2c_lp_bias.h')
    rom_maps = json.loads((ref / 'radio-provenance.json').read_text())['ROM_maps']
    for row in rom_maps:
        assert hashlib.sha256((ref / row['path']).read_bytes()).hexdigest() == row['sha256']
    rom_text = (ref / 'components/esp_rom/esp32c6/ld/esp32c6.rom.ld').read_text()
    reset_address = int(re.search(r'\brtc_get_reset_reason\s*=\s*(0x[0-9a-f]+)', rom_text)[1], 16)
    bus = runpy.run_path(str(ROOT / 'tests/esp32/riscv-regi2c-reference.py'))['C']
    csource = w / 'oracle/all.c'
    csource.write_text(peer.read_text() + '\n' + bus.replace('int main(void)', 'static int dump_bus(void)') + '''
#include "soc/regi2c_dig_reg.h"
#include "soc/regi2c_lp_bias.h"
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
 fwrite(analog,sizeof(analog),1,stdout);
 uint64_t trim[13]={EFUSE_RD_MAC_SPI_SYS_3_REG,EFUSE_RD_SYS_PART1_DATA4_REG,
 EFUSE_BLK_VERSION_MAJOR_S,EFUSE_BLK_VERSION_MINOR_S,EFUSE_OCODE_S,I2C_ULP,
 I2C_ULP_EXT_CODE,I2C_ULP_EXT_CODE_MSB,I2C_ULP_EXT_CODE_LSB,
 I2C_ULP_IR_FORCE_CODE,I2C_ULP_IR_FORCE_CODE_MSB,I2C_ULP_IR_FORCE_CODE_LSB,RESET_ROM_ADDRESS};
 fwrite(trim,sizeof(trim),1,stdout);return ferror(stdout);
}
''')
    csource.write_text(csource.read_text().replace('RESET_ROM_ADDRESS', str(reset_address)))
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
    assert expected.stat().st_size == 207 * 8
    # Execute the actual pinned reset/fuse policy with only its MMIO and
    # software-calibration effects stubbed. Expected policy is not reimplemented.
    def vendor_function(path, name):
        body = path.read_text()
        match = re.search(r'(?:static\s+)?void\s+' + name + r'\([^)]*\)\s*\{', body)
        assert match, name
        end, depth = match.end(), 1
        while depth:
            depth += (body[end] == '{') - (body[end] == '}')
            end += 1
        return body[match.start():end]

    idf = ref / 'startup-primary/idf/components/esp_hw_support/port/esp32c6'
    policy_c = w / 'oracle/ocode-policy.c'
    policy_c.write_text(r'''#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "soc/regi2c_dig_reg.h"
#include "soc/regi2c_lp_bias.h"
static uint32_t reason, version, code, legacy, count, written_code, written_force;
static uint32_t efuse_hal_blk_version(void){return version;}
static uint32_t efuse_ll_get_ocode(void){return code;}
static uint32_t esp_rom_get_reset_reason(uint32_t cpu){assert(!cpu);return reason;}
static void calibrate_ocode(void){legacy=1;}
static void *PMU_instance(void){return 0;}
static void pmu_hp_system_init_default(void *ctx){assert(!ctx);}
static void pmu_lp_system_init_default(void *ctx){assert(!ctx);}
static void pmu_power_domain_force_default(void *ctx){assert(!ctx);}
#define RESET_REASON_CHIP_POWER_ON 1
static void policy_write(uint32_t block,uint32_t reg,uint32_t value){
 if(block!=I2C_ULP)return;
 if(count==0){assert(reg==I2C_ULP_EXT_CODE);written_code=value;}
 else{assert(count==1 && reg==I2C_ULP_IR_FORCE_CODE);written_force=value;}
 count++;
}
#define REGI2C_WRITE_MASK(block,field,value) policy_write(block,field,value)
''' + vendor_function(idf / 'ocode_init.c', 'set_ocode_by_efuse') + '\n'
      + vendor_function(idf / 'ocode_init.c', 'esp_ocode_calib_init') + '\n'
      + vendor_function(idf / 'pmu_init.c', 'pmu_init') + r'''
int main(void){
 uint64_t rows=256*32*4;fwrite(&rows,8,1,stdout);
 uint32_t codes[4]={0,1,0xa7,255};
 for(reason=0;reason<256;reason++)for(uint32_t v=0;v<32;v++)for(uint32_t c=0;c<4;c++){
  version=(v>>3)*100+(v&7);code=codes[c];legacy=count=written_code=written_force=0;pmu_init();
  uint64_t row[7]={reason,v,code,legacy?2:(count?1:0),count,written_code,written_force};
  fwrite(row,sizeof(row),1,stdout);
 }return ferror(stdout);
}
''')
    policy_exe = w / 'oracle/ocode-policy'
    run(['cc', '-std=c11', '-Wno-cpp', '-I', inc, policy_c, '-o', policy_exe])
    policy_data = w / 'ocode-policy.bin'
    policy_data.write_bytes(run([policy_exe]))
    if a.inputs_only:
        print('Primary PMU and vendor-policy inputs emitted; no test execution claim')
        return
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
        r = subprocess.run([str(binary), str(expected), str(policy_data)], cwd=ROOT, capture_output=True, timeout=30)
        (w / (name + '.stdout')).write_bytes(r.stdout)
        (w / (name + '.stderr')).write_bytes(r.stderr)
        return r

    protected = execute('protected', text)
    assert protected.returncode == 0, protected.stderr
    checks = struct.unpack('<Q', protected.stdout)[0]
    port = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
    original = port.read_text()
    defects = [
        ('trim-outer-abort-omitted', 'if esp_radio_ocode_active{result=esp_radio_c6_ocode_abort(cycles);if result{esp32_irq_restore(ps);return result;}}', ''),
        ('trim-uncertain-commit-admitted', ' || (esp_radio_ocode_active && (!esp_radio_ocode_ready || esp_radio_ocode_phase!=1))', ''),
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
    trim_port = ROOT / 'lib/platform/esp32c6-radio-ocode.flex'
    trim_original = trim_port.read_text()
    trim_defects = [
        ('trim-on-warm-reset', 'if reason!=1{', 'if 0{'),
        ('trim-legacy-fuse-admission', 'if !version{', 'if 0{'),
        ('trim-wrong-efuse-field', '>>9)&255', '>>8)&255'),
        ('trim-force-before-code', 'esp_radio_ocode_count=1;result=esp_radio_c6_ocode_bus(0,code,cycles);', 'esp_radio_ocode_count=1;result=esp_radio_c6_ocode_bus(1,1,cycles);'),
        ('trim-write-not-journaled', 'esp_radio_ocode_count=2;result=', 'result='),
        ('trim-restore-blind-replay', 'if result!=before{', 'if 1{'),
        ('trim-snapshot-after-write', 'esp_radio_ocode_before_code=result;', 'esp_radio_ocode_before_code=0;'),
        ('trim-wrong-force-mask', 'high=6;low=6;', 'high=5;low=5;'),
        ('trim-IRQ-restore-omitted', 'esp_radio_ocode_ready=1;esp32_irq_restore(ps);return 0;', 'esp_radio_ocode_ready=1;return 0;'),
    ]
    for name, before, after in trim_defects:
        assert before in trim_original, name
        mutant = w / (name + '-trim.flex')
        mutant.write_text(trim_original.replace(before, after))
        wrapper = w / (name + '-stage.flex')
        module = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(port.parent / m[1]) + '";', original, flags=re.M)
        wrapper.write_text(module.replace(str(trim_port), str(mutant)))
        result = execute(name, text.replace(str(port), str(wrapper)))
        assert result.returncode != 0, name + ' escaped'
        detected.append(dict(name=name, detected=True, result=result.returncode))
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
                  factory_trim_values=256, reset_reasons=256, fuse_versions=32,
                  actual_vendor_policy_vectors=32768,
                  trim_preparation_timeouts=5, trim_rollback_timeouts=5,
                  detected_defects=detected, C6_CPU_execution=False, physical_hardware=False,
                  full_C6_power_clock_startup=False,
                  compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest())
    (w / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'PMU staging/real-I2C model checks;', len(detected), 'defects; no C6 CPU or RF proof', flush=True)


if __name__ == '__main__':
    main()
