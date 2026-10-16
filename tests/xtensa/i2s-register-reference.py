#!/usr/bin/env python3
"""Verify original I2S against C registers, target descriptors and serial peers.

This model imports neither platform drivers nor compiler instruction encoders.
Supply explicit existing tools and the pinned local headers; no downloads.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for flag in ['compiler','reference','work','report']:p.add_argument('--'+flag,type=Path,required=flag!='report')
p.add_argument('--cc',default='cc');p.add_argument('--cross-cc',required=True);p.add_argument('--objcopy',required=True);p.add_argument('--skip-controls',action='store_true')
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);refs=a.reference.resolve();compiler=a.compiler.resolve();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();oracle=root/'tests/esp32/i2s-oracle';headers={}
for item in json.loads((oracle/'sources.json').read_text()):
 name=Path(item['path']).name;assert sha(refs/name)==item['sha256'],name+' reference mismatch';headers[name]=item['sha256']
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=25)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout.decode(errors='replace'),q.stderr.decode(errors='replace'));return q
program=work/'reference';reference=work/'reference.bin';checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(root/'tests/xtensa/soc-oracle'),'-I'+str(oracle),'-I'+str(refs),root/'tests/xtensa/soc-oracle/i2s-reference.c','-o',program]);reference.write_bytes(checked([program]).stdout);assert reference.stat().st_size==19168
obj=work/'descriptors.o';descriptors=work/'descriptors.bin';checked([a.cross_cc,'-std=gnu11','-c','-I'+str(refs),oracle/'descriptor-reference.c','-o',obj]);checked([a.objcopy,'-O','binary','--only-section=.reference',obj,descriptors]);assert descriptors.stat().st_size==352
fixture=root/'tests/xtensa/i2s-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);q=checked([binary,reference,descriptors]);match=re.fullmatch(rb'I2S model: (\d+) checks passed\n',q.stdout);assert match;checks=int(match[1]);assert checks>=61000
modules=['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex'];controls=[]
mutations=[
 ('wrong-transmit-signal','esp32-i2s-emulator.flex','return 163+bus*26;','return 162+bus*26;'),
 ('wrong-receive-signal','esp32-i2s-emulator.flex','return 155+bus*26;','return 140+bus*26;'),
 ('missing-philips-ws-lead','esp32-i2s-emulator.flex','let ws=pos>=bits && pos<bits*2;','let ws=pos>bits && pos<=bits*2;'),
 ('reversed-transmit-bits','esp32-i2s-emulator.flex','>>(bits-1-index)','>>index'),
 ('data-changes-on-sampling-edge','esp32-i2s-emulator.flex','let result=0;if direction{result=se_gpio_peripheral','let result=0;if direction && load64(e+16){result=se_gpio_peripheral'),
 ('swapped-transmit-channels','esp32-i2s-emulator.flex','if !(se_i2s_get(s,bus,8)&(1<<16))','if (se_i2s_get(s,bus,8)&(1<<16))'),
 ('fake-received-zeroes','esp32-i2s-emulator.flex','let data=se_gpio_signal(s,se_i2s_signal(bus,0,2));','let data=0;'),
 ('reversed-receive-bits','esp32-i2s-emulator.flex','((load64(e+128)<<1)|data)','((load64(e+128)>>1)|(data<<(bits-1)))'),
 ('partial-eof-reuses-descriptor','esp32-i2s-emulator.flex','if load64(q+72){if !se_i2s_dma_load','if at==load64(q+24){if !se_i2s_dma_load'),
 ('rx-count-is-bytes','esp32-i2s-emulator.flex','words>=count','words*4>=count'),
 ('wrong-buffer-pointer-offset','esp32-i2s-emulator.flex','store64(q+16,em_u32(desc+4))','store64(q+16,em_u32(desc+8))'),
 ('ignored-ownership-check','esp32-i2s-emulator.flex','((control&4096) && !(head&0x80000000))','0'),
 ('ignored-buffer-alignment','esp32-i2s-emulator.flex','(em_u32(desc+4)&3) || ',''),
 ('missing-rx-ownership-return','esp32-i2s-emulator.flex','load64(q+56)&~0xc0fff000','load64(q+56)&~0x40fff000'),
 ('ignored-writeback-disable','esp32-i2s-emulator.flex','if se_i2s_get(s,bus,0x60)&64{','if 1{'),
 ('early-tx-eof','esp32-i2s-emulator.flex','if se_i2s_get(s,bus,0x60)&256{','if 0{'),
 ('ignored-early-eof-mode','esp32-i2s-emulator.flex','if se_i2s_get(s,bus,0x60)&256{','if 1{'),
 ('premature-wire-idle','esp32-i2s-emulator.flex','let value=!load64(se_i2s_engine(s,bus,1));','let value=!load64(se_i2s_engine(s,bus,1)) || load64(se_i2s_dma(s,bus,1)+40)==load64(se_i2s_dma(s,bus,1)+32);'),
 ('dma-errors-fault-cpu','esp32-i2s-emulator.flex','let bit=13+direction;return se_i2s_event','xt_fault(load64(s),-14,load64(q+8));let bit=13+direction;return se_i2s_event'),
 ('lost-clock-phase-on-gate','esp32-i2s-emulator.flex','store64(e+64,load64(e+64)+delta);',''),
 ('missing-clock-freeze','esp32-i2s-emulator.flex','store64(e+8,load64(e+8)+delta);',''),
 ('wrong-source-clock-ratio','esp32-i2s-emulator.flex','store64(e+56,a*4)','store64(e+56,a*2)'),
 ('discarded-fractional-carry','esp32-i2s-emulator.flex','let phase=load64(e+72)+load64(e+48);','let phase=load64(e+48);'),
 ('wrong-controller-stride','esp32-i2s-emulator.flex','bus*122880','bus*65536'),
 ('wrong-native-irq-source','esp32-emulator.flex','se_source(s,32+id,se_i2s_irq(s,id))','se_source(s,33+id,se_i2s_irq(s,id))'),
 ('ignored-interrupt-enable','esp32-i2s-emulator.flex','se_i2s_get(s,bus,12)&se_i2s_get(s,bus,20)','se_i2s_get(s,bus,12)'),
 ('missing-interrupt-w1tc','esp32-i2s-emulator.flex','se_i2s_put(s,bus,12,se_i2s_get(s,bus,12)&~value);',''),
 ('swapped-dma-reset-bits','esp32-i2s-emulator.flex','if value&(1<<direction){em_zero','if value&(1<<(1-direction)){em_zero'),
 ('missing-dport-reset','esp32-emulator.flex','if value&(1<<(4+i*17)){se_i2s_reset(s,i);}',''),
 ('lost-multi-device-order','esp32-emulator.flex','|se_i2s_active(s)',''),
 ('bypassed-gpio-observer','esp32-gpio-emulator.flex','let audio=se_i2s_inputs(s);if audio{return audio;}',''),
]
if not a.skip_controls:
 for label,module,old,new in mutations:
  directory=work/label;directory.mkdir(exist_ok=True)
  for name in modules:
   text=clone_source(root,name)
   if name==module:assert old in text,label+' mutation missing';text=text.replace(old,new)
   (directory/name).write_text(text.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex')))))
  source=directory/'model.flex';source.write_text(fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex'))));model=directory/'model';checked([compiler,source,'-o',model]);q=run([model,reference,descriptors]);assert q.returncode==1 and b'I2S context ' in q.stderr,(label,'defect not rejected cleanly',q.returncode,q.stderr.decode(errors='replace'));controls.append({'control':label,'detected':True,'diagnostic':q.stderr.decode(errors='replace').strip()})
  if len(controls)%5==0:print('I2S defect controls:',len(controls),flush=True)
report={'pass':True,'scope_complete':False,'checks':checks,'official_register_values':84,'independent_wave_vectors':18,'target_descriptor_vectors':12,'negative_controls':controls,'reference_headers':headers,'compiler_sha256':sha(compiler),'reference_sha256':sha(reference),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [*[source_path(root,n) for n in modules],fixture,root/'tests/xtensa/soc-oracle/i2s-reference.c']},'physical_hardware':False,'same_image_physical_replay':False,'limitations':['Original functional stereo Philips16/32 DMA/wire subset; S3 and full audio modes remain open.','CPU FIFO ports and nondefault FIFO thresholds are unsupported; FIFO occupancy/arbitration/precise DMA write timing are not calibrated.','PLL source is an explicit80MHz system profile. ROM clock initialization and windowed ABI are not modeled.']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
