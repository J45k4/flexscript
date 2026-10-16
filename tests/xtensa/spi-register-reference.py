#!/usr/bin/env python3
"""Check the machine-code emulator's SPI against pinned C layouts and bitstreams.
Only local headers and an explicitly supplied compiler are used.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--cc',default='cc');p.add_argument('--skip-controls',action='store_true')
a=p.parse_args();root=Path(__file__).resolve().parents[2];oracle=root/'tests/xtensa/soc-oracle';work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();headers={}
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True)
def checked(args):
 r=run(args);assert r.returncode==0,(args,r.stdout.decode(errors='replace'),r.stderr.decode(errors='replace'));return r
for source in json.loads((oracle/'sources.json').read_text()):
 parts=source['path'].split('/');name=source.get('chip',parts[1])+'/'+parts[-1];data=(a.reference/name).read_bytes();assert hashlib.sha256(data).hexdigest()==source['sha256'],name;headers[name]=source['sha256']
refs=[]
for chip,s3 in [('esp32',0),('esp32s3',1)]:
 program=work/(chip+'-c');ref=work/(chip+'.bin');checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-DS3='+str(s3),'-I'+str(oracle),'-I'+str(a.reference.resolve()/chip),oracle/'spi-reference.c','-o',program]);ref.write_bytes(checked([program]).stdout);assert len(ref.read_bytes())==559568;refs.append(ref)
fixture=root/'tests/xtensa/spi-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);cases=[]
for chip,ref in zip(['esp32','esp32s3'],refs):
 result=checked([binary,ref]);match=re.fullmatch(rb'SPI model: (\d+) checks passed\n',result.stdout);assert match;cases.append({'chip':chip,'checks':int(match[1]),'edge_cases':416})
mutations=[
 ('wrong-clock-polarity','esp32-spi-emulator.flex','let level=cpol^(!trailing);','let level=!trailing;'),
 ('wrong-sampling-phase','esp32-spi-emulator.flex','let cpha=((user>>edge)&1)^cpol;','let cpha=((user>>edge)&1);'),
 ('ignored-tx-order','esp32-spi-emulator.flex','store64(p+80,txlsb);','store64(p+80,0);'),
 ('ignored-rx-order','esp32-spi-emulator.flex','store64(p+88,rxlsb);','store64(p+88,0);'),
 ('fake-tx-to-rx-echo','esp32-spi-emulator.flex','let level=se_gpio_signal(s,se_spi_signal(s,bus,2));','let level=se_spi_tx_bit(s,bus,bit);'),
 ('ignored-tx-high-half','esp32-spi-emulator.flex','txoff=32;','txoff=0;'),
 ('ignored-rx-high-half','esp32-spi-emulator.flex','rxoff=32;','rxoff=0;'),
 ('wrong-s3-xtal-frequency','esp32-spi-emulator.flex','factor=2;','factor=1;'),
 ('wrong-clock-high-count','esp32-spi-emulator.flex','high=h*pre*factor*2;','high=(h+1)*pre*factor*2;'),
 ('missing-clock-gate-freeze','esp32-spi-emulator.flex','store64(p+8,load64(p+8)+delta*2);',''),
 ('missing-original-completion','esp32-spi-emulator.flex','se_spi_get(s,bus,56)|16','se_spi_get(s,bus,56)'),
 ('wrong-original-irq-source','esp32-emulator.flex','source=28+id;','source=13+id;'),
 ('missing-s3-update','esp32-spi-emulator.flex','em_copy(p+1280,p+256,256);','em_zero(p+1280,256);'),
 ('premature-completion','esp32-spi-emulator.flex','edge==load64(p+40)*2','edge==load64(p+40)*2-1'),
 ('wrong-mosi-matrix-route','esp32-spi-emulator.flex','if kind==1{return 10;}','if kind==1{return 12;}'),
 ('clipped-original-length','esp32-spi-emulator.flex','let lenmask=0xffffff;','let lenmask=0x3ffff;'),
]
controls=[]
if not a.skip_controls:
 for label,module,old,new in mutations:
  d=work/label;d.mkdir(exist_ok=True)
  for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex','esp32-rmt-emulator.flex','esp32-i2c-emulator.flex','esp32-i2s-emulator.flex','esp32-clock-emulator.flex','esp32-cache-emulator.flex']:
   source=clone_source(root,name)
   if name==module:assert source.count(old)==1,(label,source.count(old));source=source.replace(old,new)
   source=source.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex'))));(d/name).write_text(source)
  text=fixture.read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(d/'esp32-emulator.flex'))).replace('"../../scripts/lib/host.flex"',json.dumps(str(root/'scripts/lib/host.flex')));test=d/'model.flex';test.write_text(text);binary=d/'model';checked([compiler,test,'-o',binary]);detected=[]
  for chip,ref in zip(['esp32','esp32s3'],refs):
   result=run([binary,ref]);assert result.returncode in (0,1),(label,result.returncode,result.stderr.decode(errors='replace'))
   if result.returncode:
    message=result.stderr.decode();assert re.search(r'SPI check \d+: .+\n',message),message;detected.append({'chip':chip,'failure':message.strip()})
  assert detected,label+' escaped verification';controls.append({'control':label,'detected':detected});print(label+': detected',flush=True)
report={'pass':True,'scope_complete':False,'cases':cases,'checks':sum(c['checks'] for c in cases),'global_values_per_chip':54,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'limitations':['Master FIFO data phases only; command/address/dummy, half duplex, DMA, slave, dual/quad/octal and extra timing modes remain T241/T223','Virtual CPU/APB timing is functional, not silicon cycle accuracy','SPI firmware is emulator-only evidence; earlier physical fixtures are separate provenance']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'checks':report['checks'],'controls':len(controls),'cases':cases}))
