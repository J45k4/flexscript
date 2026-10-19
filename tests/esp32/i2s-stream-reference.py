#!/usr/bin/env python3
"""Independent C ABI,ring DMA scheduler and broken-driver controls.

Uses explicit installed tools and pinned local headers. No downloads,physical
hardware access,CPU model or compiler instruction encoders are involved.
"""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('compiler','reference','work','report'):p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--cross-cc',required=True);p.add_argument('--objcopy',required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve();reference=a.reference.resolve()
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=45)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout,q.stderr);return q
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
legacy=w/'legacy.json';checked(['python3',root/'tests/esp32/i2s-chain-reference.py','--compiler',compiler,'--reference',reference,'--cross-cc',a.cross_cc,'--objcopy',a.objcopy,'--work',w/'legacy','--report',legacy]);old=json.loads(legacy.read_text());assert old['pass'] and old['chain_checks']==159369 and old['legacy_checks']==245856
s='#include <stdint.h>\n#include <stddef.h>\n#include "esp_rom_lldesc.h"\n__attribute__((section(".reference"),used)) const struct {uint32_t magic,size,buf,next;lldesc_t cases[2][64][64];} r={0x5354524d,sizeof(lldesc_t),offsetof(lldesc_t,buf),offsetof(lldesc_t,qe),{\n'
for direction in range(2):
 s+='{\n'
 for count in range(1,65):
  s+='{' + ','.join(f'{{.size=32,.length={32 if direction else 0},.eof=1,.owner=1,.buf=(const uint8_t*){0x3ffb4000+i*256},.qe={{.stqe_next=(lldesc_t*){0x3ffb1000+((i+1)%count)*16}}}}}' for i in range(count))+'},\n'
 s+='},\n'
s+='}};\n';c=w/'reference.c';c.write_text(s);obj=w/'reference.o';abi=w/'reference.bin';checked([a.cross_cc,'-std=gnu11','-c','-I'+str(reference),c,'-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.reference',obj,abi]);assert abi.stat().st_size==98320
registers=w/'legacy/prior/registers.bin';fixture=root/'tests/esp32/i2s-stream-model.flex';binary=w/'model';checked([compiler,fixture,'-o',binary]);q=checked([binary,registers,abi]);m=re.fullmatch(rb'I2S streams: (\d+) checks passed\n',q.stdout);assert m;checks=int(m[1])
modules={n:(root/'lib/platform'/n).read_text() for n in ('esp32-i2s.flex','esp32-i2s-chain.flex','esp32-i2s-stream.flex','esp32-dma.flex','esp32-common.flex','esp32.flex')}
mutations=[
('private-single-buffer-alias-allowed','esp32-i2s.flex','if eis_internal_overlap(descriptor,16) || eis_internal_overlap(buffer,size){return -22;}',''),
('private-chain-metadata-alias-allowed','esp32-i2s-chain.flex','if eis_internal_overlap(descriptors,count*16) || eis_internal_overlap(blocks,count*8){return -22;}',''),
('private-chain-payload-alias-allowed','esp32-i2s-chain.flex','if eis_internal_overlap(data,size){return -22;}',''),
('private-exchange-workspace-alias-allowed','esp32-i2s.flex',' || eis_internal_overlap(workspace,size+frame)',''),
('lease-exhaustion-ignored','esp32-i2s-stream.flex','if load64(p+8)>=0x7ffffffffffffe','if 0'),
('lease-channel-not-encoded','esp32-i2s-stream.flex','id*256+(bus*2+direction)*64+index+1','id*256+index+1'),
('ring-does-not-close','esp32-i2s-stream.flex','let next=descriptors+((i+1)%count)*16;','let next=descriptors+(i+1)*16;'),
('RX-EOF-is-entire-ring','esp32-i2s-stream.flex','base+0x24,bytes/4','base+0x24,total/4'),
('lease-generation-restarts','esp32-i2s-stream.flex','store64(p+16,0);store64(p+24,0);','store64(p+8,0);store64(p+16,0);store64(p+24,0);'),
('stale-generation-accepted','esp32-i2s-stream.flex',' || load64(item+16)!=token',''),
('out-of-order-release-allowed','esp32-i2s-stream.flex','if index!=load64(p+80){esp32_irq_restore(ps);return -11;}',''),
('claim-before-DMA-completion','esp32-i2s-stream.flex',' || (esp32_load32(desc)&0x80000000)',''),
('release-does-not-consume-token','esp32-i2s-stream.flex','store64(item+16,0);store64(item+24,0);store64(p+80,','store64(p+80,'),
('wrong-refilled-owner','esp32-dma.flex','|(1<<31)',''),
('short-RX-is-full-block','esp32-i2s-stream.flex',' || (completed && (used!=size || !(word&0x40000000)))',''),
('mutable-TX-blocks-may-alias','esp32-i2s-stream.flex','if eia_overlap(data,bytes,esp32_load32(blocks+j*8),bytes)','if 0'),
('nonuniform-ring-allowed','esp32-i2s-stream.flex','esp32_load32(blocks+i*8+4)!=bytes || ',''),
('peer-resource-check-ignored','esp32-i2s-chain.flex','if eis_active(state,direction){return eis_resource_overlap(state,direction,address,size);}','if eis_active(state,direction){return 0;}'),
('error-does-not-cancel-DMA','esp32-i2s-stream.flex','eia_stop(bus,direction,state);return error;','return error;'),
('descriptor-topology-unchecked','esp32-i2s-stream.flex',' || esp32_load32(desc+8)!=next',''),
('getters-return-first-node','esp32-i2s-stream.flex','value=load64(item);','value=load64(eis_control(state,direction)+128);'),
('progress-not-counted','esp32-i2s-stream.flex','store64(p+56,load64(p+56)+1);',''),
('wrong-refill-length','esp32-i2s-stream.flex','let used=0;if direction{used=load64(item+8);}','let used=0;if direction{used=4;}'),
('finite-poll-consumes-ring','esp32-i2s-chain.flex','if eis_active(state,direction){esp32_irq_restore(ps);return -16;}',''),
('finite-wait-consumes-ring','esp32-i2s.flex','if eis_active(state,direction){return -16;}',''),
('TX-starvation-is-not-an-error','esp32-i2s-stream.flex','if direction{error= -32;}','if direction{error=0;}'),
]
controls=[]
for label,module,old_text,new_text in mutations:
 assert old_text in modules[module],label
 d=w/label;d.mkdir(exist_ok=True)
 for n,text in modules.items():(d/n).write_text(text.replace(old_text,new_text) if n==module else text)
 f=d/'model.flex';f.write_text(fixture.read_text().replace('"../../lib/platform/esp32-i2s.flex"',json.dumps(str(d/'esp32-i2s.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))));b=d/'model';checked([compiler,f,'-o',b]);q=run([b,registers,abi]);assert q.returncode==1 and re.fullmatch(rb'I2S stream case \d+: .+\n',q.stderr),(label,q.returncode,q.stderr)
 controls.append({'control':label,'detected':True,'diagnostic':q.stderr.decode().strip()});print('Stream controls:',len(controls),flush=True)
r={'pass':True,'scope_complete':False,'physical_hardware':False,'stream_checks':checks,'stream_controls':controls,'chain_checks':old['chain_checks'],'legacy_checks':old['legacy_checks'],'prior_controls':len(old['chain_defect_controls'])+old['legacy_defect_controls'],'GNU_ABI_sha256':sha(abi),'compiler_sha256':sha(compiler),'source_sha256':{n:hashlib.sha256(v.encode()).hexdigest() for n,v in modules.items()},'remaining':'Machine-code and physical sustained continuity,coalesced IRQ/FIFO timing,starvation/recovery and full I2S/DMA scope remain required.'};a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',checks,'stream checks/',len(controls),'controls;prior405225/36')
