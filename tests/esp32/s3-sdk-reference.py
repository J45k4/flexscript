#!/usr/bin/env python3
"""Verify native S3 SDK profiles against pinned IDF headers and emitted firmware.

Uses existing stock QEMU only. Compiler, linker, and hardware-model code are
never patched in place; defect controls operate on copied firmware sources.
"""
import argparse, hashlib, json, os, re, runpy, shutil, struct, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def elf(path):
    data=Path(path).read_bytes()
    assert data[:7]==b'\x7fELF\x01\x01\x01'
    u16=lambda p:struct.unpack_from('<H',data,p)[0]
    u32=lambda p:struct.unpack_from('<I',data,p)[0]
    sh=u32(32);count=u16(48);names=sh+u16(50)*40
    pool=data[u32(names+16):u32(names+16)+u32(names+20)]
    sections={}
    for i in range(count):
        at=sh+i*40;name=pool[u32(at):].split(b'\0',1)[0].decode()
        sections[name]=dict(header=at,address=u32(at+12),offset=u32(at+16),size=u32(at+20))
    info=sections['.flex.info'];profile=struct.unpack_from('<8I',data,info['offset'])
    return data,sections,profile

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['compiler','driver','qemu','prefix','s3-prefix','reference','work']:
        p.add_argument('--'+k,required=True)
    a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
    assert not (w/'report.json').exists(),'choose a fresh work directory'
    env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
    def run(args,name,ok=0,contains=None):
        result=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=60)
        text=(result.stdout+result.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text)
        assert result.returncode==ok,(name,result.returncode,text[-2500:])
        assert contains is None or contains in text,(name,contains,text[-2500:])
        return text
    ref=Path(a.reference).resolve();provenance=json.loads((ref.parent/'reference-provenance.json').read_text())
    for name,row in provenance.items(): assert sha(ref/name)==row['sha256']
    inc=w/'include';(inc/'soc').mkdir(parents=True,exist_ok=True)
    for name in ['soc.h','reg_base.h','interrupts.h','timer_group_reg.h','interrupt_core0_reg.h']:
        shutil.copyfile(ref/name,inc/'soc'/name)
    (inc/'esp_bit_defs.h').write_text('#define BIT(n) (1U << (n))\n')
    oracle=w/'oracle.c';oracle.write_text('''#include <stdio.h>
#define __ASSEMBLER__ 1
#include "soc/soc.h"
#include "soc/interrupts.h"
#include "soc/timer_group_reg.h"
#include "soc/interrupt_core0_reg.h"
int main(void) {
 printf("%u %u %u %u %u %u %u %u %u %u %u %u\\n",SOC_I_D_OFFSET,
 SOC_DIRAM_IRAM_LOW,SOC_DIRAM_IRAM_HIGH,SOC_DIRAM_DRAM_LOW,SOC_DIRAM_DRAM_HIGH,
 SOC_ROM_STACK_START-SOC_ROM_STACK_SIZE,ETS_TG1_T1_LEVEL_INTR_SOURCE,
 TIMG_T1CONFIG_REG(1),TIMG_INT_ENA_TIMERS_REG(1),
 INTERRUPT_CORE0_TG1_T1_INT_MAP_REG,TIMG_T1_HI_V,ETS_MAX_INTR_SOURCE);
 return 0;
}
''')
    run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',inc,oracle,'-o',w/'oracle'],'oracle-build')
    values=list(map(int,run([w/'oracle'],'oracle').split()))
    offset,ilo,ihi,dlo,dhi,romstack,source,base,enable,route,highmask,nsources=values
    # The ROM loader boundary is defined independently in IDF's linker input.
    match=re.search(r'^#define\s+SRAM_IRAM_END\s+(0x[0-9A-Fa-f]+)',(ref/'memory.ld.in').read_text(),re.M)
    assert match;romlimit=int(match[1],16)-offset
    oracle_values=dict(alias_offset=offset,iram_low=ilo,iram_high=ihi,dram_low=dlo,dram_high=dhi,rom_stack_floor=romstack,rom_loader_limit=romlimit,timer_source=source,timer_base=base,timer_enable=enable,timer_route=route,timer_high_mask=highmask,irq_sources=nsources)
    (w/'oracle.json').write_text(json.dumps(oracle_values,indent=2)+'\n')
    profiles=['esp32-elf','esp32-radio-elf','esp32-btdm-elf','esp32s3-elf','esp32s3-sdk-elf','esp32s3-xip-elf']
    rows=[]
    for profile in profiles:
        s3=profile.startswith('esp32s3');fixture='s3-sdk-heap-bounds.flex' if s3 else 'sdk-heap-bounds.flex'
        if profile=='esp32-btdm-elf':fixture='btdm-sdk-heap-bounds.flex'
        if profile=='esp32s3-xip-elf':fixture='s3-xip-heap-bounds.flex'
        args=[a.driver,'--compiler',a.compiler,'--work',w/profile,'--qemu',a.qemu,'--prefix',a.s3_prefix if s3 else a.prefix,'--source',ROOT/'tests/esp32'/fixture,'--chip','esp32s3' if s3 else 'esp32','--profile',profile,'--report',w/(profile+'.json')]
        run(args,profile,contains='PASS: profile heap endpoints')
        image=w/profile/'firmware.elf';data,sections,info=elf(image)
        if s3:
            _,chip,code,state,floor,top,hb,he=info
            assert chip==9 and ilo<=code and code+sections['.text']['size']<=ihi
            assert dlo<=state and state+sections['.data']['size']<=hb<he<=floor<top<=min(romlimit,romstack,dhi)
            assert code+sections['.text']['size']-offset<=state
            if profile.endswith('sdk-elf'):
                assert state-code+offset==196608 and hb-state==16384 and he-hb==8192 and floor-he==40960
            if profile=='esp32s3-xip-elf':
                assert state-code+offset==98304 and hb-state==32768 and he-hb==8192 and floor-he==122880
        rows.append(dict(profile=profile,ELF_sha256=sha(image),info=info,code_bytes=sections['.text']['size'],data_bytes=sections['.data']['size']))
    # Independent header values become guest assertions, not source-text checks.
    contract=w/'s3-registers.flex';contract.write_text(f'''import "{ROOT}/lib/platform/esp32s3-sdk-preempt.flex";
fn main() {{
 if esp_timer_source(3)!={source} || esp_timer_base(3)!={base} || esp_sdk_preempt_enable_reg()!={enable} || esp_sdk_preempt_route()!={route} {{return 11;}}
 if esp_sdk_heap_init(0x3fcc6000,40960) || esp_sdk_task_init() {{return 12;}}
 let old=esp32_load32({route});if esp_sdk_preempt_start(5000) || esp32_load32({route})!=1 || esp_irq_handler({source})!=esp32_callback(esp_sdk_preempt_tick) || !(esp32_load32({enable})&2) {{return 13;}}
 if esp_sdk_preempt_stop() || esp32_load32({route})!=old || esp_irq_handler({source}) {{return 14;}}
 esp_uart_write("PASS: IDF-derived S3 timer IRQ routing and lease restoration\\r\\n");return 0;
}}
''')
    args=[a.driver,'--compiler',a.compiler,'--work',w/'registers','--qemu',a.qemu,'--prefix',a.s3_prefix,'--source',contract,'--chip','esp32s3','--sdk','yes']
    run(args,'registers',contains='PASS: IDF-derived S3')
    # Rejection must preserve existing destinations, both compiler and linker.
    controls=[];dest=w/'preserved.elf'
    def reject(args,name,message):
        dest.write_bytes(b'preserve existing output\n');before=sha(dest)
        run(args,name,1,message);assert sha(dest)==before;controls.append(name)
    too_big=w/'static-overflow.flex';too_big.write_text(''.join(f'global g{i}={i};\n' for i in range(2048))+'fn main(){return 0;}\n')
    reject([a.compiler,'--target','esp32s3-sdk-elf',too_big,'-o',dest],'static-overflow','static data exceeds 16 KiB')
    too_big=w/'code-overflow.flex';too_big.write_text('fn main(){let a=esp32_cycles();'+''.join(f'a=a+{i};' for i in range(10000))+'return a;}\n')
    reject([a.compiler,'--target','esp32s3-sdk-elf',too_big,'-o',dest],'code-overflow','exceeds 192 KiB IRAM')
    good=w/'registers/firmware-input.elf';data,sections,info=elf(good)
    linker=w/'registers/link';obj=w/'registers/oracle.o'
    for word in [2,4,5,6,7]:
        broken=bytearray(data);at=sections['.flex.info']['offset']+word*4
        struct.pack_into('<I',broken,at,struct.unpack_from('<I',broken,at)[0]+16)
        path=w/f'bad-profile-{word}.elf';path.write_bytes(broken)
        reject([linker,'--firmware',path,'--output',dest,'--ld',a.s3_prefix+'ld','--object',obj],f'metadata-{word}','invalid ESP32-S3 SDK memory profile')
    broken=bytearray(data);at=sections['.flex.info']['offset']+12
    struct.pack_into('<I',broken,at,info[3]+16);path=w/'bad-profile-3.elf';path.write_bytes(broken)
    reject([linker,'--firmware',path,'--output',dest,'--ld',a.s3_prefix+'ld','--object',obj],'metadata-3','unexpected memory layout')
    # A huge vendor input cannot cross into the native allocator.
    asm=w/'vendor-overflow.S'
    # An imported symbol keeps the oversized allocated section alive under GC.
    sourcepath=w/'vendor-root.flex';sourcepath.write_text('fn main(){return esp32_external("oversized_data");}\n')
    asm.write_text('.section .data,"aw"\n.global oversized_data\noversized_data:\n.space 16384\n')
    run([a.s3_prefix+'as',asm,'-o',w/'vendor-overflow.o'],'vendor-overflow-build')
    run([a.compiler,'--target','esp32s3-sdk-elf',sourcepath,'-o',w/'vendor-root.elf'],'vendor-root-build')
    reject([linker,'--firmware',w/'vendor-root.elf','--output',dest,'--ld',a.s3_prefix+'ld','--object',w/'vendor-overflow.o'],'vendor-data-overflow','vendor data overlaps reserved SRAM')
    asm.write_text('.section .text,"ax"\n.global oversized_code\noversized_code:\n.space 196608\n')
    run([a.s3_prefix+'as',asm,'-o',w/'vendor-code-overflow.o'],'vendor-code-overflow-build')
    sourcepath.write_text('fn main(){return esp32_external("oversized_code");}\n')
    run([a.compiler,'--target','esp32s3-sdk-elf',sourcepath,'-o',w/'vendor-code-root.elf'],'vendor-code-root-build')
    reject([linker,'--firmware',w/'vendor-code-root.elf','--output',dest,'--ld',a.s3_prefix+'ld','--object',w/'vendor-code-overflow.o'],'vendor-code-overflow','vendor code exceeds available IRAM')
    # Old stack-overlap defect must be caught by the original plain-ELF guest.
    helper=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
    tree=w/'heap-defect/source';helper['copy_closure'](ROOT/'tests/esp32/sdk-heap-bounds.flex',tree)
    heap=tree/'lib/platform/esp32-sdk-heap.flex';text=heap.read_text();anchor='if base+size>esp32_load32(esp32_state()+20) {return -22;}'
    assert text.count(anchor)==1;heap.write_text(text.replace(anchor,''))
    run([a.driver,'--compiler',a.compiler,'--work',w/'heap-defect/run','--qemu',a.qemu,'--prefix',a.prefix,'--source',tree/'tests/esp32/sdk-heap-bounds.flex','--profile','esp32-elf'],'missing-stack-guard',1,'main returned zero');controls.append('missing-stack-guard')
    tree=w/'extent-defect/source';helper['copy_closure'](ROOT/'tests/esp32/sdk-heap-bounds.flex',tree)
    heap=tree/'lib/platform/esp32-sdk-heap.flex';text=heap.read_text();anchor='base>=upper || '
    assert text.count(anchor)==1;text=text.replace(anchor,'');assert text.count('size>upper-base')==1;heap.write_text(text.replace('size>upper-base','base+size>upper'))
    text=run([a.driver,'--compiler',a.compiler,'--work',w/'extent-defect/run','--qemu',a.qemu,'--prefix',a.prefix,'--source',tree/'tests/esp32/sdk-heap-bounds.flex','--profile','esp32-elf'],'overflowing-extent',1,'guest completion/trap status');assert '0x54524150' in text and 'SHUTDOWN' in text;controls.append('overflowing-extent')
    report=dict(pass_all=True,profiles=rows,primary_header_oracle=oracle_values,rejections=controls,QEMU_positive_boots=len(profiles)+1,defect_boots=2,compiler_sha256=sha(a.compiler),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_changes=False)
    (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: {len(profiles)} memory profiles, header-derived S3 routing, {len(controls)} rejection/defect controls')

if __name__=='__main__': main()
