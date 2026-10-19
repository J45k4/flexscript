#!/usr/bin/env python3
"""Pinned radio callback policy, atomic ownership and native ILP32 spies.

Native probes execute callbacks with a RAM MMIO boundary spy. They do not
claim actual peripheral pulses, physical clocks or full PHY initialization.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def function(text, name):
    m = re.search(r'fn ' + name + r'\([^)]*\)\s*\{', text)
    assert m, name
    end, depth = m.end(), 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[m.start():end]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'reference', 'work']:
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--qemu-c6', type=Path)
    a = p.parse_args()
    compiler, ref, work = a.compiler.resolve(), a.reference.resolve(), a.work.resolve()
    a.compiler = compiler
    if a.qemu_c6:
        a.qemu_c6 = a.qemu_c6.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(args):
        r = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, timeout=90)
        assert not r.returncode, (args, r.stdout[-1000:], r.stderr[-2500:])
        return r.stdout

    for group in ['startup-primary', 'osi-primary']:
        pins = json.loads((ref / group / 'provenance.json').read_text())
        pins = pins if isinstance(pins, list) else pins['sources']
        for pin in pins:
            if 'sha256' in pin:
                assert hashlib.sha256((ref / group / pin['path']).read_bytes()).hexdigest() == pin['sha256'], pin['path']

    # The original header oracle supplies both chips' addresses and the
    # complete surrounding PHY policy regression, independent of this trace.
    policy = work / 'policy'
    run(['python3', ROOT / 'tests/esp32/riscv-radio-platform-reference.py', '--compiler', compiler, '--reference', ref, '--work', policy])
    constants = {chip: struct.unpack('<32Q', (policy / f'c{chip}/expected.bin').read_bytes()[:256]) for chip in [3, 6]}
    primary = ref / 'startup-primary/idf/components'
    radio = ref / 'osi-primary/hal/esp-radio/src/radio_clocks/clocks_ll'
    c6_radio = (radio / 'esp32c6.rs').read_text()
    body = function(c6_radio, 'reset_wifi_mac').split('{', 1)[1][:-1]
    assert not re.sub(r'//[^\n]*', '', body).strip(), 'review changed pinned C6 reset contract'
    c3_radio = function((radio / 'esp32c3.rs').read_text(), 'reset_wifi_mac')
    assert c3_radio.count('.mac_rst()') == 2 and '.set_bit()' in c3_radio and '.clear_bit()' in c3_radio
    extract = runpy.run_path(str(ROOT / 'tests/esp32/riscv-c6-power-reference.py'))['function']
    ll = primary / 'hal/esp32c6/include/hal'
    clocks = ['wifibb_22m', 'wifibb_40m', 'wifibb_44m', 'wifibb_80m', 'wifibb_40x', 'wifibb_80x', 'wifibb_40x1', 'wifibb_80x1', 'wifibb_160x1', 'wifi_mac', 'wifi_apb']
    helpers = [extract(ll / 'modem_syscon_ll.h', f'modem_syscon_ll_enable_{n}_clock') for n in clocks]
    helpers += [extract(ll / 'modem_lpcon_ll.h', 'modem_lpcon_ll_enable_coex_clock')]
    c = work / 'oracle.c'
    c.write_text('#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#include "modem_syscon_struct.h"\n#include "modem_lpcon_struct.h"\n' + '\n'.join(helpers) + '\n' + r'''
int main(void){
 uint64_t count=2*256*3;fwrite(&count,8,1,stdout);
 for(unsigned chip=3;chip<=6;chip+=3)for(unsigned s=0;s<256;s++)for(unsigned mode=0;mode<3;mode++){
  uint32_t seed=s*0x01010101U,flip=(s*0x9e3779b9U)^0xdeadbeefU;
  uint64_t v[]={chip,mode,seed,0,0,0,0,0,0,0};
  if(chip==3 && !mode){v[3]=flip&~4U;v[4]=v[5]=C3_RESET_ADDRESS;v[6]=v[7]=4;volatile uint32_t reg=seed;reg|=4;v[8]=reg;reg^=v[3];reg&=~4U;v[9]=reg;}
  if(chip==6 && mode){
   modem_syscon_dev_t sys;modem_lpcon_dev_t lp;memset(&sys,0,sizeof(sys));memset(&lp,0,sizeof(lp));
   sys.clk_conf1.val=seed;lp.clk_conf.val=seed^0xa5a5a5a5U;
   bool en=mode==1;
''' + ''.join(f'   modem_syscon_ll_enable_{n}_clock(&sys,en);\n' for n in clocks) + r'''
   v[3]=flip&~2U;v[4]=C6_CLOCK_ADDRESS;v[5]=C6_LP_ADDRESS;v[6]=0x7ff;v[7]=2;v[8]=sys.clk_conf1.val;
   lp.clk_conf.val^=v[3];modem_lpcon_ll_enable_coex_clock(&lp,en);v[9]=lp.clk_conf.val;
  }fwrite(v,sizeof(v),1,stdout);
 }return ferror(stdout);
}
''')
    oracle, expected = work / 'oracle', work / 'expected.bin'
    structs = primary / 'soc/esp32c6/include/modem'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', structs, f'-DC3_RESET_ADDRESS={constants[3][18]}', f'-DC6_CLOCK_ADDRESS={constants[6][5]}', f'-DC6_LP_ADDRESS={constants[6][7]}', c, '-o', oracle])
    expected.write_bytes(run([oracle]))
    source = (ROOT / 'lib/platform/esp32-riscv-radio-hardware.flex').read_text()
    names = ['esp_radio_hw_require', 'esp_radio_wifi_clock', 'esp_radio_cb_wifi_clock_on', 'esp_radio_cb_wifi_clock_off', 'esp_radio_cb_wifi_reset']
    selected = '\n'.join(function(source, n) for n in names)
    update = function((ROOT / 'lib/platform/esp32-riscv-common.flex').read_text(), 'esp_reg_update')
    model = (ROOT / 'tests/esp32/riscv-radio-clock-model.flex').read_text()
    imports = f'import "{ROOT}/scripts/lib/build.flex";\nimport "{ROOT}/lib/platform/esp32-analog-state.flex";\n'

    def execute(name, code=selected, guard=0, mode=0, irq=0):
        # Observe guard entry, without changing its actual admission branches.
        observed = code.replace('fn esp_radio_hw_require(){', 'fn esp_radio_hw_require(){guard_seen=guard_seen+1;check(!(callback_ps&8));')
        path, binary = work / (name + '.flex'), work / name
        cut = model.index('fn cv(')
        path.write_text(imports + model[:cut] + observed + '\n' + update + '\n' + model[cut:])
        run([compiler, path, '-o', binary])
        args = [binary, expected] + ([str(guard), str(mode), str(irq)] if guard else [])
        return subprocess.run(list(map(str, args)), capture_output=True, timeout=30)

    result = execute('protected')
    assert not result.returncode, result.stderr
    checks = struct.unpack('<Q', result.stdout)[0]
    guard_cases = []
    binary = work / 'protected'
    for guard in range(1, 7):
        for mode in range(3):
            for irq in range(2):
                r = subprocess.run([binary, expected, str(guard), str(mode), str(irq)], capture_output=True, timeout=10)
                assert r.returncode == 77 and struct.unpack('<QQ', r.stdout) == (0, 0x1880), (guard, mode, irq, r.returncode, r.stderr)
                guard_cases.append((guard, mode, irq))
    controls = []
    for name, before, after, guard in [
        ('clock-mask-omitted', 'let ps=esp32_irq_save();esp_radio_hw_require();', 'let ps=callback_ps;esp_radio_hw_require();', 0),
        ('ownership-checked-before-mask', 'let ps=esp32_irq_save();esp_radio_hw_require();', 'esp_radio_hw_require();let ps=esp32_irq_save();', 0),
        ('IRQ-between-clock-writes', 'esp_radio_hw_require();if rv_hal_chip==13', 'esp_radio_hw_require();esp32_irq_restore(ps);if rv_hal_chip==13', 0),
        ('IRQ-between-reset-edges', 'esp_radio_hw_require();\n // The pinned', 'esp_radio_hw_require();esp32_irq_restore(ps);\n // The pinned', 0),
        ('invalid-enable-admitted', 'if enable<0 || enable>1{return -22;}', '', 0),
        ('IRQ-state-lost', 'esp32_irq_restore(ps);return 0;', 'esp32_irq_restore(0);return 0;', 0),
        ('C6-reset-invented', 'if rv_hal_chip==5{esp_reg_update', 'if rv_hal_chip==5 || rv_hal_chip==13{esp_reg_update', 0),
        ('wrong-LP-clock-field', '0x600af018,2,enable*2', '0x600af018,1,enable', 0),
        ('second-clock-write-omitted', 'esp_reg_update(0x600af018,2,enable*2);', '', 0),
        ('base-lease-ignored', 'esp_radio_base_active || ', '', 1),
        ('analog-lease-ignored', 'esp_radio_regi2c_active || ', '', 2),
        ('PMU-lease-ignored', 'esp_radio_pmu_active || ', '', 3),
        ('unready-admitted', '!esp_radio_hw_ready || ', '', 4),
        ('foreign-owner-admitted', ' || esp_radio_owner!=1', '', 6),
        ('C3-reset-stale-deassertion', 'esp_reg_update(0x60026018,4,4);esp_reg_update(0x60026018,4,0);', 'let old=esp32_load32(0x60026018);esp_reg_update(0x60026018,4,4);esp32_store32(0x60026018,old&~4);', 0),
    ]:
        assert before in selected, name
        r = execute(name, selected.replace(before, after, 1), guard=guard)
        assert (r.returncode != 77 if guard else r.returncode != 0), name + ' escaped'
        controls.append(dict(name=name, detected=True))

    native = []
    if a.qemu_c6:
        native = native_spies(a, selected, work, ref, run)
    tracked = [ROOT / 'lib/platform/esp32-riscv-radio-hardware.flex', ROOT / 'lib/platform/esp32-riscv-common.flex', radio / 'esp32c3.rs', radio / 'esp32c6.rs', ll / 'modem_syscon_ll.h', ll / 'modem_lpcon_ll.h', structs / 'modem_syscon_struct.h', structs / 'modem_lpcon_struct.h']
    report = dict(pass_all=True, checks=checks, primary_vectors=1536, guard_cases=len(guard_cases), guard_matrix=guard_cases, controls=controls, native=native, C6_ROM_boots=sum(x['ROM_boot'] for x in native), C3_packages=sum(not x['ROM_boot'] for x in native), callback_functions_extracted=names, C6_reset_policy='pinned radio no-op retained', physical_hardware=False, actual_clock_MMIO_executed=False, PHY_startup=False, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), source_sha256={str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in tracked})
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'radio callback checks;', len(controls), 'detected defects;', len(native), 'native/package cases; MMIO boundary spies only')


def native_spies(a, selected, work, ref, run):
    inc = work / 'native-include';inc.mkdir()
    shutil.copy2(ref / 'osi-primary/vendor/c/include/esp_private/wifi_os_adapter.h', inc / 'wifi_os_adapter.h')
    (inc / 'sdkconfig.h').write_text('#define CONFIG_IDF_TARGET_ESP32C6 1\n#define CONFIG_SOC_WIFI_HE_SUPPORT 1\n')
    c = work / 'native-peer.c'
    c.write_text('''#include <stdint.h>
#include "wifi_os_adapter.h"
_Static_assert(offsetof(wifi_osi_funcs_t,_wifi_reset_mac)==244,"reset ABI");
_Static_assert(offsetof(wifi_osi_funcs_t,_wifi_clock_enable)==248,"enable ABI");
_Static_assert(offsetof(wifi_osi_funcs_t,_wifi_clock_disable)==252,"disable ABI");
unsigned callback_peer(unsigned r,unsigned on,unsigned off,unsigned mode,unsigned mie){
 wifi_osi_funcs_t t;t._wifi_reset_mac=(void(*)(void))(uintptr_t)r;t._wifi_clock_enable=(void(*)(void))(uintptr_t)on;t._wifi_clock_disable=(void(*)(void))(uintptr_t)off;
 unsigned before,after,sp;__asm__ volatile("csrr %0,mstatus":"=r"(before));__asm__ volatile("mv %0,sp":"=r"(sp));
 if((sp&15)||((before>>3)&1)!=mie)return 1;
 if(!mode)t._wifi_reset_mac();else if(mode==1)t._wifi_clock_enable();else t._wifi_clock_disable();
 __asm__ volatile("csrr %0,mstatus":"=r"(after));return ((after^before)&8)!=0;
}
''')
    prefix = f'import "{ROOT}/lib/platform/esp32-analog-state.flex";\n'
    spy = '''global rv_hal_chip=13;global esp_radio_hw_ready=1;global trace=0;global used=0;global bad=0;
fn esp_reg_update(address,mask,value){let ps=esp32_irq_save();if ps&8 || esp_radio_owner!=1 || !esp_radio_hw_ready || esp_radio_base_active || esp_radio_pmu_active || esp_radio_regi2c_active{bad=1;}store64(trace+used*24,address);store64(trace+used*24+8,mask);store64(trace+used*24+16,value);used=used+1;esp32_irq_restore(ps);return 0;}
'''
    invoke = 'esp32_call32(esp32_external("callback_peer"),esp32_callback32(esp_radio_cb_wifi_reset),esp32_callback32(esp_radio_cb_wifi_clock_on),esp32_callback32(esp_radio_cb_wifi_clock_off),mode,irq,0,0,0)'
    main = 'fn main(){trace=alloc(512);esp_radio_owner=1;let saved=esp32_irq_save();let irq=0;while irq<2{let mode=0;while mode<3{used=0;bad=0;let ps=(saved&~8)|(irq*8);esp32_irq_restore(ps);let r=' + invoke + ';let observed=esp32_irq_save();if r||bad||observed!=ps{return 1;}let expected=0;if rv_hal_chip==13&&mode{expected=2;}if rv_hal_chip==5&&!mode{expected=2;}if used!=expected{return 2;}if used{let address=0x60026018;let mask=4;let value=4;let address2=address;let mask2=mask;let value2=0;if rv_hal_chip==13{address=0x600a9814;mask=0x7ff;value=(mode==1)*mask;address2=0x600af018;mask2=2;value2=(mode==1)*2;}if load64(trace)!=address||load64(trace+8)!=mask||load64(trace+16)!=value||load64(trace+24)!=address2||load64(trace+32)!=mask2||load64(trace+40)!=value2{return 3;}}mode=mode+1;}irq=irq+1;}esp32_irq_restore(saved);return 0;}'
    linker = work / 'native-linker';run([a.compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    alias = work / 'empty.ld';alias.write_text('/* no ROM calls */\n')
    cases = []

    def boot(name, text, target, obj, trapped=False):
        stem=work/name;source=stem.with_suffix('.flex');cut=spy.index('fn esp_reg_update(');source.write_text(prefix+spy[:cut]+selected+'\n'+spy[cut:]+text)
        if target.startswith('esp32c3'):source.write_text(source.read_text().replace('global rv_hal_chip=13','global rv_hal_chip=5'))
        elf, linked, image, report=[Path(str(stem)+suffix) for suffix in ['.elf','-linked.elf','.bin','.json']]
        run([a.compiler,'--target',target,source,'-o',elf])
        run([linker,'--ld','ld.lld','--rom',alias,'--firmware',elf,'--object',obj,'--output',linked,'--image',image])
        args=['python3',ROOT/'tests/esp32/riscv-rom-peer.py','--qemu',a.qemu_c6,'--image',image,'--elf',linked,'--report',report]
        chip=3 if target.startswith('esp32c3') else 6
        if chip==3:args+=['--validate-only']
        elif trapped:args+=['--trap','--zero-memory','0x40840000:512']
        run(args);row=json.loads(report.read_text());row.update(case=name,MMIO_boundary='RAM esp_reg_update spy',C_driver='pinned void(void) OSI fields');cases.append(row)

    obj=None
    for march in ['rv32im_zicsr','rv32imc_zicsr']:
        for opt in ['-O0','-O2','-Os']:
            obj=work/(march+opt+'.o');run(['clang','--target=riscv32','-mabi=ilp32','-march='+march,opt,'-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-I',inc,'-c',c,'-o',obj])
            for chip in [3,6]:boot(f'native-c{chip}-{march}{opt}',main,f'esp32c{chip}-elf',obj)
    for guard, assignment in [('base','esp_radio_base_active=1;'),('analog','esp_radio_regi2c_active=1;'),('PMU','esp_radio_pmu_active=1;'),('unready','esp_radio_hw_ready=0;'),('unowned','esp_radio_owner=0;'),('foreign','esp_radio_owner=2;')]:
        for mode in range(3):
            for irq in range(2):
                negative='fn main(){trace=alloc(512);esp_radio_owner=1;'+assignment+f'let mode={mode};let irq={irq};let ps=esp32_irq_save();esp32_irq_restore((ps&~8)|(irq*8));'+invoke+';return 99;}'
                boot(f'guard-{guard}-{mode}-{irq}',negative,'esp32c6-elf',obj,trapped=True)
    return cases


if __name__ == '__main__':
    main()
