#!/usr/bin/env python3
"""Pinned C6 preinit requests and combined owned startup/recovery model.

Status acknowledgement is an explicit modeled contract, not silicon proof.
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
    p.add_argument('--qemu-c6', type=Path)
    a = p.parse_args()
    compiler, ref, work = a.compiler.resolve(), a.reference.resolve(), a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(args):
        r = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, timeout=90)
        assert r.returncode == 0, (args, r.stdout[-1000:], r.stderr[-2500:])
        return r.stdout

    ingredients = work / 'components'
    run(['python3', ROOT / 'tests/esp32/riscv-c6-ocode-legacy-reference.py', '--coordinator', '--compiler', compiler, '--reference', ref, '--work', ingredients])
    primary = ref / 'startup-primary/idf/components'
    extract = runpy.run_path(str(ROOT / 'tests/esp32/riscv-c6-power-reference.py'))['function']
    ll = primary / 'hal/esp32c6/include/hal'
    headers = ingredients / 'PLL-inputs/pmu-inputs/oracle/include'
    for name in ['modem_syscon_struct.h','modem_lpcon_struct.h']:
        shutil.copy2(primary / 'soc/esp32c6/include/modem' / name, headers / 'modem' / name)
    enums = (ref / 'pmu-primary/components/esp_hw_support/include/esp_private/esp_pmu.h').read_text()
    enum = re.search(r'typedef enum \{([^}]*PMU_HP_ICG_MODEM_CODE_SLEEP[^}]*)\}\s*pmu_hp_icg_modem_mode_t;', enums, re.S)[0]
    helpers = [extract(ll / 'pmu_ll.h', n) for n in ['pmu_ll_hp_set_icg_modem', 'pmu_ll_imm_update_dig_icg_modem_code', 'pmu_ll_imm_update_dig_icg_switch']]
    helpers += [extract(ll / 'modem_syscon_ll.h', 'modem_syscon_ll_set_modem_apb_icg_bitmap')]
    helpers += [extract(ll / 'modem_lpcon_ll.h', n) for n in ['modem_lpcon_ll_set_i2c_master_icg_bitmap', 'modem_lpcon_ll_set_lp_apb_icg_bitmap']]
    c = work / 'preinit-oracle.c'
    c.write_text('''#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "pmu_param.h"
#include "modem/modem_syscon_struct.h"
#include "modem/modem_lpcon_struct.h"
#define BIT(n) (1U<<(n))
''' + enum + '\npmu_dev_t PMU;modem_syscon_dev_t MODEM_SYSCON;modem_lpcon_dev_t MODEM_LPCON;\n' + '\n'.join(helpers) + '\n' + extract(primary / 'esp_hw_support/port/esp32c6/rtc_clk_init.c', 'rtc_clk_modem_clock_domain_active_state_icg_map_preinit') + r'''
int main(void){
 uint64_t meta[]={256,0x600b0000+offsetof(pmu_dev_t,hp_sys[0].icg_modem),0x600b0000+offsetof(pmu_dev_t,hp_sys[0].sysclk),0x600a9800+offsetof(modem_syscon_dev_t,clk_conf_power_st),0x600af000+offsetof(modem_lpcon_dev_t,clk_conf_power_st),0x600b0000+offsetof(pmu_dev_t,imm.modem_icg),0x600b0000+offsetof(pmu_dev_t,imm.sleep_sysclk)};
 fwrite(meta,sizeof(meta),1,stdout);
 for(unsigned i=0;i<256;i++){
  memset(&PMU,0,sizeof(PMU));uint32_t v=i*0x01010101U;PMU.hp_sys[0].icg_modem.val=v;PMU.hp_sys[0].sysclk.val=v^0xa5a5a5a5;MODEM_SYSCON.clk_conf_power_st.val=v^0x5a5a5a5a;MODEM_LPCON.clk_conf_power_st.val=v^0xabcdef01;
  uint64_t row[]={PMU.hp_sys[0].icg_modem.val,PMU.hp_sys[0].sysclk.val,MODEM_SYSCON.clk_conf_power_st.val,MODEM_LPCON.clk_conf_power_st.val,0,0,0,0,0,0};
  rtc_clk_modem_clock_domain_active_state_icg_map_preinit();
  row[4]=PMU.hp_sys[0].icg_modem.val;row[5]=PMU.hp_sys[0].sysclk.val;row[6]=MODEM_SYSCON.clk_conf_power_st.val;row[7]=MODEM_LPCON.clk_conf_power_st.val;row[8]=PMU.imm.modem_icg.val;row[9]=PMU.imm.sleep_sysclk.val;fwrite(row,sizeof(row),1,stdout);
 }return ferror(stdout);
}
''')
    oracle = work / 'preinit-oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-cpp', '-I', headers, c, '-o', oracle])
    expected = work / 'preinit.bin'
    expected.write_bytes(run([oracle]))
    helpers = (ingredients / 'protected.flex').read_text().split('fn main(argc,argv){')[0]
    helpers = helpers.replace('fn esp32_call32(', 'fn hardware_model_call32(')
    helpers = helpers.replace('fn esp32_load32(', 'fn base_model_load32(').replace('fn esp32_store32(', 'fn base_model_store32(').replace('fn esp32_call64(', 'fn base_model_call64(')
    helpers = helpers.replace('fn esp32_irq_restore(value){', 'fn esp32_irq_restore(value){if esp_radio_base_active{check(!(value&8));}')
    clock = 'fn esp32_cycles(){tick=(tick+7)&4294967295;return tick;}'
    assert helpers.count(clock) == 1
    helpers = helpers.replace(clock, 'fn esp32_cycles(){if base_final_mode && esp_radio_base_active && esp_radio_base_recovery==7{base_final_calls=base_final_calls+1;if base_final_calls==1{base_final_start=tick;}if base_final_mode==3 && base_final_calls>1{tick=(base_final_start+400)&4294967295;}return tick;}tick=(tick+7)&4294967295;return tick;}')
    extra = (ROOT / 'tests/esp32/riscv-c6-base-model.flex').read_text()
    lifetime = (ROOT / 'tests/esp32/riscv-c6-base-release-model.flex').read_text()
    function = runpy.run_path(str(ROOT / 'tests/esp32/lifecycle-preempt-reference.py'))['function']
    def selected(text, names):
        return '\n'.join(text[s:e] for s,e in (function(text,n) for n in names))
    hw_entry = re.sub(r'^import .*?;\n', '', (ROOT / 'lib/platform/esp32c6-radio-hardware.flex').read_text(), flags=re.M)
    wifi = (ROOT / 'lib/platform/esp32-wifi-core.flex').read_text()
    wifi_globals = wifi[:re.search(r'^fn ', wifi, re.M).start()]
    wifi_functions = selected(wifi, ['esp_wifi_packets_active','esp_wifi_operations_active','esp_wifi_stop_inner','esp_wifi_cleanup_finish_irq','esp_wifi_teardown','esp_wifi_station_deinit'])
    wifi_functions = wifi_functions.replace('esp32_callback(esp_radio_irq)', '123')
    platform = selected((ROOT / 'lib/platform/esp32-riscv-wifi.flex').read_text(), ['esp_wifi_platform_release','esp_wifi_platform_release_pending'])
    hardware = (ROOT / 'tests/esp32/riscv-c6-hardware-release-model.flex').read_text()
    additions = hw_entry + '\n' + wifi_globals + lifetime + '\n' + wifi_functions + '\n' + platform + '\n' + hardware
    declarations = '\n'.join(re.findall(r'^global [^\n]*', additions, re.M))
    additions = re.sub(r'^global [^\n]*\n', '', additions, flags=re.M)
    extra = extra.replace('fn base_seed(', declarations + '\nfn base_seed(', 1)
    extra = extra.replace('fn main(argc,argv){', additions + '\nfn main(argc,argv){')
    extra = extra.replace('base_release_suite();let out=', 'base_release_suite();lifetime_hardware_entry=1;lifetime_prepare(9,1,1);base_release_suite();wifi_release_suite();let out=')
    cut = helpers.index('fn check_at(')
    model = helpers[:cut] + extra[:extra.index('fn base_seed(')] + helpers[cut:] + extra[extra.index('fn base_seed('):]
    port = ROOT / 'lib/platform/esp32c6-radio-base.flex'
    original = port.read_text()

    def execute(name, module=original, entry=None, station=None):
        fake = work / (name + '-base.flex')
        module = module.replace('"esp32c6-radio-calibration.flex"', '"' + str(ingredients / 'protected-flow.flex') + '"')
        modem = work / 'modem.flex'
        modem.write_text((ROOT / 'lib/platform/esp32c6-radio-modem.flex').read_text().replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(ingredients / 'protected-stage.flex') + '"'))
        module = module.replace('"esp32c6-radio-modem.flex"', '"' + str(modem) + '"').replace('esp32_iram_callback32(esp_radio_c6_base_strobe_iram)', '29')
        fake.write_text(module)
        source, binary = work / (name + '.flex'), work / name
        text = model.replace(str(ingredients / 'protected-flow.flex'), str(fake), 1)
        if entry is not None:
            assert text.count(hw_entry)==1
            text=text.replace(hw_entry,entry,1)
        if station is not None:
            assert text.count(wifi_functions)==1
            text=text.replace(wifi_functions,station,1)
        # The inherited line diagnostic is already instrumented. Instrument
        # just the new model, without rewriting its check_at implementation.
        loc = text.index('fn base_seed(')
        text = text[:loc] + '\n'.join(re.sub(r'(?<!fn )\bcheck\(', 'check_at(' + str(i+10000) + ',', line) for i,line in enumerate(text[loc:].splitlines())) + '\n'
        source.write_text(text)
        run([compiler, source, '-o', binary])
        r = subprocess.run([binary, ingredients / 'expected.bin', expected], cwd=ROOT, capture_output=True, timeout=45)
        (work / (name + '.stderr')).write_bytes(r.stderr)
        return r

    result = execute('protected')
    assert result.returncode == 0, (result.returncode, result.stderr)
    checks = struct.unpack('<Q', result.stdout)[0]
    controls = []
    for name,before,after in [
        ('unknown-live-state-admitted','if ((live>>21)&3)!=(code>>30)', 'if 0'),
        ('strobe-blindly-replayed','let issue=!esp_radio_base_issued;', 'let issue=1;'),
        ('pending-drain-omitted','result=esp_radio_c6_base_command(cycles,1);','result=0;'),
        ('WT-command-read-modify-write','esp32_store32(address,command);','esp_reg_update(address,command,command);'),
        ('early-IRQ-release','esp_radio_base_step=2;', 'esp32_irq_restore(esp_radio_base_ps);esp_radio_base_step=2;'),
        ('original-IRQ-lost','esp32_irq_restore(esp_radio_base_ps)', 'esp32_irq_restore(0)'),
        ('PMU-stage-omitted','result=esp_radio_c6_pmu_stage(cycles);','result=0;'),
        ('calibration-omitted','result=esp_radio_c6_calibration_prepare(cycles);','result=0;'),
        ('modem-stage-omitted','result=esp_radio_c6_modem_stage(source,divider,cycles);','result=0;'),
        ('inverse-command-omitted','if esp_radio_base_touched{result=esp_radio_c6_base_command(cycles,0);}','if 0{result=esp_radio_c6_base_command(cycles,0);}'),
        ('monitor-postcondition-omitted','while !result && !matched','while 0'),
        ('late-final-status-accepted','if ((esp32_cycles()-start)&0xffffffff)>=cycles{result= -110;}else{matched=observed==esp_radio_base_live;}','matched=observed==esp_radio_base_live;'),
        ('expired-final-read-issued','if ((esp32_cycles()-start)&0xffffffff)>=cycles{result= -110;}\n    if !result{','if !result{'),
        ('primary-error-lost','esp_radio_base_cleanup_error=result;', 'esp_radio_base_error=result;esp_radio_base_cleanup_error=result;'),
        ('partial-prepare-committed','esp_radio_base_step!=6','esp_radio_base_step<1'),
        ('lifetime-startup-PS-reused','esp_radio_base_ps=ps;esp_radio_base_releasing=1;', 'esp_radio_base_releasing=1;'),
        ('lifetime-digital-snapshots-lost','esp_radio_pmu_digital_count=49;', 'esp_radio_pmu_digital_count=0;'),
        ('lifetime-force-snapshots-lost','esp_radio_pmu_force_count=6;', 'esp_radio_pmu_force_count=0;'),
        ('lifetime-modem-not-rearmed','esp_radio_modem_active=1;esp_radio_modem_phase=1;', 'esp_radio_modem_phase=1;'),
        ('lifetime-incomplete-receipt-admitted','if !result && (!esp_radio_pmu_configured ||', 'if 0 && (!esp_radio_pmu_configured ||'),
        ('lifetime-foreign-selector-retuned','if !result && (esp32_load32(0x600af014)&3)!=esp_radio_modem_32k', 'if 0 && (esp32_load32(0x600af014)&3)!=esp_radio_modem_32k'),
        ('lifetime-foreign-lease-overwritten','if !result && (esp_radio_base_releasing ||', 'if 0 && (esp_radio_base_releasing ||'),
        ('lifetime-flags-never-released','if esp_radio_base_releasing{esp_radio_base_configured=0;', 'if 0{esp_radio_base_configured=0;'),
        ('lifetime-flags-dropped-before-recovery','esp_radio_base_internal=0;esp_radio_base_cleanup_error=result;', 'if esp_radio_base_releasing{esp_radio_base_configured=0;esp_radio_modem_configured=0;esp_radio_pmu_configured=0;esp_radio_base_releasing=0;}esp_radio_base_internal=0;esp_radio_base_cleanup_error=result;'),
        ('lifetime-retry-denied','if esp_radio_base_active{\n  if !esp_radio_base_releasing', 'if esp_radio_base_active{esp32_irq_restore(ps);return -16;\n  if !esp_radio_base_releasing'),
        ('lifetime-unrepresented-monitor-admitted',' || ((live^esp_radio_base_live)&0x100000)', ''),
    ]:
        assert before in original,name
        r=execute(name,original.replace(before,after))
        assert r.returncode!=0,name+' escaped'
        controls.append(dict(name=name,detected=True))
    integration_controls=[]
    for name,before,after in [
        ('hardware-readiness-never-retired','if hardware{esp_radio_hw_ready=0;}','if 0{esp_radio_hw_ready=0;}'),
        ('hardware-readiness-retired-before-admission','let result=0;if !hardware{','if hardware{esp_radio_hw_ready=0;}let result=0;if !hardware{'),
    ]:
        assert before in original
        changed=original.replace(before,after)
        r=execute(name,changed);assert r.returncode!=0,name+' escaped';integration_controls.append(dict(name=name,detected=True))
    for name,before,after in [
        ('hardware-caller-PS-lost','esp_radio_c6_base_release_locked(cycles,ps,1)','esp_radio_c6_base_release_locked(cycles,0,1)'),
        ('hardware-recovery-blocked-by-owned-PMU',' if esp_radio_base_active{',' if esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}if esp_radio_base_active{'),
    ]:
        assert before in hw_entry
        r=execute(name,entry=hw_entry.replace(before,after));assert r.returncode!=0,name+' escaped';integration_controls.append(dict(name=name,detected=True))
    for name,before,after in [
        ('wifi-pending-IRQ-released','if esp_wifi_platform_release_pending() {return r;}','if 0 {return r;}'),
        ('wifi-final-phase-replayed','if esp_wifi_cleanup_phase {','if 0 {'),
        ('wifi-masked-retry-denied','(!recovery && esp_sdk_irq_blocked(ps))','esp_sdk_irq_blocked(ps)'),
        ('wifi-pending-owner-unlocked','if !esp_wifi_cleanup_phase {esp_wifi_lifecycle_busy=0;}','esp_wifi_lifecycle_busy=0;'),
        ('wifi-original-PS-overwritten','if esp_wifi_cleanup_phase {','if esp_wifi_cleanup_phase {esp_wifi_cleanup_ps=esp32_irq_save();'),
        ('wifi-foreign-recovery-task-admitted',' || esp_wifi_cleanup_task!=esp_sdk_current',''),
        ('wifi-unmasked-before-domain-release','r=esp_radio_resources_end(123);','esp32_irq_restore(esp_wifi_cleanup_ps);r=esp_radio_resources_end(123);'),
        ('wifi-journal-kept-after-success','esp_wifi_cleanup_phase=0;esp_wifi_cleanup_ps=0;','esp_wifi_cleanup_phase=1;esp_wifi_cleanup_ps=0;'),
    ]:
        assert before in wifi_functions,name
        r=execute(name,station=wifi_functions.replace(before,after));assert r.returncode!=0,name+' escaped';integration_controls.append(dict(name=name,detected=True))
    packaging=[]
    linker=work/'linker';run([compiler,ROOT/'scripts/esp32-link.flex','-o',linker]);alias=work/'empty.ld';alias.write_text('/* no externals */\n')
    for target in ['esp32c6-elf','esp32c6-xip-elf','esp32c6-radio-elf']:
        source=work/(target+'.flex')
        source.write_text('import "'+str(ROOT/'lib/platform/esp32c6-xip.flex')+'";\nimport "'+str(port)+'";\nglobal esp_radio_hw_ready=0;\nfn main(){if esp_radio_c6_base_prepare(0,0,0)!=-22 || esp_radio_c6_base_abort(2147483648)!=-22 || esp_radio_c6_base_commit()!=-16{return 1;}if esp_radio_c6_base_prepare(0,0,1000)!=-16 || esp_radio_c6_base_abort(1000)!=-16{return 2;}esp_radio_base_active=1;if esp_radio_c6_pmu_abort(1000)!=-16 || esp_radio_c6_regi2c_idle()!=-16 || esp_radio_c6_pll_consumer(1)!=-16{return 3;}esp_radio_base_active=0;return 0;}\n')
        guard = (ROOT / 'tests/esp32/riscv-c6-base-release-guards.flex').read_text()
        source.write_text(source.read_text().replace('fn main(){', guard + '\nfn main(){let status=base_release_native_guards();if status{return 40+status;}'))
        elf,linked,image=work/(target+'.elf'),work/(target+'-linked.elf'),work/(target+'.bin')
        run([compiler,'--target',target,source,'-o',elf]);args=[linker,'--ld','ld.lld','--rom',alias,'--firmware',elf,'--output',linked,'--image',image]
        if target!='esp32c6-elf':args+=['--xip']
        run(args)
        payload=elf.read_bytes();shoff=struct.unpack_from('<I',payload,32)[0];text_size=struct.unpack_from('<I',payload,shoff+40+20)[0]
        assert text_size<=(65536 if target=='esp32c6-radio-elf' else 131072)
        if a.qemu_c6:
            args=['python3',ROOT/'tests/esp32/riscv-rom-peer.py','--qemu',a.qemu_c6.resolve(),'--image',image,'--elf',linked,'--report',work/(target+'-ROM.json')]
            if target!='esp32c6-elf':args+=['--xip']
            if target=='esp32c6-radio-elf':args+=['--radio']
            run(args)
        packaging.append(dict(target=target,IRAM_bytes=text_size,executed=bool(a.qemu_c6),scope='invalid/unprepared and committed lifetime receipt admission with real IRQ preservation; no valid PMU MMIO'))
    native_deadline = None
    native_lifetime = None
    native_wifi = None
    if a.qemu_c6:
        directory = work / 'native-deadline'
        run(['python3', ROOT / 'tests/esp32/riscv-c6-base-deadline-reference.py', '--compiler', compiler, '--qemu-c6', a.qemu_c6.resolve(), '--work', directory])
        native_deadline = json.loads((directory / 'report.json').read_text())
        directory = work / 'native-lifetime'
        run(['python3', ROOT / 'tests/esp32/riscv-c6-base-deadline-reference.py', '--lifetime', '--compiler', compiler, '--qemu-c6', a.qemu_c6.resolve(), '--work', directory])
        native_lifetime = json.loads((directory / 'report.json').read_text())
        directory = work / 'native-WiFi-release'
        run(['python3', ROOT / 'tests/esp32/riscv-c6-wifi-release-native-reference.py', '--compiler', compiler, '--reference', ref, '--qemu-c6', a.qemu_c6.resolve(), '--work', directory])
        native_wifi = json.loads((directory / 'report.json').read_text())
    report=dict(pass_all=True,checks=checks,controls=controls,integration_controls=integration_controls,release_entry_points=["base_release","C6_hardware_deinit"],WiFi_vendor_and_SDK_boundaries=True,valid_C6_hardware_startup=False,deadline_boundary_vectors=26,native_deadline=native_deadline,native_lifetime=native_lifetime,native_wifi=native_wifi,lifetime_entry_runs=2,lifetime_counts_are_per_entry=True,WiFi_teardown_scenarios=15,lifetime_nominal_cases=49,lifetime_guard_cases=68,lifetime_fault_recovery_cases=10,lifetime_reinitialization_cases=48,primary_C_preinit_vectors=256,packaging=packaging,all_lower_stages_executed_in_host_model=True,physical_hardware=False,valid_WT_MMIO_execution=False,acknowledgement='modeled live-field contract; inverse recovery also checks original bit20',full_PHY_startup=False,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',checks,'combined C6 base checks;',len(controls)+len(integration_controls),'defects;',len(packaging),'native admission profiles; no silicon acknowledgement claim')


if __name__=='__main__':main()
