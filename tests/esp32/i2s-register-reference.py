#!/usr/bin/env python3
"""Verify the original I2S adapter with official C registers and Xtensa descriptors.

Supply pinned local headers, Flexscript, a host C compiler, and the existing
Xtensa cross compiler/objcopy. This tool downloads nothing and touches no board.
The host contract fixture is separate from the machine-code SoC emulator.
"""
import argparse,hashlib,json,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for flag in ['compiler','reference','work','report']:p.add_argument('--'+flag,type=Path,required=flag!='report')
p.add_argument('--cc',default='cc');p.add_argument('--cross-cc',required=True);p.add_argument('--objcopy',required=True)
a=p.parse_args();r=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);reference=a.reference.resolve();compiler=a.compiler.resolve();oracle=r/'tests/esp32/i2s-oracle'
def run(args):return subprocess.run([str(v) for v in args],cwd=r,capture_output=True,timeout=20)
def checked(args):
 result=run(args);assert result.returncode==0,(args,result.stderr.decode(errors='replace'));return result
headers={}
for item in json.loads((oracle/'sources.json').read_text()):
 name=Path(item['path']).name;data=(reference/name).read_bytes();digest=hashlib.sha256(data).hexdigest();assert digest==item['sha256'],name+' reference checksum mismatch';headers[name]=digest
program=w/'reference';checked([a.cc,'-std=gnu11','-O2','-I'+str(oracle),'-I'+str(reference),oracle/'register-reference.c','-o',program]);registers=w/'registers.bin';registers.write_bytes(checked([program]).stdout);assert len(registers.read_bytes())==9664
obj=w/'descriptors.o';descriptors=w/'descriptors.bin';checked([a.cross_cc,'-std=gnu11','-c','-I'+str(reference),oracle/'descriptor-reference.c','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.reference',obj,descriptors]);assert len(descriptors.read_bytes())==352
fixture=r/'tests/esp32/i2s-register-model.flex';model=w/'model';checked([compiler,fixture,'-o',model]);result=checked([model,registers,descriptors]);assert len(result.stdout)==8 and not result.stderr;checks,=struct.unpack('<Q',result.stdout);assert checks>=219000
controls=[]
mutations=[
 ('wrong-descriptor-length','esp32-dma.flex','used<<12','used<<13'),
 ('wrong-descriptor-owner','esp32-dma.flex','(1<<31)','(1<<30)'),
 ('missing-descriptor-overlap','esp32-dma.flex','if desc<buffer+size && buffer<desc+16 {return -22;}',''),
 ('self-linked-descriptor','esp32-dma.flex','(next<desc+16 && desc<next+16)','0'),
 ('early-ownership-publication','esp32-dma.flex','esp32_store32(desc+4,buffer);esp32_store32(desc+8,next);esp32_store32(desc+12,0);','esp32_store32(desc,size|(used<<12)|(eof<<30)|(1<<31));esp32_store32(desc+4,buffer);esp32_store32(desc+8,next);esp32_store32(desc+12,0);'),
 ('swapped-dma-resets','esp32-i2s.flex','esp_reg_update(base+0x60,1<<direction,1<<direction);esp_reg_update(base+0x60,1<<direction,0);','esp_reg_update(base+0x60,reset,reset);esp_reg_update(base+0x60,reset,0);'),
 ('rx-byte-count','esp32-i2s.flex','base+0x24,size/4','base+0x24,size'),
 ('missing-pll-precondition','esp32-i2s.flex','if (esp32_load32(0x3ff48070)&(3<<27))!=(1<<27) {return -19;}',''),
 ('wrong-serial-input','esp32-i2s.flex','let signal=155;','let signal=140;'),
 ('enabled-rx-compander','esp32-i2s.flex','(1<<8)|(1<<7)|(1<<3)','(1<<8)|(1<<3)'),
 ('wrong-sample-width','esp32-i2s.flex','(bits<<12)|(bits<<18)','((bits-1)<<12)|((bits-1)<<18)'),
 ('wrong-stereo-fifo','esp32-i2s.flex','fifo=fifo|(2<<13)|(2<<16)','fifo=fifo|(3<<13)|(3<<16)'),
 ('missing-wire-completion','esp32-i2s-chain.flex','(!direction || (esp32_load32(base+0xbc)&1))','1'),
 ('ignored-owner-return','esp32-i2s-chain.flex','(word&0x80000000)','0'),
 ('ignored-short-rx','esp32-i2s-chain.flex','(!direction && ((word>>12)&4095)!=size)','0'),
 ('unreclaimed-cancellation','esp32-i2s.flex','esp32_store32(node,esp32_load32(node)&0x7fffffff);',''),
 ('wrong-controller-stride','esp32-i2s.flex','bus*122880','bus*65536'),
 ('missing-priming-frame','esp32-i2s.flex','store8(workspace+i,0);','store8(workspace+i,1);'),
 ('short-duplex-transmission','esp32-i2s.flex','workspace,size+frame,1','workspace,size,1'),
 ('restarted-exchange-timeout','esp32-i2s.flex','cycles-elapsed,1','cycles,1'),
]
for label,module,old,new in mutations:
 directory=w/label;directory.mkdir(exist_ok=True)
 for name in ['esp32-i2s.flex','esp32-i2s-chain.flex','esp32-i2s-stream.flex','esp32-dma.flex','esp32-common.flex','esp32.flex']:
  text=(r/'lib/platform'/name).read_text()
  if name==module:assert old in text,label+' mutation pattern missing';text=text.replace(old,new)
  (directory/name).write_text(text)
 source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../lib/platform/esp32-i2s.flex"',json.dumps(str(directory/'esp32-i2s.flex'))));binary=directory/'model';checked([compiler,source,'-o',binary]);failure=run([binary,registers,descriptors]);assert failure.returncode==1 and len(failure.stderr)==16,(label,'defect not detected cleanly',failure.returncode,failure.stderr);assertion,count=struct.unpack('<QQ',failure.stderr);controls.append({'control':label,'detected':True,'assertion':assertion,'checks_before_detection':count})
report={'pass':True,'native_checks':checks,'official_register_values':52,'configuration_vectors':72,'target_abi_descriptors':12,'negative_controls':controls,'reference_headers':headers,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'cross_cc':a.cross_cc,'machine_code_emulator':False,'physical_hardware':False}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
