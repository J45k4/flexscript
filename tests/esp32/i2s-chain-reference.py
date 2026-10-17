#!/usr/bin/env python3
"""Independent GNU ABI vectors and adversarial tests for native finite I2S chains.

Explicit existing tools and pinned SDK headers only. Does not access hardware
or import the machine-code emulator. C is reference tooling,not a runtime.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('compiler','reference','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--cross-cc',required=True);p.add_argument('--objcopy',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve()
def run(args):return subprocess.run([str(v) for v in args],cwd=root,capture_output=True,timeout=30)
def checked(args):
    q=run(args);assert q.returncode==0,(args,q.stdout,q.stderr);return q
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
# Run the existing independent register/ABI fixture too; moving completion
# logic into its own module must preserve all legacy defect detections.
old=work/'prior.json'
checked(['python3',root/'tests/esp32/i2s-register-reference.py','--compiler',compiler,'--reference',a.reference.resolve(),'--work',work/'prior','--report',old,'--cross-cc',a.cross_cc,'--objcopy',a.objcopy])
legacy=json.loads(old.read_text());assert legacy['pass'] and legacy['native_checks']==245856
# Emit C initializers,never encoded descriptor words. The real Xtensa C
# compiler supplies size/length/EOF/owner bitfields and32-bit pointer layout.
s='#include <stdint.h>\n#include <stddef.h>\n#include "esp_rom_lldesc.h"\n__attribute__((section(".reference"),used)) const struct {uint32_t magic,size,buf,next;lldesc_t cases[2][64][64];} r={0x49433238,sizeof(lldesc_t),offsetof(lldesc_t,buf),offsetof(lldesc_t,qe),{\n'
for direction in range(2):
    s+='{\n'
    for count in range(1,65):
        s+='{'
        for i in range(count):
            size=8*(1+i%31);next_desc=0x3ffb1000+(i+1)*16 if i+1<count else 0
            s+=f'{{.size={size},.length={size if direction else 0},.eof={int(i+1==count)},.owner=1,.buf=(const uint8_t*){0x3ffb4000+i*256},.qe={{.stqe_next=(lldesc_t*){next_desc}}}}},'
        s+='},\n'
    s+='},\n'
s+='}};\n';c=work/'descriptor-vectors.c';c.write_text(s);obj=work/'descriptor-vectors.o';abi=work/'descriptor-vectors.bin'
checked([a.cross_cc,'-std=gnu11','-c','-I'+str(a.reference.resolve()),c,'-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.reference',obj,abi]);assert len(abi.read_bytes())==98320
registers=work/'prior/registers.bin';fixture=root/'tests/esp32/i2s-chain-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);q=checked([binary,registers,abi]);m=re.fullmatch(rb'I2S finite chains: (\d+) checks passed\n',q.stdout);assert m;checks=int(m[1])
modules={n:(root/'lib/platform'/n).read_text() for n in ('esp32-i2s.flex','esp32-i2s-chain.flex','esp32-i2s-stream.flex','esp32-dma.flex','esp32-common.flex','esp32.flex')}
mutations=[
('chain-owner-return-first-node-only','esp32-i2s.flex','while descriptor && i<count','while descriptor && i<1'),
('wrong-controller-state-stride','esp32-i2s.flex','bus*256','bus*128'),
('wrong-RX-total-units','esp32-i2s-chain.flex','base+0x24,total/4','base+0x24,total'),
('EOF-on-every-descriptor','esp32-i2s-chain.flex','next,i+1==count','next,1'),
('missing-middle-owner-check','esp32-i2s-chain.flex','while i<n{let word','while i<1{let word'),
('no-chain-peer-resource-check','esp32-i2s-chain.flex','if busy&(1<<peer)','if 0'),
('no-single-peer-resource-check','esp32-i2s.flex','if busy&(1<<peer)','if 0'),
('RX-payload-alias-allowed','esp32-i2s-chain.flex','if !direction{let j=0;','if 0{let j=0;'),
('metadata-descriptor-alias-allowed','esp32-i2s-chain.flex','if eia_overlap(descriptors,count*16,blocks,count*8){return -22;}',''),
('count-boundary65-allowed','esp32-i2s-chain.flex','count>64','count>65'),
('chain-completes-before-TX-idle','esp32-i2s-chain.flex','(!direction || (esp32_load32(base+0xbc)&1))','1'),
('poll-consumes-pending-transfer','esp32-i2s-chain.flex','if result{eia_stop(bus,direction,state);}','eia_stop(bus,direction,state);'),
('RX-IRQ-uses-TX-bit','esp32-i2s-chain.flex','return (1<<9)|(1<<10)|(1<<13);','return (1<<12)|(1<<10)|(1<<13);'),
('chain-next-link-discarded','esp32-i2s-chain.flex','next=descriptors+(i+1)*16','next=0'),
('chain-byte-count-is-first-block','esp32-i2s-chain.flex','state+72+direction*16,total','state+72+direction*16,esp32_load32(blocks+4)'),
('cancel-clears-peer-status','esp32-i2s.flex','base+0x18,eia_status_mask(direction)','base+0x18,0x1ffff'),
]
controls=[]
for label,module,old_text,new_text in mutations:
    assert old_text in modules[module],label
    d=work/label;d.mkdir(exist_ok=True)
    for n,text in modules.items():(d/n).write_text(text.replace(old_text,new_text) if n==module else text)
    text=fixture.read_text().replace('"../../lib/platform/esp32-i2s.flex"',json.dumps(str(d/'esp32-i2s.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')))
    source=d/'model.flex';source.write_text(text);binary=d/'model';checked([compiler,source,'-o',binary]);q=run([binary,registers,abi])
    assert q.returncode==1 and re.fullmatch(rb'I2S chain case \d+: .+\n',q.stderr),(label,'defect not caught by assertion',q.returncode,q.stderr)
    controls.append({'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()})
    print('I2S chain controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'physical_hardware':False,'chain_checks':checks,'chain_defect_controls':controls,'legacy_checks':legacy['native_checks'],'legacy_defect_controls':len(legacy['negative_controls']),'GNU_ABI_cases':128,'GNU_ABI_descriptors':4160,'GNU_ABI_sha256':sha(abi),'compiler_sha256':sha(compiler),'source_sha256':{n:hashlib.sha256(v.encode()).hexdigest() for n,v in modules.items()},'remaining':'Full machine-code image,physical PCM/IRQ chains,cached-flash native execution and continuous rings remain unverified.'}
a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',checks,'chain checks/',len(controls),'defects;legacy',legacy['native_checks'],'/',len(legacy['negative_controls']))
