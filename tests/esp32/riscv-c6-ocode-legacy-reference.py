#!/usr/bin/env python3
"""Pinned legacy C6 OCODE sequence oracle and owned failure/recovery model.

The legacy cohort injects an XTAL lease; --coordinator executes real clock
handoff helpers. Physical bandgap/PLL/analog timing is unverified.
"""
import argparse
import hashlib
import json
import re
import runpy
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def extract_void(path, name):
    source = path.read_text()
    match = re.search(r'(?:static\s+)?void\s+' + name + r'\([^)]*\)\s*\{', source)
    assert match
    end, depth = match.end(), 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--qemu-c6', type=Path)
    parser.add_argument('--coordinator', action='store_true', help='exercise composed policy/clock/PLL recovery')
    args = parser.parse_args()
    compiler, ref, work = args.compiler.resolve(), args.reference.resolve(), args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(command):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=60)
        assert result.returncode == 0, (command, result.stdout[-1000:], result.stderr[-2500:])
        return result.stdout

    inputs = work / 'PLL-inputs'
    run(['python3', ROOT / 'tests/esp32/riscv-c6-pll-reference.py', '--compiler', compiler,
         '--reference', ref, '--work', inputs, '--inputs-only'])
    vendor = ref / 'startup-primary/idf/components/esp_hw_support/port/esp32c6/ocode_init.c'
    c = work / 'legacy-oracle.c'
    c.write_text(r'''#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "soc/regi2c_lp_bias.h"
typedef int soc_rtc_slow_clk_src_t;
typedef int rtc_cal_sel_t;
typedef struct {int source;} rtc_cpu_freq_config_t;
#define RTC_CAL_RTC_MUX 0
#define SOC_RTC_SLOW_CLK_SRC_OSC_SLOW 1
#define RTC_CAL_32K_OSC_SLOW 1
#define SOC_RTC_SLOW_CLK_SRC_XTAL32K 2
#define RTC_CAL_32K_XTAL 2
static uint32_t flags, time_now, clock_on, enabled, disabled, restored, reset_count, timeout, on_xtal;
static soc_rtc_slow_clk_src_t rtc_clk_slow_src_get(void){return 0;}
static uint32_t rtc_clk_cal(rtc_cal_sel_t s,uint32_t n){assert(!s && n==100);return 1;}
static uint64_t rtc_time_us_to_slowclk(uint64_t us,uint32_t period){assert(us==10000 && period==1);return 10;}
static uint64_t rtc_time_get(void){return time_now++;}
static void rtc_clk_cpu_freq_get_config(rtc_cpu_freq_config_t *c){assert(!clock_on && !on_xtal);c->source=1;}
static void rtc_clk_cpu_freq_set_xtal(void){assert(!clock_on);on_xtal=1;}
static void rtc_clk_cpu_freq_set_config(rtc_cpu_freq_config_t *c){assert(!clock_on && on_xtal && c->source==1);on_xtal=0;restored++;}
static void analog_clock(bool enable){assert(on_xtal);clock_on=enable;if(enable)enabled++;else disabled++;}
static void reset_write(uint32_t block,uint32_t reg,uint32_t value){assert(clock_on && on_xtal && block==I2C_ULP && reg==I2C_ULP_IR_RESETB && value==reset_count);reset_count++;}
static uint32_t flag_read(uint32_t block,uint32_t reg,uint32_t msb,uint32_t lsb){assert(clock_on && on_xtal && reset_count==2 && block==I2C_ULP && reg==3);return(flags>>lsb)&((1U<<(msb-lsb+1))-1);}
#define ANALOG_CLOCK_ENABLE() analog_clock(true)
#define ANALOG_CLOCK_DISABLE() analog_clock(false)
#define REGI2C_WRITE_MASK(block,field,value) reset_write(block,field,value)
#define REGI2C_READ_MASK(block,field) flag_read(block,field,field##_MSB,field##_LSB)
#define ESP_HW_LOGW(...) do {timeout=1;} while(0)
''' + extract_void(vendor, 'calibrate_ocode') + r'''
int main(void){
 uint64_t meta[10]={I2C_ULP,I2C_ULP_IR_RESETB,I2C_ULP_IR_RESETB_LSB,I2C_ULP_O_DONE_FLAG,I2C_ULP_O_DONE_FLAG_LSB,I2C_ULP_BG_O_DONE_FLAG_LSB,
 (1U<<I2C_ULP_O_DONE_FLAG_LSB)|(1U<<I2C_ULP_BG_O_DONE_FLAG_LSB),400000,10000,16};fwrite(meta,sizeof(meta),1,stdout);
 for(flags=0;flags<16;flags++){time_now=clock_on=enabled=disabled=restored=reset_count=timeout=on_xtal=0;calibrate_ocode();assert(!clock_on && !on_xtal && enabled==1 && disabled==1 && restored==1 && reset_count==2);
  uint64_t row[6]={flags,!timeout,reset_count,enabled,disabled,restored};fwrite(row,sizeof(row),1,stdout);}
 return ferror(stdout);
}
''')
    oracle = work / 'legacy-oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', inputs / 'pmu-inputs/oracle/include', c, '-o', oracle])
    expected = work / 'expected.bin'
    expected.write_bytes((inputs / 'expected.bin').read_bytes() + run([oracle]))
    assert expected.stat().st_size == 3504
    pmu = (ROOT / 'tests/esp32/riscv-pmu-stage-model.flex').read_text().split('fn main(argc,argv){')[0]
    pmu = pmu.replace('fn esp32_load32(', 'fn pmu_load32(').replace('fn esp32_store32(', 'fn pmu_store32(')
    pmu = pmu.replace('fn esp32_call32(', 'fn pmu_call32(').replace('fn bus_write(', 'fn pmu_bus_write(')
    needle = 'if command&(1<<cv(11)){store8(p,command>>cv(10));}else{'
    assert needle in pmu
    pmu = pmu.replace(needle, 'if command&(1<<cv(11)){if block==0x66{pll_commit(command);}if block==0x61{cal_commit(command);}store8(p,command>>cv(10));}else{cal_read(block,reg);')
    # Existing factory-trim instrumentation handles registers5/6; legacy reset
    # register0 is separately checked against its primary fields above.
    pmu = pmu.replace('(value&255)==tv(5) && (value&(1<<cv(11)))', '(value&255)==tv(5) && ((value>>cv(9))&255)!=0 && (value&(1<<cv(11)))')
    pmu = pmu.replace('h_int(stage_seed)', 'h_int(pll_case)').replace('../../scripts/', str(ROOT / 'scripts') + '/').replace('../../lib/', str(ROOT / 'lib') + '/')
    pll_model = (ROOT / 'tests/esp32/riscv-c6-pll-model.flex').read_text().split('fn main(argc,argv){')[0]
    pll_model = pll_model.replace('if address==17{return', 'if address==25{return esp_radio_c6_ocode_legacy_stage_iram(a,b,c,d,e,f,g,h);}if address==27{return esp_radio_c6_ocode_legacy_abort_iram(a,b,c,d,e,f,g,h);}if address==17{return')
    pll_model = pll_model.replace('if address==17 || address==19 || address==21 || address==23', 'if address==25 || address==27 || address==17 || address==19 || address==21 || address==23')
    pll_model = pll_model.replace('if address==pcv(0){', 'if address==pcv(0){if value&pcv(9){check(!cal_running);}')
    pll_model = pll_model.replace('if address==cv(5){', 'if address==cv(5){if cal_running{check((value&cv(12))==cv(12));}')
    body = (ROOT / 'tests/esp32/riscv-c6-ocode-legacy-model.flex').read_text()
    flow_port = ROOT / 'lib/platform/esp32c6-radio-calibration.flex'
    flow_original = flow_port.read_text() if args.coordinator else None
    if args.coordinator:
        helpers = body.split('fn main(argc,argv){')[0]
        flow = (ROOT / 'tests/esp32/riscv-c6-calibration-model.flex').read_text()
        location, first = helpers.index('fn ocv('), flow.index('fn flow_reset(')
        body = helpers[:location] + flow[:first] + helpers[location:] + flow[first:]
        pmu = pmu.replace('fn esp32_irq_restore(value){', 'fn esp32_irq_restore(value){if esp_radio_calibration_active{check(!(value&8));}')
        pll_model = pll_model.replace('if address==pcv(19){check(', 'if address==pcv(19){if flow_ignore_restore_root && (value&0x30000)==0x10000{return 0;}check(')
    port = ROOT / 'lib/platform/esp32c6-radio-ocode-legacy.flex'
    original = port.read_text()
    common = ROOT / 'lib/platform/esp32c6-radio-ocode.flex'
    common_text = common.read_text()

    def execute(name, legacy_module, common_module, flow_module=None, stage_module=None, pll_module=None):
        stage = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
        fake_common = work / (name + '-ocode.flex')
        fake_common.write_text(common_module)
        fake_stage = work / (name + '-stage.flex')
        stage_text = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(stage.parent / m[1]) + '";', (stage_module if stage_module is not None else stage.read_text()), flags=re.M)
        fake_stage.write_text(stage_text.replace(str(common), str(fake_common)))
        clock = work / (name + '-clock.flex')
        clock_text = (ROOT / 'lib/platform/esp32c6-radio-clock.flex').read_text().replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(fake_stage) + '"')
        for label, number in [('begin', 17), ('restore', 19)]:
            clock_text = clock_text.replace('esp32_iram_callback32(esp_radio_c6_clock_' + label + '_iram)', str(number))
        clock.write_text(clock_text)
        pll = work / (name + '-PLL.flex')
        pll_text = (pll_module if pll_module is not None else (ROOT / 'lib/platform/esp32c6-radio-pll.flex').read_text()).replace('"esp32c6-radio-clock.flex"', '"' + str(clock) + '"')
        for label, number in [('begin', 21), ('restore', 23)]:
            pll_text = pll_text.replace('esp32_iram_callback32(esp_radio_c6_pll_' + label + '_iram)', str(number))
        pll.write_text(pll_text)
        legacy = work / (name + '-legacy.flex')
        legacy_module = legacy_module.replace('"esp32c6-radio-pll.flex"', '"' + str(pll) + '"')
        for label, number in [('stage', 25), ('abort', 27)]:
            legacy_module = legacy_module.replace('esp32_iram_callback32(esp_radio_c6_ocode_legacy_' + label + '_iram)', str(number))
        legacy.write_text(legacy_module)
        entry = legacy
        if args.coordinator:
            entry = work / (name + '-flow.flex')
            entry.write_text((flow_module if flow_module is not None else flow_original).replace('"esp32c6-radio-ocode-legacy.flex"', '"' + str(legacy) + '"'))
        a, b, c = pmu.index('fn pmu_test_alloc('), pll_model.index('fn pcv('), body.index('fn ocv(')
        text = ('import "' + str(entry) + '";\n' + pmu[:a] + pll_model[:b] + body[:c]
                + pmu[a:] + pll_model[b:] + body[c:]).replace(str(stage), str(fake_stage))
        text = '\n'.join(re.sub(r'(?<!fn )\bcheck\(', 'check_at(' + str(i) + ',', line)
                         for i, line in enumerate(text.splitlines(), 1)) + '\n'
        location = text.index('fn pmu_test_alloc(')
        text = text[:location] + 'fn check_at(line,ok){if !ok{h_print(2,h_cat3("line ",h_int(line)," failed\\n"));}return check(ok); }\n' + text[location:]
        source, binary = work / (name + '.flex'), work / name
        source.write_text(text)
        run([compiler, source, '-o', binary])
        command = [str(binary), str(expected)]
        if args.coordinator:
            command += [str(inputs / 'pmu-inputs/ocode-policy.bin')]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        (work / (name + '.stderr')).write_bytes(result.stderr)
        return result

    protected = execute('protected', original, common_text)
    assert protected.returncode == 0, protected.stderr
    checks = struct.unpack('<Q', protected.stdout)[0]
    if args.coordinator:
        controls = []
        for name, before, after in [
            ('wrong-reset-policy', 'if reason==1', 'if reason!=1'),
            ('legacy-fuse-route-lost', 'if !(esp32_load32(0x600b0850)&0xf8000000)', 'if 0'),
            ('clock-begin-omitted', 'result=esp_radio_c6_clock_begin(cycles);', 'result=0;'),
            ('PLL-begin-omitted', 'result=esp_radio_c6_pll_begin(cycles);', 'result=0;'),
            ('legacy-calibration-omitted', 'result=esp_radio_c6_ocode_legacy_stage(cycles);', 'result=0;'),
            ('PLL-restore-omitted', 'result=esp_radio_c6_pll_restore(cycles);', 'result=0;'),
            ('CPU-restore-omitted', 'result=esp_radio_c6_clock_restore(cycles);', 'result=0;'),
            ('caller-IRQs-released-early', 'esp_radio_calibration_step=5;', 'esp32_irq_restore(esp_radio_calibration_ps);esp_radio_calibration_step=5;'),
            ('original-IRQ-state-lost', 'esp32_irq_restore(esp_radio_calibration_ps)', 'esp32_irq_restore(0)'),
            ('failure-lease-lost', 'if result{esp_radio_calibration_error=result;', 'if result{esp_radio_calibration_active=0;esp_radio_calibration_error=result;'),
            ('primary-error-overwritten', 'esp_radio_calibration_internal=1;let result=', 'esp_radio_calibration_error=0;esp_radio_calibration_internal=1;let result='),
            ('cleanup-error-swallowed', 'if result{return result;}', 'if 0{return result;}'),
            ('cleanup-error-not-published', 'esp_radio_calibration_cleanup_error=result;', 'esp_radio_calibration_cleanup_error=0;'),
            ('cleanup-internal-admission-lost', 'esp_radio_calibration_internal=1;let result=', 'esp_radio_calibration_internal=0;let result='),
            ('legacy-abort-omitted', 'result=esp_radio_c6_ocode_legacy_abort(cycles);', 'result=0;'),
            ('factory-abort-omitted', 'result=esp_radio_c6_ocode_abort(cycles);', 'result=0;'),
            ('foreign-CPU-lease-admitted', ' || esp_radio_cpu_clock_active', ''),
            ('partial-PMU-admitted', ' || esp_radio_pmu_phase!=1', ''),
        ]:
            assert before in flow_original, name
            result = execute(name, original, common_text, flow_original.replace(before, after))
            assert result.returncode != 0, name + ' escaped'
            controls.append(dict(name=name, detected=True, result=result.returncode))
        stage_text = (ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex').read_text()
        for name, before, after in [
            ('public-PMU-admission-not-blocked', 'if esp_radio_calibration_active && !esp_radio_calibration_internal{return -16;}', ''),
            ('public-analog-write-not-blocked', 'if esp_radio_calibration_active && !esp_radio_calibration_internal{esp32_irq_restore(ps);return -16;}', ''),
        ]:
            assert before in stage_text, name
            result = execute(name, original, common_text, stage_module=stage_text.replace(before, after))
            assert result.returncode != 0, name + ' escaped'
            controls.append(dict(name=name, detected=True, result=result.returncode))
        pll_text = (ROOT / 'lib/platform/esp32c6-radio-pll.flex').read_text()
        before = ' || (esp_radio_calibration_active && !esp_radio_calibration_internal)'
        assert before in pll_text
        result = execute('public-PLL-consumer-not-blocked', original, common_text, pll_module=pll_text.replace(before, ''))
        assert result.returncode != 0
        controls.append(dict(name='public-PLL-consumer-not-blocked', detected=True, result=result.returncode))
    else:
        controls = []
        for name, before, after in [
            ('signed-status-truncated', 'return esp32_call64(', 'return esp32_call32('),
            ('reset-reason-ignored', 'if reason!=1', 'if 0'),
            ('factory-version-admitted', 'if version&0xf8000000', 'if 0'),
            ('PLL-lease-ignored', ' || !esp_radio_pll_active', ''),
            ('PLL-phase-ignored', ' || esp_radio_pll_phase!=2', ''),
            ('CPU-lease-ignored', ' || !esp_radio_cpu_clock_active', ''),
            ('master-clock-lease-ignored', ' || !esp_radio_pll_master_clock_owned', ''),
            ('PLL-powered-state-ignored', ' || (esp32_load32(0x600b0194)&0x62000000)', ''),
            ('CPU-divider-ignored', ' || (esp32_load32(0x60096118)&255)', ''),
            ('AHB-divider-ignored', ' || (esp32_load32(0x6009611c)&255)', ''),
            ('foreign-consumer-ignored', 'result=esp_radio_c6_pll_idle();', 'result=0;'),
            ('reset-intent-missing', 'esp_radio_ocode_count=3;', ''),
            ('reset-low-omitted', 'result=esp_radio_c6_ocode_bus(2,0,cycles);', 'result=0;'),
            ('reset-high-omitted', 'result=esp_radio_c6_ocode_bus(2,1,cycles);', 'result=0;'),
            ('force-code-guard-ignored', 'if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return -16;}', ''),
            ('timeout-lease-lost', 'if result{esp_radio_ocode_phase=2;', 'if result{esp_radio_ocode_active=0;esp_radio_ocode_phase=2;'),
        ]:
            assert before in original, name
            result = execute(name, original.replace(before, after), common_text)
            assert result.returncode != 0, name + ' escaped'
            controls.append(dict(name=name, detected=True, result=result.returncode))
        for name, before, after in [
            ('late-done-accepted', 'if ((esp32_cycles()-start)&0xffffffff)>=limit{return -110;}', ''),
            ('either-done-flag-accepted', '(result&9)==9', '(result&9)!=0'),
            ('BG-done-flag-ignored', '(result&9)==9', '(result&1)==1'),
            ('ten-ms-ceiling-ignored', 'if limit>400000{limit=400000;}', ''),
            ('reset-snapshot-lost', 'if result!=esp_radio_ocode_before_reset', 'if result!=0'),
            ('abort-reset-not-restored', 'result=esp_radio_c6_ocode_bus(2,esp_radio_ocode_before_reset,cycles);', 'result=0;'),
            ('abort-calibration-wait-omitted', 'result=esp_radio_c6_ocode_legacy_wait(cycles);', 'result=0;'),
        ]:
            assert before in common_text, name
            result = execute(name, original, common_text.replace(before, after))
            assert result.returncode != 0, name + ' escaped'
            controls.append(dict(name=name, detected=True, result=result.returncode))

    # Compile real callbacks into both cached profiles and inspect their ELF
    # symbol section/address: this verifies the compiler's actual placement.
    packaging = []
    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    aliases = work / 'empty.ld'
    aliases.write_text('/* No vendor objects or external imports. */\n')
    package_port = flow_port if args.coordinator else port
    for target in ['esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf']:
        source = work / (target + '.flex')
        source.write_text('import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\nimport "' + str(package_port) + '";\nglobal esp_radio_hw_ready=0;\nfn main(){if esp_radio_c6_ocode_legacy_stage(1000)!=-16{return 7;}if esp_radio_c6_ocode_legacy_abort(1000)!=-16{return 8;}esp_radio_owner=1;if esp_radio_c6_ocode_legacy_stage(1000)!=-16{return 9;}if esp_radio_c6_ocode_legacy_abort(1000)!=0{return 10;}let a=esp_radio_c6_clock_begin(0);if a!=-22{return 1;}let b=esp_radio_c6_clock_restore(0);if b!=-22{return 2;}let c=esp_radio_c6_pll_begin(0);if c!=-22{return 3;}let d=esp_radio_c6_pll_restore(0);if d!=-22{return 4;}let e=esp_radio_c6_ocode_legacy_stage(0);if e!=-22{return 5;}let f=esp_radio_c6_ocode_legacy_abort(0);if f!=-22{return 6;}return a+b+c+d+e+f;}\n')
        if args.coordinator:
            fixture = source.read_text().replace('fn main(){', 'fn flow_prepare_callback(a,b,c,d,e,f,g,h){return esp_radio_c6_calibration_prepare(a);}\nfn flow_abort_callback(a,b,c,d,e,f,g,h){return esp_radio_c6_calibration_abort(a);}\nfn main(){')
            fixture = fixture.replace('fn main(){', 'fn main(){if esp_radio_c6_calibration_prepare(1000)!=-16{return 21;}if esp_radio_c6_calibration_abort(1000)!=-16{return 22;}let p=esp32_callback32(flow_prepare_callback);let q=esp32_callback32(flow_abort_callback);let x=esp32_call64(p,0,0,0,0,0,0,0,0);let y=esp32_call64(q,0,0,0,0,0,0,0,0);if x!=-22 || y!=-22{return 23;}')
            fixture = fixture.replace('esp_radio_owner=1;', 'esp_radio_owner=1;if esp_radio_c6_calibration_prepare(1000)!=-16 || esp_radio_c6_calibration_abort(1000)!=0{return 24;}')
            source.write_text(fixture.replace('return a+b+c+d+e+f;', 'return a+b+c+d+e+f+x+y;'))
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
        flow_found = {}
        for section in sections:
            if section[1] != 2:
                continue
            strings = sections[section[6]]
            pool = payload[strings[4]:strings[4] + strings[5]]
            for pos in range(section[4], section[4] + section[5], 16):
                name, value, size, info, other, index = struct.unpack_from('<IIIBBH', payload, pos)
                label = pool[name:pool.find(b'\0', name)].decode()
                if label in ['esp_radio_c6_clock_begin_iram', 'esp_radio_c6_clock_restore_iram', 'esp_radio_c6_pll_begin_iram', 'esp_radio_c6_pll_restore_iram', 'esp_radio_c6_ocode_legacy_stage_iram', 'esp_radio_c6_ocode_legacy_abort_iram']:
                    assert 0x40800000 <= value < (0x40810000 if target == 'esp32c6-radio-elf' else 0x40820000)
                    assert sections[index][2] & 4
                    found[label] = value
                if args.coordinator and label in ['flow_prepare_callback', 'flow_abort_callback']:
                    if target == 'esp32c6-elf':
                        assert 0x40800000 <= value < 0x40820000
                    else:
                        assert 0x42000000 <= value < 0x42300000
                    assert sections[index][2] & 4
                    flow_found[label] = value
        if args.coordinator:
            assert len(flow_found) == 2, flow_found
        assert len(found) == 6, found
        if args.qemu_c6:
            command = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', args.qemu_c6.resolve(),
                       '--image', image, '--elf', linked, '--report', work / (target + '-ROM.json'), '--expected', -176 if args.coordinator else -132]
            if target != 'esp32c6-elf':
                command += ['--xip']
            if target == 'esp32c6-radio-elf':
                command += ['--radio']
            run(command)
        packaging.append(dict(target=target, real_IRAM_callbacks=found, coordinator_C_callbacks=flow_found, executed=bool(args.qemu_c6),
                              execution_scope='invalid-budget and unprepared-lease signed statuses through real IRAM wrappers' if args.qemu_c6 else 'package-only',
                              image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, coordinator=args.coordinator, checks=checks, controls=controls, packaging=packaging, primary_vendor_status_vectors=16, primary_vendor_policy_vectors=32768 if args.coordinator else 0, physical_hardware=False, injected_XTAL_lease=not args.coordinator,
                  real_PLL_or_analog_timing=False, full_C6_radio_startup=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'C6 calibration coordinator model checks;' if args.coordinator else 'legacy C6 OCODE model checks;', len(controls), 'defects;', len(packaging), 'IRAM packages; no physical/analog claim')


if __name__ == '__main__':
    main()
