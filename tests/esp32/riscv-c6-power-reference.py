#!/usr/bin/env python3
"""Pinned PMU force-default C policy and actual owned PMU prepare/abort model."""
import argparse
import hashlib
import json
import re
import runpy
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def function(path, name):
    text = path.read_text()
    m = re.search(r'void\s+' + name + r'\([^)]*\)\s*\{', text)
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
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()

    def run(args):
        r = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, timeout=60)
        assert r.returncode == 0, (args, r.stdout[-1500:], r.stderr[-2500:])
        return r.stdout

    inputs = work / 'pmu-inputs'
    run(['python3', ROOT / 'tests/esp32/riscv-pmu-stage-reference.py', '--compiler', compiler, '--reference', ref, '--work', inputs, '--inputs-only'])
    primary = ref / 'startup-primary/idf/components'
    ll = primary / 'hal/esp32c6/include/hal/pmu_ll.h'
    names = ['power_up', 'no_reset', 'no_isolate', 'power_down', 'isolate', 'reset']
    helpers = [function(ll, 'pmu_ll_' + kind + '_set_power_force_' + n) for kind in ['hp', 'lp'] for n in names]
    helpers += [function(ll, 'pmu_ll_hp_set_memory_no_isolate')]
    c = work / 'force-oracle.c'
    c.write_text('''#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "pmu_param.h"
typedef struct {pmu_dev_t *dev;} pmu_hal_t;
typedef struct {pmu_hal_t *hal;} pmu_context_t;
''' + '\n'.join(helpers) + '\n' + function(primary / 'esp_hw_support/port/esp32c6/pmu_init.c', 'pmu_power_domain_force_default') + r'''
static volatile uint32_t *field(pmu_dev_t *dev,unsigned row){
 if(row<3)return &dev->power.hp_pd[row].val;
 if(row==3)return &dev->power.hp_pd[PMU_HP_PD_WIFI].val;
 if(row==4)return &dev->power.mem_cntl.val;
 return &dev->power.lp_peri.val;
}
int main(void){
 uint64_t count=256*6;fwrite(&count,8,1,stdout);
 for(unsigned seed=0;seed<256;seed++){
  pmu_dev_t dev;memset(&dev,255,sizeof(dev));pmu_hal_t hal={&dev};pmu_context_t ctx={&hal};pmu_power_domain_force_default(&ctx);
  uint32_t mask[6];for(unsigned row=0;row<6;row++)mask[row]=~*field(&dev,row);
  uint32_t pattern=seed*0x01010101U;memset(&dev,0,sizeof(dev));for(unsigned row=0;row<6;row++)*field(&dev,row)=pattern;
  dev.power.hp_pd[PMU_HP_PD_RESERVED].val=0xa5a5a5a5;
  pmu_power_domain_force_default(&ctx);assert(dev.power.hp_pd[PMU_HP_PD_RESERVED].val==0xa5a5a5a5);
  for(unsigned row=0;row<6;row++){
   uint64_t v[]={row,0x600b0000+(uintptr_t)((uint8_t*)field(&dev,row)-(uint8_t*)&dev),mask[row],pattern,*field(&dev,row)};
   fwrite(v,sizeof(v),1,stdout);
  }
 }return ferror(stdout);
}
''')
    oracle = work / 'force-oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-cpp', '-I', inputs / 'oracle/include', c, '-o', oracle])
    expected = work / 'force.bin'
    expected.write_bytes(run([oracle]))
    base = (ROOT / 'tests/esp32/riscv-pmu-stage-model.flex').read_text().split('fn main(argc,argv){')[0]
    base = base.replace('../../scripts/', str(ROOT / 'scripts') + '/').replace('../../lib/', str(ROOT / 'lib') + '/')
    extra = (ROOT / 'tests/esp32/riscv-c6-power-model.flex').read_text()
    cut = base.index('fn pmu_test_alloc(')
    model = base[:cut] + extra.split('fn force_case(')[0] + base[cut:] + extra[extra.index('fn force_case('):]
    stage = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
    port = ROOT / 'lib/platform/esp32c6-radio-power.flex'
    stage_text, original = stage.read_text(), port.read_text()

    def execute(name, module=original, outer=stage_text):
        fake = work / (name + '-power.flex')
        fake.write_text(module)
        wrapper = work / (name + '-stage.flex')
        outer = re.sub(r'^import "([^\"]+)";', lambda m: 'import "' + str(stage.parent / m[1]) + '";', outer, flags=re.M)
        wrapper.write_text(outer.replace(str(port), str(fake)))
        source, binary = work / (name + '.flex'), work / name
        text = model.replace(str(stage), str(wrapper))
        text = '\n'.join(re.sub(r'(?<!fn )\bcheck\(', 'check_at(' + str(i) + ',', line) for i, line in enumerate(text.splitlines(), 1)) + '\n'
        text += '\nfn check_at(line,ok){if !ok{h_print(2,h_cat3("line ",h_int(line)," failed\\n"));}return check(ok);}\n'
        source.write_text(text)
        run([compiler, source, '-o', binary])
        result = subprocess.run([binary, inputs / 'expected.bin', expected], cwd=ROOT, capture_output=True, timeout=30)
        (work / (name + '.stderr')).write_bytes(result.stderr)
        return result

    protected = execute('protected')
    assert protected.returncode == 0, (protected.returncode, protected.stderr)
    checks = struct.unpack('<Q', protected.stdout)[0]
    controls = []
    for name, before, after in [
        ('reserved-domain-selected', '0x600b0104', '0x600b0100'),
        ('wrong-memory-field', '0x0f000000', '0x00000f00'),
        ('force-power-down-not-cleared', 'return 63;', 'return 31;'),
        ('live-core-reset-admitted', '&35', '&34'),
        ('live-memory-isolation-admitted', '&15', '&0'),
        ('snapshot-row-aliased', 'if row==1{return esp_radio_pmu_force1;}', 'if row==1{return esp_radio_pmu_force0;}'),
        ('uncertain-write-replayed', 'if (esp32_load32(address)&mask)!=value', 'if 1'),
        ('late-read-accepted', 'let observed=esp32_load32(address)&mask;\n  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}', 'let observed=esp32_load32(address)&mask;'),
    ]:
        assert before in original, name
        result = execute(name, original.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True))
    for name, before, after in [
        ('force-default-omitted', 'result=esp_radio_c6_power_write(row,0,cycles);', 'result=0;'),
        ('intent-not-published', 'esp_radio_pmu_force_count=row+1;', ''),
        ('restore-omitted', 'while esp_radio_pmu_force_count{', 'while 0{'),
        ('restore-before-analog', 'while esp_radio_pmu_force_count{', 'while esp_radio_pmu_force_count{'),
        ('partial-force-commit-admitted', ' || esp_radio_pmu_force_count!=6', ''),
        ('failure-phase-not-set', 'if result{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}row=row+1;', 'if result{esp32_irq_restore(ps);return result;}row=row+1;'),
    ]:
        if name == 'restore-before-analog':
            block = re.search(r' while esp_radio_pmu_force_count\{.*?\n', stage_text)[0]
            changed = stage_text.replace(block, '').replace(' while esp_radio_pmu_analog_count{', block + ' while esp_radio_pmu_analog_count{')
        else:
            assert before in stage_text, name
            changed = stage_text.replace(before, after)
        result = execute(name, outer=changed)
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True))
    packaging = []
    linker = work / 'linker'
    run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker])
    alias = work / 'empty.ld'
    alias.write_text('/* no external inputs */\n')
    values = list(struct.iter_unpack('<5Q', expected.read_bytes()[8:]))[:6]
    for target in ['esp32c6-elf', 'esp32c6-xip-elf', 'esp32c6-radio-elf']:
        source = work / (target + '.flex')
        body = ''.join('if esp_radio_c6_power_address(' + str(row) + ')!=' + str(addr) + ' || esp_radio_c6_power_mask(' + str(row) + ')!=' + str(mask) + '{return 1;}' for row, addr, mask, _, _ in values)
        source.write_text('import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\nimport "' + str(port) + '";\nfn main(){' + body + 'let row=0;while row<6{let value=0;while value<256{esp_radio_c6_power_saved(row,value);if esp_radio_c6_power_saved(row,-1)!=value{return 2;}value=value+1;}row=row+1;}return 0;}\n')
        elf, linked, image = work / (target + '.elf'), work / (target + '-linked.elf'), work / (target + '.bin')
        run([compiler, '--target', target, source, '-o', elf])
        args = [linker, '--ld', 'ld.lld', '--rom', alias, '--firmware', elf, '--output', linked, '--image', image]
        if target != 'esp32c6-elf':
            args += ['--xip']
        run(args)
        if a.qemu_c6:
            args = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', a.qemu_c6.resolve(), '--image', image, '--elf', linked, '--report', work / (target + '-ROM.json')]
            if target != 'esp32c6-elf':
                args += ['--xip']
            if target == 'esp32c6-radio-elf':
                args += ['--radio']
            run(args)
        packaging.append(dict(target=target, executed=bool(a.qemu_c6), scope='address/mask/snapshot helpers only', image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, checks=checks, primary_C_vectors=1536, controls=controls, packaging=packaging, physical_hardware=False, power_MMIO_execution=False, full_C6_startup=False, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'owned C6 force-control checks;', len(controls), 'defects;', len(packaging), 'native pure-helper profiles; no physical claim')


if __name__ == '__main__':
    main()
