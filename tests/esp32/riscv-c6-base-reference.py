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
    helpers = helpers.replace('fn esp32_load32(', 'fn base_model_load32(').replace('fn esp32_store32(', 'fn base_model_store32(').replace('fn esp32_call64(', 'fn base_model_call64(')
    helpers = helpers.replace('fn esp32_irq_restore(value){', 'fn esp32_irq_restore(value){if esp_radio_base_active{check(!(value&8));}')
    extra = (ROOT / 'tests/esp32/riscv-c6-base-model.flex').read_text()
    cut = helpers.index('fn check_at(')
    model = helpers[:cut] + extra[:extra.index('fn base_seed(')] + helpers[cut:] + extra[extra.index('fn base_seed('):]
    port = ROOT / 'lib/platform/esp32c6-radio-base.flex'
    original = port.read_text()

    def execute(name, module=original):
        fake = work / (name + '-base.flex')
        module = module.replace('"esp32c6-radio-calibration.flex"', '"' + str(ingredients / 'protected-flow.flex') + '"')
        modem = work / 'modem.flex'
        modem.write_text((ROOT / 'lib/platform/esp32c6-radio-modem.flex').read_text().replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(ingredients / 'protected-stage.flex') + '"'))
        module = module.replace('"esp32c6-radio-modem.flex"', '"' + str(modem) + '"').replace('esp32_iram_callback32(esp_radio_c6_base_strobe_iram)', '29')
        fake.write_text(module)
        source, binary = work / (name + '.flex'), work / name
        text = model.replace(str(ingredients / 'protected-flow.flex'), str(fake), 1)
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
        ('monitor-postcondition-omitted','while !result && (esp32_load32(0x600b0194)&0xf00000)!=esp_radio_base_live','while 0'),
        ('primary-error-lost','esp_radio_base_cleanup_error=result;', 'esp_radio_base_error=result;esp_radio_base_cleanup_error=result;'),
        ('partial-prepare-committed','esp_radio_base_step!=6','esp_radio_base_step<1'),
    ]:
        assert before in original,name
        r=execute(name,original.replace(before,after))
        assert r.returncode!=0,name+' escaped'
        controls.append(dict(name=name,detected=True))
    packaging=[]
    linker=work/'linker';run([compiler,ROOT/'scripts/esp32-link.flex','-o',linker]);alias=work/'empty.ld';alias.write_text('/* no externals */\n')
    for target in ['esp32c6-elf','esp32c6-xip-elf','esp32c6-radio-elf']:
        source=work/(target+'.flex')
        source.write_text('import "'+str(ROOT/'lib/platform/esp32c6-xip.flex')+'";\nimport "'+str(port)+'";\nglobal esp_radio_hw_ready=0;\nfn main(){if esp_radio_c6_base_prepare(0,0,0)!=-22 || esp_radio_c6_base_abort(2147483648)!=-22 || esp_radio_c6_base_commit()!=-16{return 1;}if esp_radio_c6_base_prepare(0,0,1000)!=-16 || esp_radio_c6_base_abort(1000)!=-16{return 2;}esp_radio_base_active=1;if esp_radio_c6_pmu_abort(1000)!=-16 || esp_radio_c6_regi2c_idle()!=-16 || esp_radio_c6_pll_consumer(1)!=-16{return 3;}esp_radio_base_active=0;return 0;}\n')
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
        packaging.append(dict(target=target,IRAM_bytes=text_size,executed=bool(a.qemu_c6),scope='invalid/unprepared statuses and base lease admission only'))
    report=dict(pass_all=True,checks=checks,controls=controls,primary_C_preinit_vectors=256,packaging=packaging,all_lower_stages_executed_in_host_model=True,physical_hardware=False,valid_WT_MMIO_execution=False,acknowledgement='modeled live-field contract; inverse recovery also checks original bit20',full_PHY_startup=False,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',checks,'combined C6 base checks;',len(controls),'defects;',len(packaging),'native admission profiles; no silicon acknowledgement claim')


if __name__=='__main__':main()
