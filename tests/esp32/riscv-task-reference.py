#!/usr/bin/env python3
"""Stock-ROM task/context checks with independent LLVM C register consumers."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--compiler',required=True,type=Path)
    p.add_argument('--qemu',required=True,type=Path)
    p.add_argument('--work',required=True,type=Path)
    p.add_argument('--clang',default='clang')
    p.add_argument('--ld',default='ld.lld')
    p.add_argument('--execute-c6',action='store_true')
    p.add_argument('--qemu-c6',type=Path)
    a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();cases=[]
    def run(args):
        r=subprocess.run(list(map(str,args)),cwd=root,text=True,capture_output=True,timeout=60)
        assert r.returncode==0,(args,r.stdout,r.stderr)
        return r
    def source_for(text,chip):
        text=text.replace('esp32c3','esp32c'+str(chip))
        if chip==6:text=text.replace('0x3fcb8000','0x40848000')
        return re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
    def boot(name,text,chip,objects=(),trap=False,zero=False):
        prefix=work/(name+'-c'+str(chip));source=Path(str(prefix)+'.flex');source.write_text(source_for(text,chip));image=Path(str(prefix)+'.bin');elf=Path(str(prefix)+'.elf')
        run([compiler,'--target','esp32c'+str(chip),source,'-o',image] if not objects else [compiler,'--target','esp32c'+str(chip)+'-elf',source,'-o',elf])
        if not objects:run([compiler,'--target','esp32c'+str(chip)+'-elf',source,'-o',elf])
        else:
            linked=Path(str(prefix)+'-linked.elf');cmd=[work/'linker','--ld',a.ld,'--firmware',elf,'--output',linked,'--image',image]
            for obj in objects:cmd+=['--object',obj]
            run(cmd);elf=linked
        report=Path(str(prefix)+'.json');cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--elf',elf,'--report',report]
        if chip==6 and not a.execute_c6:cmd+=['--validate-only']
        else:
            if trap:cmd+=['--trap']
            if zero:cmd+=['--zero-memory',('0x3fcb0000' if chip==3 else '0x40840000')+':512']
        run(cmd);row=json.loads(report.read_text());row['case']=name;row['context_unchanged_checked']=zero and (chip==3 or a.execute_c6)
        cases.append(row)
    run([compiler,'scripts/esp32-link.flex','-o',work/'linker'])
    for name in ['riscv-context','riscv-sdk-runtime','riscv-sdk-timers','riscv-sdk-priorities','riscv-sdk-guards']:
        text=(root/'tests/esp32'/(name+'.flex')).read_text()
        for chip in (3,6):boot(name,text,chip)
    base=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections']
    for march in ['rv32im_zicsr','rv32imc_zicsr']:
        for opt in ['-O0','-O2','-Os']:
            objects=[]
            for suffix in ['c','S']:
                obj=work/(march+opt+'-'+suffix+'.o');run([*base,'-march='+march,opt,'-c','tests/esp32/riscv-context-c.'+suffix,'-o',obj]);objects.append(obj)
            for chip in (3,6):boot('C-context-'+march+opt,(root/'tests/esp32/riscv-context-c.flex').read_text(),chip,objects)
    setup='fn worker(n){return n;}fn main(){let from=alloc(1024);let to=from+512;let stack=alloc(8192);let top=stack+8192-16;store64(top,911);esp32_store32(to+8,top);esp32_store32(to+256,esp32_callback(worker));esp32_store32(to+304,stack);'
    bad=[('high-from','esp32_switch(from+0x100000000,to);'),('high-to','esp32_switch(from,to+0x100000000);'),('unaligned-from','esp32_switch(from+8,to);'),('unaligned-to','esp32_switch(from,to+8);'),('below-data','esp32_switch(16,to);'),('beyond-context-region','esp32_switch(from,esp32_state()+131072);'),('overlapping-contexts','esp32_switch(from,from+16);'),('SP-alignment','esp32_store32(to+8,top+1);esp32_switch(from,to);'),('SP-upper-bound','esp32_store32(to+8,esp32_state()+196608);esp32_switch(from,to);'),('SP-floor','esp32_store32(to+8,stack);esp32_switch(from,to);'),('floor-alignment','esp32_store32(to+304,stack+1);esp32_switch(from,to);'),('floor-lower-bound','esp32_store32(to+304,16);esp32_switch(from,to);'),('null-PC','esp32_store32(to+256,0);esp32_switch(from,to);'),('odd-PC','esp32_store32(to+256,esp32_callback(worker)+1);esp32_switch(from,to);'),('PC-region','esp32_store32(to+256,esp32_state());esp32_switch(from,to);'),('ISR-rejected','esp32_store32(esp32_state()+16,1);esp32_switch(from,to);')]
    for name,code in bad:
        for chip in (3,6):boot(name,setup+code+'return 0;}',chip,trap=True,zero=True)
    report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),guard_unchanged_checks=sum(x['context_unchanged_checked'] for x in cases),cases=cases,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),physical_hardware=False,preemption=False,automatic_TLS=False,vendor_library_startup=False)
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: RISC-V task/context',report['C3_ROM_boots'],'C3 ROM boots,',report['C6_ROM_boots'],'C6 ROM boots,',report['C6_package_checks'],'C6 packages')


if __name__=='__main__':main()
