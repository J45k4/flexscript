#!/usr/bin/env python3
"""Check original ESP32 I2C against pinned C layouts and independent wire peers.

No platform driver or compiler encoder is imported by the model fixture.
Only supplied local headers and an explicit compiler are used.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--soc-reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--cc',default='cc');p.add_argument('--skip-controls',action='store_true');a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();refs=a.reference.resolve();soc=a.soc_reference.resolve();headers={};sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 needed={'i2c_struct.h','i2c_reg.h','dport_reg.h','gpio_sig_map.h','reg_base.h'}
 for item in json.loads((root/'tests/esp32/bus-oracle/sources.json').read_text()):
  name=Path(item['path']).name
  if name in needed:assert sha(refs/name)==item['sha256'],name;headers['i2c/'+name]=item['sha256']
 assert set(x.split('/')[-1] for x in headers)==needed
 needed={'gpio_reg.h','io_mux_reg.h','interrupts.h'}
 for item in json.loads((root/'tests/xtensa/soc-oracle/sources.json').read_text()):
  name=Path(item['path']).name;chip=item.get('chip',item['path'].split('/')[1])
  if chip=='esp32' and name in needed:assert sha(soc/name)==item['sha256'],name;headers['soc/'+name]=item['sha256']
 assert len(headers)==8
 def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True)
 def checked(args):
  q=run(args);assert q.returncode==0,(args,q.stdout.decode(errors='replace'),q.stderr.decode(errors='replace'));return q
 program=work/'reference';reference=work/'reference.bin';checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(root/'tests/xtensa/soc-oracle'),'-I'+str(root/'tests/esp32/bus-oracle'),'-I'+str(refs),'-I'+str(soc),root/'tests/xtensa/soc-oracle/i2c-reference.c','-o',program]);reference.write_bytes(checked([program]).stdout);assert reference.stat().st_size==23128
 fixture=root/'tests/xtensa/i2c-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);q=checked([binary,reference]);match=re.fullmatch(rb'I2C model: (\d+) checks passed\n',q.stdout);assert match;checks=int(match[1]);controls=[]
 mutations=[
  ('wrong-low-period','esp32-i2c-emulator.flex','let low=em_u32(p+1280)+se_apb_factor(s);','let low=em_u32(p+1280);'),
  ('wrong-high-period','esp32-i2c-emulator.flex','em_u32(p+1280+56)+7','em_u32(p+1280+56)+6'),
  ('ignored-sample-delay','esp32-i2c-emulator.flex','se_i2c_high(s,bus,10,em_u32(p+1280+52))','se_i2c_high(s,bus,10,0)'),
  ('early-input-sample-with-correct-clock','esp32-i2c-emulator.flex','if result{return 0;}}else if phase==10{result=se_i2c_master_sample(s,bus);','if result{return 0;}result=se_i2c_master_sample(s,bus);}else if phase==10{'),
  ('missing-restart-low-time','esp32-i2c-emulator.flex','if !load64(p+256){wait=em_u32(p+1280)+se_apb_factor(s);}',''),
  ('delayed-timeout-until-wire-event','esp32-i2c-emulator.flex','let now=load64(s+16);if load64(p+80) && now>=load64(p+80){return se_i2c_abort(s,bus,256);}let iterations=0;','let now=load64(s+16);let iterations=0;'),
  ('missing-timeout-clock-freeze','esp32-i2c-emulator.flex','if load64(p+80){store64(p+80,load64(p+80)+delta);}',''),
  ('end-restart-releases-bus','esp32-i2c-emulator.flex','if !(previous&256){let result=se_i2c_release(s,bus);if result{return result;}}','let result=se_i2c_release(s,bus);if result{return result;}'),
  ('wrong-transmit-bit-order','esp32-i2c-emulator.flex','let shift=7-bit;','let shift=bit;'),
  ('fake-pulled-up-master-input','esp32-i2c-emulator.flex','let data=se_gpio_signal(s,se_i2c_signal(bus,1));if data<0{return data;}','let data=1;'),
  ('ignored-ack-check','esp32-i2c-emulator.flex','if (command&256) && data!=((command>>9)&1)','if 0'),
  ('ignored-ack-expectation','esp32-i2c-emulator.flex','data!=((command>>9)&1)','data!=0'),
  ('missing-arbitration-loss','esp32-i2c-emulator.flex','if wanted && !data','if 0'),
  ('wrong-rx-count-shift','esp32-i2c-emulator.flex','(load64(p+120)<<8)','(load64(p+120)<<9)'),
  ('missing-command-done','esp32-i2c-emulator.flex','se_i2c_get(s,bus,88+index*4)|0x80000000','se_i2c_get(s,bus,88+index*4)'),
  ('missing-rx-fifo-reset','esp32-i2c-emulator.flex','if value&4096{store64(p+112,0);store64(p+120,0);}',''),
  ('missing-tx-fifo-reset','esp32-i2c-emulator.flex','if value&8192{store64(p+128,0);store64(p+136,0);}',''),
  ('unprotected-dport-rx','esp32-i2c-emulator.flex','!synchronized || !(xt_sr(load64(s),230)&15)','0'),
  ('unmasked-dport-rx','esp32-i2c-emulator.flex','!(xt_sr(load64(s),230)&15)','0'),
  ('missing-w1tc','esp32-i2c-emulator.flex','se_i2c_put(s,bus,32,se_i2c_get(s,bus,32)&~value);',''),
  ('ignored-irq-enable','esp32-i2c-emulator.flex','se_i2c_raw(s,bus)&se_i2c_get(s,bus,40)','se_i2c_raw(s,bus)'),
  ('wrong-irq-source','esp32-emulator.flex','se_source(s,49+id,se_i2c_irq(s,id))','se_source(s,48+id,se_i2c_irq(s,id))'),
  ('missing-gpio-listener','esp32-gpio-emulator.flex','let i2c=se_i2c_inputs(s);','let i2c=0;'),
  ('missing-module-reset','esp32-emulator.flex','if value&(1<<(7+i*11)){se_i2c_reset(s,i);}','if 0{se_i2c_reset(s,i);}'),
  ('missing-slave-address-check','esp32-i2c-emulator.flex','(byte>>1)==(se_i2c_get(s,bus,16)&127)','1'),
  ('slave-stores-address-in-rx','esp32-i2c-emulator.flex','if phase==1{let match=','if phase==1{se_i2c_rx_push(s,bus,byte&255);let match='),
  ('ignored-slave-nack','esp32-i2c-emulator.flex','if load64(p+232){store64(p+176,4);','if 0{store64(p+176,4);'),
  ('missing-slave-clock-stretch','esp32-i2c-emulator.flex','return se_i2c_out(s,bus,0,0);','return se_i2c_out(s,bus,0,1);'),
 ]
 if not a.skip_controls:
  for label,module,old,new in mutations:
   directory=work/label;directory.mkdir(exist_ok=True)
   for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex']:
    text=clone_source(root,name)
    if name==module:assert text.count(old)==1,(label,text.count(old));text=text.replace(old,new)
    (directory/name).write_text(text.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex')))))
   source=fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));test=directory/'model.flex';test.write_text(source);binary=directory/'model';checked([compiler,test,'-o',binary]);q=run([binary,reference]);message=q.stderr.decode();assert q.returncode==1 and re.search(r'I2C case \d+ check \d+: .+\n',message),(label,q.returncode,message);controls.append({'control':label,'detected':True,'failure':message.strip()});print(label+': detected',flush=True)
 report={'pass':True,'scope_complete':False,'checks':checks,'official_values':87,'external_master_cases':50,'external_slave_cases':50,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'compiler_sha256':sha(compiler),'reference_sha256':sha(reference),'source_sha256':{str(p.relative_to(root)):sha(p) for p in [source_path(root,'esp32-i2c-emulator.flex'),source_path(root,'esp32-emulator.flex'),source_path(root,'esp32-gpio-emulator.flex'),fixture,root/'tests/xtensa/soc-oracle/i2c-reference.c']},'limitations':['Original ESP32 functional wire model; S3,10-bit,non-FIFO,address-memory modes,filtering and low-level sampling remain unsupported.','Independent wire peers establish GPIO-level protocol behavior, not calibrated electrical or cross-revision timing.']}
 if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'pass':True,'checks':checks,'controls':len(controls)}));return 0
if __name__=='__main__':raise SystemExit(main())
