#!/usr/bin/env python3
"""Primary C6 CPU/AHB clock oracle, owned handoff model and IRAM packaging.

No PLL power cycling, silicon clock/timing or full calibration claim.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def extract(path, name):
    source = path.read_text()
    start = source.index(name + '(')
    start = source.rfind('static inline', 0, start)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for label in ['compiler', 'reference', 'work']:
        parser.add_argument('--' + label, type=Path, required=True)
    parser.add_argument('--qemu-c6', type=Path)
    args = parser.parse_args()
    work, reference, compiler = args.work.resolve(), args.reference.resolve(), args.compiler.resolve()
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    for group in ['startup-primary', 'pmu-primary']:
        records = json.loads((reference / group / 'provenance.json').read_text())
        if isinstance(records, dict):
            records = records['sources']
        for record in records:
            if 'sha256' in record:
                assert hashlib.sha256((reference / group / record['path']).read_bytes()).hexdigest() == record['sha256']
    for name in ['provenance.json', 'register-provenance.json', 'xip-provenance.json']:
        records = json.loads((reference / name).read_text())
        if isinstance(records, dict):
            records = records['sources']
        for record in records:
            if 'sha256' in record:
                assert hashlib.sha256((reference / record['path']).read_bytes()).hexdigest() == record['sha256']
    for record in json.loads((reference / 'radio-provenance.json').read_text())['ROM_maps']:
        assert hashlib.sha256((reference / record['path']).read_bytes()).hexdigest() == record['sha256']

    def run(command, timeout=60):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=timeout)
        assert result.returncode == 0, (command, result.stdout[-1000:], result.stderr[-2000:])
        return result.stdout

    inc = work / 'include'
    (inc / 'soc').mkdir(parents=True)
    for folder in ['include/soc', 'register/soc']:
        for file in (reference / 'components/soc/esp32c6' / folder).glob('*.h'):
            shutil.copy2(file, inc / 'soc' / file.name)
    shutil.copy2(reference / 'startup-primary/idf/components/soc/esp32c6/register/soc/pcr_struct.h', inc / 'soc/pcr_struct.h')
    (inc / 'esp_assert.h').write_text('#pragma once\n#include <assert.h>\n')
    (inc / 'esp_bit_defs.h').write_text('#pragma once\n#define BIT(n) (1U<<(n))\n#define BIT64(n) (1ULL<<(n))\n')
    rom = (reference / 'components/esp_rom/esp32c6/ld/esp32c6.rom.ld').read_text()
    getter = re.search(r'\bets_get_cpu_frequency\s*=\s*(0x[0-9a-f]+)', rom)[1]
    setter = re.search(r'\bets_update_cpu_frequency\s*=\s*(0x[0-9a-f]+)', rom)[1]
    helpers = reference / 'pmu-primary/components/hal/esp32c6/include/hal/clk_tree_ll.h'
    names = ['clk_ll_cpu_get_src', 'clk_ll_cpu_get_hs_divider', 'clk_ll_cpu_get_ls_divider',
             'clk_ll_ahb_get_hs_divider', 'clk_ll_ahb_get_ls_divider', 'clk_ll_apb_get_divider']
    c = work / 'oracle.c'
    c.write_text('''#include <stdint.h>
#include <stdio.h>
#include "soc/pcr_reg.h"
#include "soc/pcr_struct.h"
#include "soc/pmu_reg.h"
#include "soc/spi_mem_reg.h"
_Static_assert(PCR_GDMA_CLK_EN_M==1 && PCR_GDMA_RST_EN_M==2,"GDMA ownership fields");
_Static_assert(PCR_REGDMA_CLK_EN_M==1 && PCR_REGDMA_RST_EN_M==2,"REGDMA ownership fields");
pcr_dev_t PCR;
typedef enum {SOC_CPU_CLK_SRC_XTAL=0,SOC_CPU_CLK_SRC_PLL=1,SOC_CPU_CLK_SRC_RC_FAST=2,SOC_CPU_CLK_SRC_INVALID=-1} soc_cpu_clk_src_t;
#define HAL_FORCE_READ_U32_REG_FIELD(reg,field) ((reg).field)
''' + '\n'.join(extract(helpers, name) for name in names) + '''
static void emit(uint32_t source,uint32_t cl,uint32_t al,uint32_t ch,uint32_t ah,uint32_t force,uint32_t p){
 PCR.sysclk_conf.val=(40U<<PCR_CLK_XTAL_FREQ_S)|(2U<<PCR_HS_DIV_NUM_S)|(source<<PCR_SOC_CLK_SEL_S)|0x800000;
 PCR.cpu_freq_conf.val=0xa5000000|cl|(ch<<PCR_CPU_HS_DIV_NUM_S)|(force<<PCR_CPU_HS_120M_FORCE_S);
 PCR.ahb_freq_conf.val=0x5a000000|al|(ah<<PCR_AHB_HS_DIV_NUM_S);PCR.apb_freq_conf.val=p<<PCR_APB_DIV_NUM_S;
 uint32_t s=clk_ll_cpu_get_src(),mhz=s==SOC_CPU_CLK_SRC_PLL?480:(s==SOC_CPU_CLK_SRC_XTAL?40:20);
 uint32_t cd=s==SOC_CPU_CLK_SRC_PLL?clk_ll_cpu_get_hs_divider():clk_ll_cpu_get_ls_divider();
 uint32_t ad=s==SOC_CPU_CLK_SRC_PLL?clk_ll_ahb_get_hs_divider():clk_ll_ahb_get_ls_divider();
 uint64_t row[8]={PCR.sysclk_conf.val,PCR.cpu_freq_conf.val,PCR.ahb_freq_conf.val,PCR.apb_freq_conf.val,20|(480<<8),(uint64_t)mhz*1000000/cd,(uint64_t)mhz*1000000/ad,(uint64_t)mhz*1000000/ad/clk_ll_apb_get_divider()};fwrite(row,sizeof(row),1,stdout);
}
int main(void){
 uint64_t config[18]={PCR_SYSCLK_CONF_REG,PCR_CPU_FREQ_CONF_REG,PCR_AHB_FREQ_CONF_REG,PCR_APB_FREQ_CONF_REG,PCR_SYSCLK_FREQ_QUERY_0_REG,
 PMU_CLK_STATE0_REG,PCR_GDMA_CONF_REG,PCR_REGDMA_CONF_REG,SPI_MEM_CMD_REG(0),SPI_MEM_CMD_REG(1),PCR_SOC_CLK_SEL_M,PCR_CPU_LS_DIV_NUM_M,PCR_AHB_LS_DIV_NUM_M,GETTER,SETTER,3186,SPI_MEM_FLASH_READ_M|SPI_MEM_FLASH_WREN_M|SPI_MEM_FLASH_WRDI_M|SPI_MEM_FLASH_RDID_M|SPI_MEM_FLASH_RDSR_M|SPI_MEM_FLASH_WRSR_M|SPI_MEM_FLASH_PP_M|SPI_MEM_FLASH_SE_M|SPI_MEM_FLASH_BE_M|SPI_MEM_FLASH_CE_M|SPI_MEM_FLASH_DP_M|SPI_MEM_FLASH_RES_M|SPI_MEM_FLASH_HPM_M|SPI_MEM_USR_M|SPI_MEM_FLASH_PE_M|SPI_MEM_SLV_ST_M|SPI_MEM_MST_ST_M,PMU_STABLE_XPD_BBPLL_STATE_M|PMU_ICG_GLOBAL_PLL_STATE_M|PMU_ANA_XPD_BBPLL_STATE_M};fwrite(config,sizeof(config),1,stdout);
 uint32_t p[3]={0,1,3};
 for(uint32_t s=0;s<3;s+=2)for(uint32_t c=1;c<=256;c*=2)for(uint32_t a=c;a<=256;a*=2)for(uint32_t k=0;k<3;k++)emit(s,c-1,a-1,0,3,0,p[k]);
 uint32_t ch[4]={0,0,1,3},force[4]={0,1,0,0},ah[3]={3,7,15};
 for(uint32_t c=0;c<4;c++)for(uint32_t a=0;a<3;a++)for(uint32_t k=0;k<3;k++)for(uint32_t cl=1;cl<=256;cl*=2)for(uint32_t al=1;al<=256;al*=2)emit(1,cl-1,al-1,ch[c],ah[a],force[c],p[k]);
 return ferror(stdout);
}
'''.replace('GETTER', getter).replace('SETTER', setter))
    oracle = work / 'oracle'
    run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', inc, c, '-o', oracle])
    expected = work / 'expected.bin'
    expected.write_bytes(run([oracle]))
    assert expected.stat().st_size == 144 + 3186 * 64
    model = (ROOT / 'tests/esp32/riscv-c6-clock-model.flex').read_text()
    model = model.replace('../../scripts/', str(ROOT / 'scripts') + '/').replace('../../lib/', str(ROOT / 'lib') + '/')
    port = ROOT / 'lib/platform/esp32c6-radio-clock.flex'
    original = port.read_text()

    def execute(name, module):
        # The positive firmware's real IRAM C-ABI thunks are checked below.
        # Native instrumentation substitutes only their opaque callback IDs.
        module = module.replace('esp32_iram_callback32(esp_radio_c6_clock_begin_iram)', '17')
        module = module.replace('esp32_iram_callback32(esp_radio_c6_clock_restore_iram)', '19')
        module = module.replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(port.parent / 'esp32c6-radio-pmu-stage.flex') + '"')
        adapter = work / (name + '-port.flex')
        adapter.write_text(module)
        source, binary = work / (name + '.flex'), work / name
        source.write_text(model.replace(str(port), str(adapter)))
        run([compiler, source, '-o', binary])
        result = subprocess.run([str(binary), str(expected)], cwd=ROOT, capture_output=True, timeout=30)
        (work / (name + '.stderr')).write_bytes(result.stderr)
        return result

    protected = execute('protected', original)
    assert protected.returncode == 0, protected.stderr
    checks = struct.unpack('<Q', protected.stdout)[0]
    mutations = [
        ('signed-status-truncated', 'return esp32_call64(', 'return esp32_call32('),
        ('CPU120-force-ignored', 'if cdiv==1 && (cpu&65536)', 'if 0'),
        ('AHB-derived-from-CPU120', 'ahb_hz=160000000/adiv;', 'ahb_hz=120000000/adiv;'),
        ('restore-IRQ-mask-lost', 'esp32_irq_restore(esp_radio_cpu_clock_ps);', 'esp32_irq_restore(0);'),
        ('entry-mask-released', 'esp_radio_cpu_clock_phase=2;return 0;', 'esp_radio_cpu_clock_phase=2;esp32_irq_restore(ps);return 0;'),
        ('inactive-fields-not-restored', 'result=esp_radio_c6_clock_write(0x60096118,255,esp_radio_cpu_clock_cpu,cycles);', 'result=0;'),
        ('AHB-restore-omitted', 'result=esp_radio_c6_clock_write(0x6009611c,255,esp_radio_cpu_clock_ahb,cycles);', 'result=0;'),
        ('ROM-ticks-not-restored', '0x40000048,esp_radio_cpu_clock_ticks', '0x40000048,40'),
        ('DMA-owner-ignored', '((dma&3)==1)', '0'),
        ('REGDMA-owner-ignored', '((regdma&3)==1)', '0'),
        ('SPI0-FSM-ignored', '&0xfffe00ff', '&0xfffe0000'),
        ('SPI1-command-ignored', '|esp32_load32(0x60003000)', ''),
        ('PLL-gate-state-ignored', '0x42000001,0x42000001', '0x40000001,0x40000001'),
        ('unstable-PLL-selected', 'result=esp_wait_mask(0x600b0194,0x42000001,0x42000001,cycles);', 'result=0;'),
        ('foreign-AHB-overwritten', ' || ((ahb^esp_radio_cpu_clock_ahb)&0xff00)', ''),
        ('partial-write-lease-lost', 'if result{return result;}', 'if result{esp_radio_cpu_clock_active=0;return result;}'),
    ]
    controls = []
    for name, before, after in mutations:
        assert before in original, name
        result = execute(name, original.replace(before, after))
        assert result.returncode != 0, name + ' escaped'
        controls.append(dict(name=name, detected=True, result=result.returncode))

    stage_port = ROOT / 'lib/platform/esp32c6-radio-pmu-stage.flex'
    for name, before, after in [
        ('PMU-abort-ignores-clock', 'if esp_radio_cpu_clock_active{esp32_irq_restore(ps);return -16;}', ''),
        ('PMU-commit-ignores-clock', ' || esp_radio_cpu_clock_active || ', ' || '),
    ]:
        module = stage_port.read_text()
        assert before in module, name
        module = module.replace(before, after)
        module = re.sub(r'^import "([^"]+)";', lambda m: 'import "' + str(stage_port.parent / m[1]) + '";', module, flags=re.M)
        mutant = work / (name + '-stage.flex')
        mutant.write_text(module)
        result = execute(name, original.replace('"esp32c6-radio-pmu-stage.flex"', '"' + str(mutant) + '"'))
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
        source.write_text('import "' + str(ROOT / 'lib/platform/esp32c6-xip.flex') + '";\nimport "' + str(port) + '";\nglobal esp_radio_hw_ready=0;\nfn main(){let a=esp_radio_c6_clock_begin(0);if a!=-22{return 1;}let b=esp_radio_c6_clock_restore(0);if b!=-22{return 2;}return a+b;}\n')
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
                if label in ['esp_radio_c6_clock_begin_iram', 'esp_radio_c6_clock_restore_iram']:
                    assert 0x40800000 <= value < 0x40810000
                    assert sections[index][2] & 4
                    found[label] = value
        assert len(found) == 2, found
        if args.qemu_c6:
            command = ['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', args.qemu_c6.resolve(),
                       '--image', image, '--elf', linked, '--report', work / (target + '-ROM.json'), '--expected', -44]
            if target != 'esp32c6-elf':
                command += ['--xip']
            if target == 'esp32c6-radio-elf':
                command += ['--radio']
            run(command)
        packaging.append(dict(target=target, real_IRAM_callbacks=found, executed=bool(args.qemu_c6),
                              execution_scope='invalid-budget signed status through real IRAM wrappers' if args.qemu_c6 else 'package-only',
                              image_sha256=hashlib.sha256(image.read_bytes()).hexdigest()))
    report = dict(pass_all=True, checks=checks, primary_clock_vectors=3186, IRQ_modes=2,
                  detected_defects=controls, packaging=packaging, physical_hardware=False,
                  CPU_clock_handoff_execution_verified=False, signed_callback_status_ROM_boots=3 if args.qemu_c6 else 0, PLL_power_cycling=False,
                  legacy_software_calibration=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS:', checks, 'C6 clock model checks;', len(controls), 'defects; 3 real IRAM packages; no physical/PLL-off proof')


if __name__ == '__main__':
    main()
