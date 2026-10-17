#!/usr/bin/env python3
"""Check ESP32/S3 machine-emulator devices against pinned local C headers.
No compiler/vendor downloads; supply the two chip directories in --reference.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--cc',default='cc')
a=p.parse_args();root=Path(__file__).resolve().parents[2];oracle=root/'tests/xtensa/soc-oracle';work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();headers={}
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True)
def checked(args):
 r=run(args);assert r.returncode==0,(args,r.stderr.decode(errors='replace'));return r
for source in json.loads((oracle/'sources.json').read_text()):
 parts=source['path'].split('/');name=source.get('chip',parts[1])+'/'+parts[-1];data=(a.reference/name).read_bytes();assert hashlib.sha256(data).hexdigest()==source['sha256'],name;headers[name]=source['sha256']
references=[]
for chip,s3 in [('esp32',0),('esp32s3',1)]:
 program=work/(chip+'-c');reference=work/(chip+'.bin');checked([a.cc,'-std=gnu11','-O2','-DS3='+str(s3),'-I'+str(oracle),'-I'+str(a.reference.resolve()/chip),oracle/'register-reference.c','-o',program]);reference.write_bytes(checked([program]).stdout);assert len(reference.read_bytes())==832;references.append(reference)
fixture=root/'tests/xtensa/board-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);cases=[]
for chip,reference in zip(['esp32','esp32s3'],references):
 result=checked([binary,reference]);match=re.fullmatch(rb'ESP board model: (\d+) checks passed\n',result.stdout);assert match;cases.append({'chip':chip,'checks':int(match[1])})
controls=[]
for label,old,new in [
 ('missing-uart-clock-freeze','store64(u+64,load64(u+64)+delta);',''),
 ('wrong-s3-uart-source','source=27+id;','source=26+id;'),
 ('wrong-s3-uart-threshold','if se_chip(s){mask=1023;shift=10;}',''),
 ('ignored-gpio-input-enable','if mux&512{ie=1;}','if 1{ie=1;}'),
 ('ignored-gpio-output-inversion','^((matrix>>9)&1)',''),
 ('wrong-gpio-set-alias','store64(p,old|bits);','store64(p,old&~bits);'),
 ('missing-timer-ack','store64(raw,load64(raw)&~value);','store64(raw,load64(raw));'),
 ('wrong-s3-counter-width','return 0x3fffffffffffff;','return 0xffffffff;'),
 ('wrong-timer-counter-latch','store64(t+16,load64(t+8));','store64(t+16,load64(t+8)+1);'),
 ('missing-uart-trace-preservation','store64(u+8,history);',''),
 ('fifo-count-includes-shifter','(load64(u+56)<<16)','((load64(u+56)+(load64(u)==1))<<16)'),
 ('missing-tx-complete-irq','store64(u+88,load64(u+88)|(1<<14));',''),
 ('wrong-s3-fsm-location','return se_uart_fsm(s,id)<<4;','return se_uart_fsm(s,id)<<24;'),
 ('missing-fractional-endpoint','store64(x+16,rest);','store64(x+16,0);'),
 ('missing-loopback','if load64(u+104)&(1<<14){se_uart_feed(s,id,u+16,1);}',''),
 ('wrong-s3-divider-mask','mask=0x00f00fff;','mask=0x00ffffff;'),
 ('missing-original-uart-reset-coupling','if !se_chip(s) && id==1{let other=se_uart(s,2);store64(other+48,0);store64(other+56,0);}',''),
 ('premature-tx-done-before-idle','if idle{store64(u,2);','if 0{store64(u,2);'),
 ('missing-timer-clock-gate',' || !se_enabled(s,13+(id/2)*2)',''),
]:
 directory=work/label;directory.mkdir(exist_ok=True);modules={name:clone_source(root,name) for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex']};matches=[name for name,source in modules.items() if old in source];module='esp32-emulator.flex' if label=='wrong-gpio-set-alias' else (matches[0] if len(matches)==1 else None);assert module and modules[module].count(old)==1,(label,matches);modules[module]=modules[module].replace(old,new)
 for name,source in modules.items():(directory/name).write_text(source.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex')))))
 model=directory/'esp32-emulator.flex';text=fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(model))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));test=directory/'model.flex';test.write_text(text);binary=directory/'model';checked([compiler,test,'-o',binary]);detected=[]
 for chip,reference in zip(['esp32','esp32s3'],references):
  result=run([binary,reference]);assert result.returncode in (0,1),(label,chip,result.stderr.decode(errors='replace'))
  if result.returncode:
   message=result.stderr.decode();assert re.fullmatch(r'Board check \d+: .+\n',message),(label,message);detected.append({'chip':chip,'failure':message.strip()})
 assert detected,label+' mutation escaped verification';controls.append({'control':label,'detected':detected})
report={'pass':True,'cases':cases,'checks':sum(x['checks'] for x in cases),'official_values_per_chip':102,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'scope':'UART FIFOs/clock/reset/selected IRQs, digital GPIO subset, timer groups. Full peripheral parity remains T223.'}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
