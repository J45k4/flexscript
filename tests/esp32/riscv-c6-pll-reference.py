#!/usr/bin/env python3
"""Primary C6 PLL power/configuration oracle and owned recovery model.

No physical PLL/analog timing or completed legacy OCODE/RF claim.
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
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--qemu-c6', type=Path)
    parser.add_argument('--inputs-only', action='store_true')
    args = parser.parse_args()
    work, ref, compiler = args.work.resolve(), args.reference.resolve(), args.compiler.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(command, timeout=60):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=timeout)
        assert result.returncode == 0, (command, result.stdout[-1000:], result.stderr[-2500:])
        return result.stdout

    inputs = work / 'pmu-inputs'
    run(['python3', ROOT / 'tests/esp32/riscv-pmu-stage-reference.py', '--compiler', compiler,
         '--reference', ref, '--work', inputs, '--inputs-only'])
    # Additional PCR/SPI/ROM inputs use their original pinned source manifests.
    for name in ['provenance.json', 'register-provenance.json', 'xip-provenance.json']:
        records = json.loads((ref / name).read_text())
        if isinstance(records, dict):
            records = records['sources']
        for row in records:
            if 'sha256' in row:
                assert hashlib.sha256((ref / row['path']).read_bytes()).hexdigest() == row['sha256']
    inc = inputs / 'oracle/include'
    shutil.copy2(ref / 'components/soc/esp32c6/register/soc/pcr_reg.h', inc / 'soc/pcr_reg.h')
    shutil.copy2(ref / 'components/soc/esp32c6/register/soc/spi_mem_reg.h', inc / 'soc/spi_mem_reg.h')
    shutil.copy2(ref / 'components/soc/esp32c6/register/soc/pmu_reg.h', inc / 'soc/pmu_reg.h')
    shutil.copy2(ref / 'startup-primary/idf/components/soc/esp32c6/include/soc/regi2c_bbpll.h', inc / 'soc/regi2c_bbpll.h')
    shutil.copy2(ref / 'regi2c-primary/regi2c_defs.h', inc / 'soc/regi2c_defs.h')
    rom = (ref / 'components/esp_rom/esp32c6/ld/esp32c6.rom.ld').read_text()
    getter = re.search(r'\bets_get_cpu_frequency\s*=\s*(0x[0-9a-f]+)', rom)[1]
    setter = re.search(r'\bets_update_cpu_frequency\s*=\s*(0x[0-9a-f]+)', rom)[1]
    extract = runpy.run_path(str(ROOT / 'tests/esp32/riscv-c6-clock-reference.py'))['extract']
    function = extract(ref / 'pmu-primary/components/hal/esp32c6/include/hal/clk_tree_ll.h', 'clk_ll_bbpll_set_config')
    power_helpers = '\n'.join(extract(ref / 'pmu-primary/components/hal/esp32c6/include/hal/clk_tree_ll.h', name)
                              for name in ['clk_ll_bbpll_enable', 'clk_ll_bbpll_disable'])
    c = work / 'pll-oracle.c'
    c.write_text('''#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "soc/pcr_reg.h"
#include "soc/pmu_reg.h"
#include "soc/spi_mem_reg.h"
#include "soc/regi2c_defs.h"
#include "soc/regi2c_bbpll.h"
#include "modem/modem_syscon_reg.h"
#define HAL_ASSERT assert
#define CLK_LL_PLL_480M_FREQ_MHZ 480
#define SOC_XTAL_FREQ_40M 40
static uint64_t rows[6][5];static unsigned count;
static void trace(uint32_t block,uint32_t reg,uint32_t msb,uint32_t lsb,uint32_t value){assert(count<6);uint64_t row[5]={block,reg,msb,lsb,value};for(unsigned i=0;i<5;i++)rows[count][i]=row[i];count++;}
#define REGI2C_WRITE(block,field,value) trace(block,field,7,0,value)
#define REGI2C_WRITE_MASK(block,field,value) trace(block,field,field##_MSB,field##_LSB,value)
static uint32_t power_addr[4], power_mask[4];static unsigned power_count;
static void trace_power(uint32_t address,uint32_t mask){assert(power_count<4);power_addr[power_count]=address;power_mask[power_count++]=mask;}
#undef SET_PERI_REG_MASK
#define SET_PERI_REG_MASK(address,mask) trace_power(address,mask)
''' + function + '\n' + power_helpers + '''
int main(void){
 uint64_t meta[35]={PMU_IMM_HP_CK_POWER_REG,PMU_CLK_STATE0_REG,I2C_MST_ANA_CONF0_REG,PCR_MSPI_CONF_REG,PCR_USB_DEVICE_CONF_REG,
 MODEM_SYSCON_CLK_CONF_REG,MODEM_SYSCON_CLK_CONF1_REG,PMU_TIE_LOW_GLOBAL_BBPLL_ICG,PMU_TIE_LOW_XPD_BBPLL|PMU_TIE_LOW_XPD_BBPLL_I2C,
 PMU_TIE_HIGH_XPD_BB_I2C|PMU_TIE_HIGH_XPD_BBPLL_I2C|PMU_TIE_HIGH_XPD_BBPLL,PMU_TIE_HIGH_GLOBAL_BBPLL_ICG,
 PMU_ANA_XPD_BB_I2C_STATE_M|PMU_ANA_XPD_BBPLL_I2C_STATE_M|PMU_ANA_XPD_BBPLL_STATE_M|PMU_ICG_GLOBAL_PLL_STATE_M,
 PMU_ANA_XPD_BBPLL_I2C_STATE_M|PMU_ANA_XPD_BBPLL_STATE_M|PMU_ICG_GLOBAL_PLL_STATE_M,I2C_MST_BBPLL_CAL_DONE,I2C_MST_BBPLL_STOP_FORCE_HIGH,I2C_MST_BBPLL_STOP_FORCE_LOW,PCR_MSPI_PLL_CLK_EN_M,
 MODEM_SYSCON_CLK_ETM_EN|MODEM_SYSCON_CLK_ZB_MAC_EN|MODEM_SYSCON_CLK_MODEM_SEC_ECB_EN|MODEM_SYSCON_CLK_MODEM_SEC_CCM_EN|MODEM_SYSCON_CLK_MODEM_SEC_BAH_EN|MODEM_SYSCON_CLK_MODEM_SEC_EN|MODEM_SYSCON_CLK_BLE_TIMER_EN|MODEM_SYSCON_CLK_DATA_DUMP_EN,
 0xffffff&~(MODEM_SYSCON_CLK_WIFI_APB_EN|MODEM_SYSCON_CLK_FE_APB_EN|MODEM_SYSCON_CLK_BT_APB_EN),
 PCR_SYSCLK_CONF_REG,PCR_CPU_FREQ_CONF_REG,PCR_AHB_FREQ_CONF_REG,PCR_APB_FREQ_CONF_REG,PCR_SYSCLK_FREQ_QUERY_0_REG,PCR_GDMA_CONF_REG,PCR_REGDMA_CONF_REG,SPI_MEM_CMD_REG(0),SPI_MEM_CMD_REG(1),GETTER,SETTER,PMU_ANA_XPD_BBPLL_STATE_M,PMU_STABLE_XPD_BBPLL_STATE_M,15,6,PCR_SOC_CLK_SEL_M};
 clk_ll_bbpll_disable();clk_ll_bbpll_enable();assert(power_count==4);
 for(unsigned i=0;i<4;i++){assert(power_addr[i]==meta[0]);assert(power_mask[i]==meta[7+i]);}
 fwrite(meta,sizeof(meta),1,stdout);
 uint64_t consumers[15][4]={
 {PCR_UART0_SCLK_CONF_REG,PCR_UART0_SCLK_EN_M,PCR_UART0_SCLK_SEL_M,2},
 {PCR_UART1_SCLK_CONF_REG,PCR_UART1_SCLK_EN_M,PCR_UART1_SCLK_SEL_M,2},
 {PCR_RMT_SCLK_CONF_REG,PCR_RMT_SCLK_EN_M,PCR_RMT_SCLK_SEL_M,2},
 {PCR_LEDC_SCLK_CONF_REG,PCR_LEDC_SCLK_EN_M,PCR_LEDC_SCLK_SEL_M,2},
 {PCR_TIMERGROUP0_TIMER_CLK_CONF_REG,PCR_TG0_TIMER_CLK_EN_M,PCR_TG0_TIMER_CLK_SEL_M,10},
 {PCR_TIMERGROUP0_WDT_CLK_CONF_REG,PCR_TG0_WDT_CLK_EN_M,PCR_TG0_WDT_CLK_SEL_M,10},
 {PCR_TIMERGROUP1_TIMER_CLK_CONF_REG,PCR_TG1_TIMER_CLK_EN_M,PCR_TG1_TIMER_CLK_SEL_M,10},
 {PCR_TIMERGROUP1_WDT_CLK_CONF_REG,PCR_TG1_WDT_CLK_EN_M,PCR_TG1_WDT_CLK_SEL_M,10},
 {PCR_I2S_TX_CLKM_CONF_REG,PCR_I2S_TX_CLKM_EN_M,PCR_I2S_TX_CLKM_SEL_M,6},
 {PCR_I2S_RX_CLKM_CONF_REG,PCR_I2S_RX_CLKM_EN_M,PCR_I2S_RX_CLKM_SEL_M,6},
 {PCR_SARADC_CLKM_CONF_REG,PCR_SARADC_CLKM_EN_M,PCR_SARADC_CLKM_SEL_M,10},
 {PCR_PWM_CLK_CONF_REG,PCR_PWM_CLKM_EN_M,PCR_PWM_CLKM_SEL_M,2},
 {PCR_PVT_MONITOR_FUNC_CLK_CONF_REG,PCR_PVT_MONITOR_FUNC_CLK_EN_M,PCR_PVT_MONITOR_FUNC_CLK_SEL_M,2},
 {PCR_SPI2_CLKM_CONF_REG,PCR_SPI2_CLKM_EN_M,PCR_SPI2_CLKM_SEL_M,10},
 {PCR_IOMUX_CLK_CONF_REG,PCR_IOMUX_FUNC_CLK_EN_M,PCR_IOMUX_FUNC_CLK_SEL_M,2}};
 fwrite(consumers,sizeof(consumers),1,stdout);clk_ll_bbpll_set_config(480,40);assert(count==6);fwrite(rows,sizeof(rows),1,stdout);return ferror(stdout);
}
'''.replace('GETTER', getter).replace('SETTER', setter))
    oracle = work / 'pll-oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', inc, c, '-o', oracle])
    expected = work / 'expected.bin'
    expected.write_bytes((inputs / 'expected.bin').read_bytes() + run([oracle]))
    assert expected.stat().st_size == 2656
    if args.inputs_only:
        print('Primary PLL/PMU inputs emitted; no test execution claim')
        return
    prefix = (ROOT / 'tests/esp32/riscv-pmu-stage-model.flex').read_text().split('fn main(argc,argv){')[0]
    prefix = prefix.replace('fn esp32_load32(', 'fn pmu_load32(').replace('fn esp32_store32(', 'fn pmu_store32(')
    prefix = prefix.replace('fn esp32_call32(', 'fn pmu_call32(').replace('fn bus_write(', 'fn pmu_bus_write(')
    needle = 'if command&(1<<cv(11)){store8(p,command>>cv(10));}'
    assert needle in prefix
    prefix = prefix.replace(needle, 'if command&(1<<cv(11)){if block==0x66{pll_commit(command);}store8(p,command>>cv(10));}')
    prefix = prefix.replace('h_int(stage_seed)', 'h_int(pll_case)')
    prefix = prefix.replace('../../scripts/', str(ROOT / 'scripts') + '/').replace('../../lib/', str(ROOT / 'lib') + '/')
    body = (ROOT / 'tests/esp32/riscv-c6-pll-model.flex').read_text()
    clock_port, pll_port = ROOT / 'lib/platform/esp32c6-radio-clock.flex', ROOT / 'lib/platform/esp32c6-radio-pll.flex'
    clock_text, pll_text = clock_port.read_text(), pll_port.read_text()

    def execute(name, clock_module, pll_module, bus_module=None):
        clock_module = clock_module.replace('esp32_iram_callback32(esp_radio_c6_clock_begin_iram)', '17').replace('esp32_iram_callback32(esp_radio_c6_clock_restore_iram)', '19')
        clock_module = clock_module.replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex') + '"')
        clock = work / (name + '-clock.flex')
        clock.write_text(clock_module)
        pll_module = pll_module.replace('esp32_iram_callback32(esp_radio_c6_pll_begin_iram)', '21').replace('esp32_iram_callback32(esp_radio_c6_pll_restore_iram)', '23')
        pll_module = pll_module.replace('"esp32c6-radio-clock.flex"', '"' + str(clock) + '"')
        pll = work / (name + '-pll.flex')
        pll.write_text(pll_module)
        head = prefix.index('fn pmu_test_alloc(')
        tail = body.index('fn pcv(')
        model = ('import "' + str(pll) + '";\n' + prefix[:head] + body[:tail]
                 + prefix[head:] + body[tail:])
        if bus_module is not None:
            # PMU and PLL share the same production bus module; substitute its
            # import through one wrapper without changing either caller.
            bus_path = ROOT / 'lib/platform/esp32c6-radio-regi2c.flex'
            fake_bus = work / (name + '-bus.flex')
            fake_bus.write_text(bus_module.replace('"esp32-analog-state.flex"', '"' + str(bus_path.parent / 'esp32-analog-state.flex') + '"'))
            stage = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
            fake_stage = work / (name + '-stage.flex')
            stage_text = re.sub(r'^import "([^\"]+)";', lambda m: 'import "' + str(stage.parent / m[1]) + '";', stage.read_text(), flags=re.M)
            fake_stage.write_text(stage_text.replace(str(bus_path), str(fake_bus)))
            clock.write_text(clock.read_text().replace(str(stage), str(fake_stage)))
            model = model.replace(str(stage), str(fake_stage))
        source, binary = work / (name + '.flex'), work / name
        source.write_text(model)
        run([compiler, source, '-o', binary])
        result = subprocess.run([str(binary), str(expected)], cwd=ROOT, capture_output=True, timeout=30)
        (work / (name + '.stdout')).write_bytes(result.stdout)
        (work / (name + '.stderr')).write_bytes(result.stderr)
        return result

    protected = execute('protected', clock_text, pll_text)
    assert protected.returncode == 0, protected.stderr
    checks = struct.unpack('<Q', protected.stdout)[0]
    controls = []
    for name, before, after in [
        ('analog-master-lease-omitted', 'esp_radio_c6_clock_write(0x600af018,4,4,cycles)', '0'),
        ('analog-master-restore-omitted', 'esp_radio_c6_clock_write(0x600af018,4,esp_radio_pll_old_master_clock,cycles)', '0'),
        ('signed-status-truncated', 'return esp32_call64(', 'return esp32_call32('),
        ('explicit-consumer-ignored', 'esp_radio_pll_consumers || ', ''),
        ('USB-clock-ignored', '(esp32_load32(0x6009608c)&3)==1', '0'),
        ('modem-clock-ignored', '&0xef400000', '&0'),
        ('modem-radio-clock-ignored', '&0xfcfbff', '&0'),
        ('peripheral-clock-ignored', 'if !(value&0x400000)', 'if 1'),
        ('MSPI-route-not-disabled', 'esp_radio_c6_clock_write(0x60096018,4,0,cycles)', '0'),
        ('MSPI-route-not-restored', 'esp_radio_c6_clock_write(0x60096018,4,esp_radio_pll_old_mspi,cycles)', '0'),
        ('global-gate-off-omitted', 'esp32_store32(0x600b00cc,1);', ''),
        ('calibration-gate-omitted', 'if !(esp32_load32(0x600b0194)&0x02000000)', 'if (esp_radio_pll_old_state&0x02000000) && !(esp32_load32(0x600b0194)&0x02000000)'),
        ('PLL-off-omitted', 'esp32_store32(0x600b00cc,0x30);', ''),
        ('power-trigger-replayed', 'esp32_store32(0x600b00cc,missing)', 'esp32_store32(0x600b00cc,0x70000000)'),
        ('USB-analog-ignored', 'if result{return -16;}', ''),
        ('noncanonical-config-accepted', 'if result!=esp_radio_c6_pll_value(row){return -95;}', ''),
        ('preflight-lease-lost', 'if result<0{return result;}', 'if result<0{esp_radio_pll_active=0;return result;}'),
        ('coefficient-order-changed', 'if row==0{return 2;}', 'if row==0{return 3;}'),
        ('coefficient-value-changed', 'if row==4{return 0x73;}', 'if row==4{return 0x72;}'),
        ('matching-coefficients-not-programmed', 'if esp_radio_pll_cal_pending==2', 'if 1'),
        ('uncertain-write-replayed', 'esp_radio_pll_cal_pending=2;', 'esp_radio_pll_cal_pending=1;'),
        ('read-timeout-treated-as-write', 'if esp_radio_regi2c_write_issued', 'if 1'),
        ('settle-omitted', 'while ((esp32_cycles()-start)&0xffffffff)<400{}', ''),
        ('calibration-done-ignored', 'esp_wait_mask(0x600af818,0x1000000,0x1000000,cycles)', '0'),
        ('calibration-start-repeated', 'if esp_radio_pll_cal_step<2', 'if 1'),
        ('calibration-stop-repolls-done', 'if esp_radio_pll_cal_step<3', 'if esp_radio_pll_cal_step<4'),
    ]:
        assert before in pll_text, name
        result = execute(name, clock_text, pll_text.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True, result=result.returncode))
    name = 'CPU-restore-ignores-PLL'
    result = execute(name, clock_text.replace(' || esp_radio_pll_active', ''), pll_text)
    assert result.returncode != 0, name + ' escaped'
    controls.append(dict(name=name, detected=True, result=result.returncode))
    bus_text = (ROOT / 'lib/platform/esp32c6-radio-regi2c.flex').read_text()
    for name, before, after in [
        ('write-issued-journal-missing', 'esp_radio_regi2c_write_issued=1;', ''),
        ('read-marked-as-write', 'esp_radio_regi2c_write_issued=0;', 'esp_radio_regi2c_write_issued=1;'),
    ]:
        assert before in bus_text, name
        result = execute(name, clock_text, pll_text, bus_text.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True, result=result.returncode))

    # Compile real callbacks into both cached profiles and inspect their ELF
    # symbol section/address: this verifies the compiler's actual placement.
    packaging = []
    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    aliases = work / 'empty.ld'
    aliases.write_text('/* No vendor objects or external imports. */\n')
    for target in ['esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf']:
        source = work / (target + '.flex')
        source.write_text('import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\nimport "' + str(pll_port) + '";\nglobal esp_radio_hw_ready=0;\nfn main(){let a=esp_radio_c6_clock_begin(0);if a!=-22{return 1;}let b=esp_radio_c6_clock_restore(0);if b!=-22{return 2;}let c=esp_radio_c6_pll_begin(0);if c!=-22{return 3;}let d=esp_radio_c6_pll_restore(0);if d!=-22{return 4;}return a+b+c+d;}\n')
        elf, linked, image = work / (target + '.elf'), work / (target + '-linked.elf'), work / (target + '.bin')
        run([compiler, '--target', target, source, '-o', elf])
        command = [linker, '--ld', 'ld.lld', '--rom', aliases, '--firmware', elf, '--output', linked, '--image', image]
        if target != 'esp32c6-elf':
            command += ['--xip']
        run(command)
        payload = linked.read_bytes()
        shoff, = struct.unpack_from('<I', payload, 32)
        shsize, shcount, names_index = struct.unpack_from('<HHH', payload, 46)
        assert shsize == 40
        sections = [struct.unpack_from('<10I', payload, shoff + i * 40) for i in range(shcount)]
        found = {}
        for section in sections:
            if section[1] != 2:
                continue
            strings = sections[section[6]]
            pool = payload[strings[4]:strings[4] + strings[5]]
            for pos in range(section[4], section[4] + section[5], 16):
                name, value, size, info, other, index = struct.unpack_from('<IIIBBH', payload, pos)
                label = pool[name:pool.find(b'\0', name)].decode()
                if label in ['esp_radio_c6_clock_begin_iram', 'esp_radio_c6_clock_restore_iram', 'esp_radio_c6_pll_begin_iram', 'esp_radio_c6_pll_restore_iram']:
                    assert 0x40800000 <= value < 0x40810000
                    assert sections[index][2] & 4
                    found[label] = value
        assert len(found) == 4, found
        if args.qemu_c6:
            command = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', args.qemu_c6.resolve(),
                       '--image', image, '--elf', linked, '--report', work / (target + '-ROM.json'), '--expected', -88]
            if target != 'esp32c6-elf':
                command += ['--xip']
            if target == 'esp32c6-radio-elf':
                command += ['--radio']
            run(command)
        packaging.append(dict(target=target, real_IRAM_callbacks=found, executed=bool(args.qemu_c6),
                              execution_scope='invalid-budget signed status through real IRAM wrappers' if args.qemu_c6 else 'package-only',
                              image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, continuous_analog_master_clock=True, canonical_coefficient_writes=6, peripheral_consumer_rows=15,
                  injected_XTAL_lease=True, primary_configuration_function="clk_ll_bbpll_set_config",
                  checks=checks, controls=controls, packaging=packaging, physical_hardware=False, real_PLL_power_or_calibration_verified=False,
                  legacy_software_OCODE_complete=False, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'owned C6 PLL model checks;', len(controls), 'defects;', len(packaging), 'IRAM packages; no physical/analog claim')


if __name__ == '__main__':
    main()
