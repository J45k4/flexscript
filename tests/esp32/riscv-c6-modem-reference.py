#!/usr/bin/env python3
"""Primary C6 modem policy, owned staging/recovery and native admission checks."""
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


def extract_function(path, name):
    text = path.read_text()
    match = re.search(r'(?:void|uint32_t)\s+(?:IRAM_ATTR\s+)?' + name + r'\([^)]*\)\s*\{', text)
    assert match, name
    end, depth = match.end(), 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[match.start():end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--qemu-c6', type=Path)
    args = parser.parse_args()
    compiler, ref, work = args.compiler.resolve(), args.reference.resolve(), args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    for group in ['startup-primary', 'pmu-primary', 'osi-primary']:
        rows = json.loads((ref / group / 'provenance.json').read_text())
        if isinstance(rows, dict):
            rows = rows['sources']
        for row in rows:
            if 'sha256' in row:
                assert hashlib.sha256((ref / group / row['path']).read_bytes()).hexdigest() == row['sha256']

    def run(command):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=60)
        assert result.returncode == 0, (command, result.stdout[-2000:], result.stderr[-2500:])
        return result.stdout

    primary = ref / 'startup-primary/idf/components'
    inc = work / 'include'
    for name in ['soc', 'hal', 'modem']:
        (inc / name).mkdir(parents=True, exist_ok=True)
    for name in ['modem_lpcon', 'modem_syscon']:
        shutil.copy2(primary / ('soc/esp32c6/include/modem/' + name + '_struct.h'), inc / ('modem/' + name + '_struct.h'))
        shutil.copy2(primary / ('hal/esp32c6/include/hal/' + name + '_ll.h'), inc / ('hal/' + name + '_ll.h'))
    (inc / 'soc/soc.h').write_text('#pragma once\n')
    (inc / 'hal/assert.h').write_text('#include <assert.h>\n#define HAL_ASSERT assert\n')
    domains = ['MODEM_APB', 'MODEM_PERIPH', 'WIFI', 'BT', 'MODEM_FE', 'IEEE802154', 'LP_APB', 'I2C_MASTER', 'COEX', 'WIFIPWR']
    sources = ['RC_SLOW', 'RC_FAST', 'MAIN_XTAL', 'RC32K', 'XTAL32K', 'EXT32K']
    # Symbolic HAL switch inputs; their numeric discriminants are irrelevant to
    # the public API mapping, which is recorded explicitly by the C oracle.
    (inc / 'hal/modem_clock_types.h').write_text('#pragma once\n#include <stdint.h>\ntypedef enum {' + ','.join('MODEM_CLOCK_DOMAIN_' + n for n in domains) + ',MODEM_CLOCK_DOMAIN_MAX} modem_clock_domain_t;\ntypedef enum {' + ','.join('MODEM_CLOCK_LPCLK_SRC_' + n for n in sources) + ',MODEM_CLOCK_LPCLK_SRC_MAX} modem_clock_lpclk_src_t;\n')
    hal = primary / 'hal/esp32c6/modem_clock_hal.c'
    policy = (primary / 'esp_hw_support/modem_clock.c').read_text()
    table = re.search(r'static const DRAM_ATTR uint32_t initial_gating_mode\[MODEM_CLOCK_DOMAIN_MAX\] = \{.*?\};', policy, re.S)[0]
    functions = '\n'.join(extract_function(hal, n) for n in ['modem_clock_hal_get_clock_domain_icg_bitmap', 'modem_clock_hal_set_clock_domain_icg_bitmap', 'modem_clock_hal_deselect_all_wifi_lpclk_source', 'modem_clock_hal_select_wifi_lpclk_source'])
    c = work / 'oracle.c'
    c.write_text(r'''#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "hal/modem_syscon_ll.h"
#include "hal/modem_lpcon_ll.h"
#define IRAM_ATTR
#define DRAM_ATTR
#define ICG_NOGATING_ACTIVE (1U<<2)
#define ICG_NOGATING_MODEM (1U<<1)
#define ICG_NOGATING_SLEEP (1U<<0)
typedef struct {modem_syscon_dev_t *syscon_dev;modem_lpcon_dev_t *lpcon_dev;} modem_clock_hal_context_t;
enum {MODEM_CLOCK_XTAL32K_CODE,MODEM_CLOCK_RC32K_CODE,MODEM_CLOCK_EXT32K_CODE};
''' + table + '\n' + functions + r'''
int main(void){
 uint64_t meta[]={6*4096,0x600a9800+offsetof(modem_syscon_dev_t,clk_conf_power_st),0x600af000+offsetof(modem_lpcon_dev_t,clk_conf_power_st),0x600af000+offsetof(modem_lpcon_dev_t,wifi_lp_clk_conf),0x600af000+offsetof(modem_lpcon_dev_t,modem_32k_clk_conf),0x600af000+offsetof(modem_lpcon_dev_t,clk_conf)};
 fwrite(meta,sizeof(meta),1,stdout);
 for(unsigned source=0;source<6;source++)for(unsigned divider=0;divider<4096;divider++){
  uint32_t seed=(divider*1103515245U+source*1664525U+12345U);modem_syscon_dev_t sys={0};modem_lpcon_dev_t lp={0};modem_clock_hal_context_t h={&sys,&lp};
  sys.clk_conf_power_st.val=seed;lp.clk_conf_power_st.val=seed^0xa5a5a5a5;lp.wifi_lp_clk_conf.val=seed^0x5a5a5a5a;lp.modem_32k_clk_conf.val=seed^0x55aaff00;lp.clk_conf.val=seed&~10U;
  uint64_t row[12]={source,divider,sys.clk_conf_power_st.val,lp.clk_conf_power_st.val,lp.wifi_lp_clk_conf.val,lp.modem_32k_clk_conf.val,lp.clk_conf.val};
  for(unsigned domain=0;domain<MODEM_CLOCK_DOMAIN_MAX;domain++){uint32_t old=modem_clock_hal_get_clock_domain_icg_bitmap(&h,domain);modem_clock_hal_set_clock_domain_icg_bitmap(&h,domain,old|initial_gating_mode[domain]);}
  modem_clock_hal_deselect_all_wifi_lpclk_source(&h);modem_clock_hal_select_wifi_lpclk_source(&h,source);modem_lpcon_ll_set_wifi_lpclk_divisor_value(&lp,divider);modem_lpcon_ll_enable_wifipwr_clock(&lp,true);
  row[7]=sys.clk_conf_power_st.val;row[8]=lp.clk_conf_power_st.val;row[9]=lp.wifi_lp_clk_conf.val;row[10]=lp.modem_32k_clk_conf.val;row[11]=lp.clk_conf.val;fwrite(row,sizeof(row),1,stdout);
 }return ferror(stdout);
}
''')
    oracle = work / 'oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-I', inc, c, '-o', oracle])
    expected = work / 'expected.bin'
    expected.write_bytes(run([oracle]))
    model = (ROOT / 'tests/esp32/riscv-c6-modem-model.flex').read_text().replace('../../scripts/', str(ROOT / 'scripts') + '/')
    port = ROOT / 'lib/platform/esp32c6-radio-modem.flex'
    original = port.read_text()
    stage = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
    common = stage.read_text()

    pll = (ROOT / 'lib/platform/esp32c6-radio-pll.flex').read_text()
    consumer = re.search(r'^fn esp_radio_c6_pll_consumer\(.*?^}', pll, re.M | re.S)[0]
    model = model.replace('global cfg=0;', 'global esp_radio_pll_consumers=0;\nglobal cfg=0;') + '\n' + consumer + '\n'

    def execute(name, module, stage_text=common, pll_consumer=consumer):
        fake_stage = work / (name + '-PMU.flex')
        fake_stage.write_text(re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(stage.parent / m[1]) + '";', stage_text, flags=re.M))
        module = module.replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(fake_stage) + '"')
        fake = work / (name + '-port.flex')
        fake.write_text(module)
        source, binary = work / (name + '.flex'), work / name
        text = model.replace(consumer, pll_consumer).replace('"../../lib/platform/esp32c6-radio-modem.flex"', '"' + str(fake) + '"').replace('../../lib/', str(ROOT / 'lib') + '/')
        text = '\n'.join(line if line.startswith('fn check_at(') else re.sub(r'(?<!fn )\bcheck\(', 'check_at(' + str(i) + ',', line) for i, line in enumerate(text.splitlines(), 1)) + '\n'
        source.write_text(text)
        run([compiler, source, '-o', binary])
        result = subprocess.run([binary, expected], cwd=ROOT, capture_output=True, timeout=30)
        (work / (name + '.stderr')).write_bytes(result.stderr)
        return result

    protected = execute('protected', original)
    assert protected.returncode == 0, (protected.returncode, protected.stderr)
    checks = struct.unpack('<Q', protected.stdout)[0]
    controls = []
    for name, before, after in [
        ('wrong-BT-or-ZB-mode', '0x64646400', '0x64666600'),
        ('existing-ICG-bits-lost', 'esp_radio_modem_sys_map|0x64646400', '0x64646400'),
        ('LP-map-omitted', 'esp_radio_modem_lp_map|0x66660000', 'esp_radio_modem_lp_map'),
        ('divider-truncated', 'divider<<4', '(divider&255)<<4'),
        ('wrong-32k-code', 'if source==3{code=1;}', 'if source==3{code=0;}'),
        ('shared-32k-user-ignored', 'code!=selected &&', '0 &&'),
        ('forced-clock-admitted', 'esp32_load32(0x600af01c)&11', 'esp32_load32(0x600af01c)&10'),
        ('WiFi-clock-not-gated', 'modem_put(0x600af018,1,0,cycles)', 'modem_put(0x600af018,1,1,cycles)'),
        ('source-not-deselected', 'modem_put(0x600af00c,15,0,cycles)', 'modem_put(0x600af00c,15,esp_radio_modem_wifi,cycles)'),
        ('failure-lease-lost', 'if result{esp_radio_modem_error=result;', 'if result{esp_radio_modem_active=0;esp_radio_modem_error=result;'),
        ('original-IRQ-lost', 'esp32_irq_restore(esp_radio_modem_ps)', 'esp32_irq_restore(0)'),
        ('caller-IRQ-released-early', 'esp_radio_modem_internal=0;if result', 'esp32_irq_restore(esp_radio_modem_ps);esp_radio_modem_internal=0;if result'),
        ('primary-error-overwritten', 'esp_radio_modem_cleanup_error=result;', 'esp_radio_modem_error=result;esp_radio_modem_cleanup_error=result;'),
        ('cleanup-error-hidden', 'esp_radio_modem_cleanup_error=result;', 'esp_radio_modem_cleanup_error=0;'),
        ('uncertain-write-replayed', 'if (esp32_load32(address)&mask)!=value', 'if 1'),
        ('late-completion-accepted', 'let observed=esp32_load32(address)&mask;\n  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}', 'let observed=esp32_load32(address)&mask;'),
        ('PMU-commit-omitted', 'let result=esp_radio_c6_pmu_commit();', 'let result=0;'),
    ]:
        assert before in original, name
        result = execute(name, original.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True))
    for name, before, after in [
        ('outer-PMU-abort-admitted', 'if esp_radio_modem_active && !esp_radio_modem_internal{return -16;}', ''),
        ('public-analog-admitted', 'if esp_radio_modem_active && !esp_radio_modem_internal{esp32_irq_restore(ps);return -16;}', ''),
    ]:
        assert before in common, name
        result = execute(name, original, common.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True))
    before = ' || (esp_radio_modem_active && !esp_radio_modem_internal)'
    assert before in consumer
    result = execute('PLL-consumer-admitted', original, pll_consumer=consumer.replace(before, ''))
    assert result.returncode != 0, 'PLL-consumer-admitted escaped'
    controls.append(dict(name='PLL-consumer-admitted', detected=True))
    # Native status fixtures execute only rejected/unprepared calls; valid
    # modem writes remain host-model evidence, not QEMU or physical proof.
    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    aliases = work / 'empty.ld'
    aliases.write_text('/* no vendor imports */\n')
    packaging = []
    for target in ['esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf']:
        source = work / (target + '.flex')
        source.write_text('import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\nimport "' + str(port) + '";\nglobal esp_radio_hw_ready=0;\nfn main(){if esp_radio_c6_modem_stage(0,0,0)!=-22 || esp_radio_c6_modem_abort(0)!=-22 || esp_radio_c6_modem_commit()!=-16{return 1;}if esp_radio_c6_modem_stage(0,0,1000)!=-16 || esp_radio_c6_modem_abort(1000)!=-16{return 2;}esp_radio_owner=1;if esp_radio_c6_modem_stage(0,0,1000)!=-16 || esp_radio_c6_modem_abort(1000)!=0{return 3;}return 0;}\n')
        elf, linked, image = work / (target + '.elf'), work / (target + '-linked.elf'), work / (target + '.bin')
        run([compiler, '--target', target, source, '-o', elf])
        command = [linker, '--ld', 'ld.lld', '--rom', aliases, '--firmware', elf, '--output', linked, '--image', image]
        if target != 'esp32c6-elf':
            command += ['--xip']
        run(command)
        if args.qemu_c6:
            command = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', args.qemu_c6.resolve(), '--image', image, '--elf', linked, '--report', work / (target + '-ROM.json')]
            if target != 'esp32c6-elf':
                command += ['--xip']
            if target == 'esp32c6-radio-elf':
                command += ['--radio']
            run(command)
        packaging.append(dict(target=target, executed=bool(args.qemu_c6), execution_scope='invalid arguments and unprepared ownership only', image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, checks=checks, primary_C_policy_vectors=24576, controls=controls, packaging=packaging, physical_hardware=False, valid_modem_MMIO_execution=False, PMU_immediate_activation=False, full_C6_PHY_startup=False, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'C6 modem model checks;', len(controls), 'defects;', len(packaging), 'native status profiles; no physical claim')


if __name__ == '__main__':
    main()
