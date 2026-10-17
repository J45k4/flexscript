#!/usr/bin/env python3
"""Check original ESP32 RMT modeling against pinned C definitions and wire stimuli."""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--rmt-reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--cc',default='cc');a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();headers={}
for manifest,base,flat in [(root/'tests/xtensa/soc-oracle/sources.json',a.reference.resolve(),False),(root/'tests/esp32/signal-oracle/sources.json',a.rmt_reference.resolve(),True)]:
 for item in json.loads(manifest.read_text()):
  parts=item['path'].split('/');name=Path(item['path']).name if flat else item.get('chip',parts[1])+'/'+parts[-1];blob=(base/name).read_bytes();assert hashlib.sha256(blob).hexdigest()==item['sha256'],name;headers[('rmt/' if flat else 'soc/')+name]=item['sha256']
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True)
def checked(args):
 q=run(args);assert q.returncode==0,(args,q.stdout.decode(errors='replace'),q.stderr.decode(errors='replace'));return q
reference=work/'reference.bin';program=work/'reference';oracle=root/'tests/xtensa/soc-oracle';checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-I'+str(oracle),'-I'+str(a.rmt_reference.resolve()),'-I'+str(a.reference.resolve()/'esp32'),oracle/'rmt-reference.c','-o',program]);reference.write_bytes(checked([program]).stdout);assert len(reference.read_bytes())==608
fixture=root/'tests/xtensa/rmt-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);q=checked([binary,reference]);match=re.fullmatch(rb'RMT model: (\d+) checks passed\n',q.stdout);assert match;checks=int(match[1]);controls=[]
mutations=[
 ('idle-fixed-bit-as-output-enable','esp32-rmt-emulator.flex','return se_gpio_peripheral(s,87+ch,level,1);','return se_gpio_peripheral(s,87+ch,level,(c>>19)&1);'),
 ('ignored-eof-level','esp32-rmt-emulator.flex','if !(se_rmt_c1(s,ch)&(1<<19)){let edge=','if 0{let edge='),
 ('wrong-rx-memory-stride','esp32-rmt-emulator.flex','let at=s+263168+ch*256+(index/2)*4;','let at=s+263168+ch*252+(index/2)*4;'),
 ('wrong-rx-level-position','esp32-rmt-emulator.flex','load64(p+40)<<15','load64(p+40)<<14'),
 ('missing-final-idle-terminator','esp32-rmt-emulator.flex','se_rmt_rx_word(s,ch,0)','se_rmt_rx_word(s,ch,1)'),
 ('missing-rx-capacity-check','esp32-rmt-emulator.flex','if index>=cap{return se_rmt_error(s,ch,1<<28);}','if 0{return se_rmt_error(s,ch,1<<28);}'),
 ('missing-rx-owner-error','esp32-rmt-emulator.flex','if !(se_rmt_c1(s,ch)&32)','if 0'),
 ('wrong-divider-zero','esp32-rmt-emulator.flex','if !n{n=256;}','if !n{n=255;}'),
 ('wrong-ref-tick-source','esp32-rmt-emulator.flex','n=n*80;','n=n*40;'),
 ('ignored-rx-filter','esp32-rmt-emulator.flex','if cfg&128{filter=(cfg>>8)&255;}',''),
 ('wrong-tx-matrix-signal','esp32-rmt-emulator.flex','return se_gpio_peripheral(s,87+ch,half>>15,1);','return se_gpio_peripheral(s,88+ch,half>>15,1);'),
 ('wrong-tx-status-shift','esp32-rmt-emulator.flex','(ch*64+index/2)<<12','(ch*64+index/2)<<10'),
 ('missing-tx-clock-freeze','esp32-rmt-emulator.flex','store64(p+8,load64(p+8)+delta);',''),
 ('ignored-interrupt-mask','esp32-rmt-emulator.flex','se_rmt_get(s,160)&se_rmt_get(s,168)','se_rmt_get(s,160)'),
 ('missing-w1tc','esp32-rmt-emulator.flex','se_rmt_put(s,160,se_rmt_get(s,160)&~value);',''),
 ('wrong-rmt-interrupt-route','esp32-emulator.flex','se_source(s,47,se_rmt_irq(s))','se_source(s,46,se_rmt_irq(s))'),
 ('missing-gpio-capture','esp32-gpio-emulator.flex','let rmt=se_rmt_inputs(s);','let rmt=0;'),
 ('collapsed-device-timeline','esp32-emulator.flex','if se_chip(s) || !(load64(s+265472)|load64(s+265480)|load64(se_i2c(s,0))|load64(se_i2c(s,1))|se_i2s_active(s)|load64(se_clock(s)+64)|se_flash_pending(s)){return se_advance_step(s,delta);}','if 1{return se_advance_step(s,delta);}'),
 ('wrong-rx-wait-state','esp32-rmt-emulator.flex','state=4;if load64(p+32)','state=0;if load64(p+32)'),
 ('wrong-channel-memory-size','esp32-rmt-emulator.flex','return blocks*128;','return blocks*64;'),
]
for label,module,old,new in mutations:
 directory=work/label;directory.mkdir(exist_ok=True)
 for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex']:
  source=clone_source(root,name)
  if name==module:assert source.count(old)==1,(label,source.count(old));source=source.replace(old,new)
  (directory/name).write_text(source.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex')))))
 source=fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));test=directory/'model.flex';test.write_text(source);binary=directory/'model';checked([compiler,test,'-o',binary]);q=run([binary,reference]);message=q.stderr.decode();assert q.returncode==1 and re.search(r'RMT case \d+ check \d+: .+\n',message),(label,q.returncode,message);controls.append({'control':label,'detected':True,'failure':message.strip()});print(label+': detected',flush=True)
report={'pass':True,'scope_complete':False,'chip':'original ESP32','checks':checks,'official_values':72,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'limitations':['S3, carrier, legacy FIFO access, TX looping/wrap and active reference-counter reset remain unsupported','Virtual CPU/APB timing and divided RX quantization are functional; cross-revision and electrical behavior remain physical gates']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'checks':checks,'controls':len(controls)}))
