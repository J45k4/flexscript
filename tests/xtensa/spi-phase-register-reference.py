#!/usr/bin/env python3
"""Check the machine-code emulator's SPI phases against pinned C layouts and logical wire bitstreams.
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
 program=work/(chip+'-c');ref=work/(chip+'.bin');checked([a.cc,'-std=gnu11','-O2','-Wall','-Wextra','-Werror','-DS3='+str(s3),'-I'+str(oracle),'-I'+str(a.reference.resolve()/chip),oracle/'spi-phase-reference.c','-o',program]);ref.write_bytes(checked([program]).stdout);assert len(ref.read_bytes())==2294448;refs.append(ref)
fixture=root/'tests/xtensa/spi-phase-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);cases=[]
for chip,ref in zip(['esp32','esp32s3'],refs):
 result=checked([binary,ref]);match=re.fullmatch(rb'SPI phase model: (\d+) checks passed\n',result.stdout);assert match;cases.append({'chip':chip,'checks':int(match[1]),'phase_cases':512})
mutations=[
 ('wrong-command-byte-order','esp32-spi-emulator.flex','load64(p+160)>>se_spi_bit_index(bit,lsb)','load64(p+160)>>bit'),
 ('wrong-address-lsb-order','esp32-spi-emulator.flex','index=56-(at&~7)+(at&7);','index=63-at;'),
 ('missing-upper-address-extension','esp32-spi-emulator.flex','addr=addr|se_spi_cfg(s,bus,48);',''),
 ('missing-command-phase','esp32-spi-emulator.flex','command=((u2>>28)&15)+1;','command=0;'),
 ('wrong-original-address-length','esp32-spi-emulator.flex','let addrshift=26;','let addrshift=27;'),
 ('wrong-dummy-count','esp32-spi-emulator.flex','dummy=(u1&255)+1;','dummy=u1&255;'),
 ('capture-during-prefix','esp32-spi-emulator.flex','let index=bit-load64(p+184);','let index=bit;'),
 ('half-duplex-rx-overlaps-tx','esp32-spi-emulator.flex','rxstart=rxstart+txlen;',''),
 ('half-duplex-clocks-omit-rx','esp32-spi-emulator.flex','data=txlen+rxlen;','data=txlen;'),
 ('old-original-cpha1-placement','esp32-spi-emulator.flex','if !se_chip(s) && cpha{store64(p+240,first);first=0;}',''),
 ('missing-cpha1-final-idle','esp32-spi-emulator.flex','let tail=load64(p+240);','let tail=0;'),
 ('cpha1-s3-accidental-change','esp32-spi-emulator.flex','if !se_chip(s) && cpha{','if cpha{'),
 ('missing-cs-setup','esp32-spi-emulator.flex','+first+load64(p+224)','+first'),
 ('missing-cs-hold','esp32-spi-emulator.flex','store64(p+232,hold*(high+low));','store64(p+232,0);'),
 ('coupled-cs-and-completion','esp32-spi-emulator.flex','store64(p+208,completion*(high+low));','store64(p+208,hold*(high+low));'),
 ('missing-completion-clock-freeze','esp32-spi-emulator.flex','if load64(p+216){store64(p+216,load64(p+216)+delta*2);}',''),
 ('ignored-clockless-dummy','esp32-spi-emulator.flex','store64(p+200,(user>>26)&1);','store64(p+200,0);'),
 ('missing-classic-rx-byte-clear','esp32-spi-emulator.flex','if !se_chip(s){em_zero(p+1600,(rxlen+7)/8);}',''),
 ('old-original-user-reset','esp32-spi-emulator.flex','se_spi_put(s,bus,28,0x80000040);','se_spi_put(s,bus,28,0x80000030);'),
 ('missing-original-ctrl-reset','esp32-spi-emulator.flex','se_spi_put(s,bus,8,0x0020a400);',''),
 ('missing-original-timing-reset','esp32-spi-emulator.flex','se_spi_put(s,bus,20,0x11);',''),
 ('missing-s3-slave-reset','esp32-spi-emulator.flex','se_spi_put(s,bus,224,0x02800000);',''),
 ('wrong-s3-setup-field','esp32-spi-emulator.flex','st=(u1>>17)&31;','st=(u1>>18)&31;'),
 ('wrong-s3-hold-field','esp32-spi-emulator.flex','ht=(u1>>22)&31;','ht=(u1>>23)&31;'),
 ('clockless-dummy-oscillator-phase','esp32-spi-emulator.flex','if !(cpol^(!trailing)){wait=load64(p+72);}','if !level{wait=load64(p+72);}')
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
    message=result.stderr.decode();assert re.search(r'SPI phase case \d+ check \d+: .+\n',message),message;detected.append({'chip':chip,'failure':message.strip()})
  assert detected,label+' escaped verification';controls.append({'control':label,'detected':detected});print(label+': detected',flush=True)
report={'pass':True,'scope_complete':False,'cases':cases,'checks':sum(c['checks'] for c in cases),'global_values_per_chip':82,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'limitations':['Command/address/dummy and four-line half/full duplex with setup/hold are modeled; DMA, slave, SIO, dual/quad/octal and signal delays remain T241/T223','Virtual CPU/APB timing is functional, not silicon cycle accuracy; unused MOSI levels outside transmit phases are not verified','SPI firmware is emulator-only evidence; earlier physical fixtures are separate provenance']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'checks':report['checks'],'controls':len(controls),'cases':cases}))
