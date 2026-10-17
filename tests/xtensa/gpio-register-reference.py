#!/usr/bin/env python3
"""Independent C-table and behavioral checks for ESP32/S3 GPIO/RTC emulation.
Supply local files pinned in soc-oracle/sources.json; never downloads tools.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--cc',default='cc');p.add_argument('--skip-controls',action='store_true')
a=p.parse_args();root=Path(__file__).resolve().parents[2];oracle=root/'tests/xtensa/soc-oracle';work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();reference=a.reference.resolve();headers={}
def run(args):return subprocess.run([str(x) for x in args],cwd=root,capture_output=True)
def checked(args):
 r=run(args);assert r.returncode==0,(args,r.stderr.decode(errors='replace'));return r
for source in json.loads((oracle/'sources.json').read_text()):
 parts=source['path'].split('/');name=source.get('chip',parts[1])+'/'+parts[-1];data=(reference/name).read_bytes();assert hashlib.sha256(data).hexdigest()==source['sha256'],name;headers[name]=source['sha256']
refs=[]
for chip,s3 in [('esp32',0),('esp32s3',1)]:
 d=work/chip;d.mkdir(exist_ok=True);official=reference/chip;definition=re.search(r'typedef struct \{[\s\S]*?\} rtc_io_desc_t;',(official/'rtc_io_periph.h').read_text()).group(0);rt=(official/'rtc_io_periph.c').read_text();rt=rt[rt.index('const int rtc_io_num_map'):];gpio=(official/'gpio_periph.c').read_text();arrays=[]
 for name in ['GPIO_PIN_MUX_REG','GPIO_HOLD_MASK']:arrays.append(re.search(r'const uint32_t '+name+r'\[.*?\]\s*=\s*\{[\s\S]*?\};',gpio).group(0))
 bitdefs=''.join(f'#define BIT{i} (UINT64_C(1)<<{i})\n' for i in range(64));includes=''.join(f'#include "{x}"\n' for x in ['soc_caps.h','rtc_io_channel.h','rtc_cntl_reg.h','rtc_io_reg.h','io_mux_reg.h']);(d/'pad-support.h').write_text(bitdefs+includes+definition+'\n'+rt+'\n'+'\n'.join(arrays)+'\n')
 binary=d/'c-reference';checked([a.cc,'-std=gnu11','-O2','-DSOC_CAPS_ECO_VER=3','-DS3='+str(s3),'-I'+str(d),'-I'+str(oracle),'-I'+str(official),oracle/'gpio-reference.c','-o',binary]);data=checked([binary]).stdout;shape=struct.unpack_from('<4Q',data);assert shape==(0x4750494f50414401,69,49 if s3 else 40,14);assert len(data)==32+(69+shape[2]*14)*8;ref=d/'reference.bin';ref.write_bytes(data);refs.append(ref)
fixture=root/'tests/xtensa/gpio-model.flex';binary=work/'model';checked([compiler,fixture,'-o',binary]);cases=[]
for chip,ref in zip(['esp32','esp32s3'],refs):
 result=checked([binary,ref]);match=re.fullmatch(rb'GPIO model: (\d+) checks passed\n',result.stdout);assert match;cases.append({'chip':chip,'checks':int(match[1]),'pad_slots':40 if chip=='esp32' else 49})
controls=[]
mutations=[
 ('incorrect-pad-metadata','esp32-gpio-pads.flex','3ff49044','3ff49048'),
 ('ignored-rtc-mux','esp32-gpio-emulator.flex','rtc=(pad&se_gpio_desc(s,pin,4))!=0;','rtc=0;'),
 ('wrong-s3-rtc-position','esp32-gpio-emulator.flex','if se_chip(s){return 10;}','if se_chip(s){return 14;}'),
 ('ignored-pad-hold','esp32-gpio-emulator.flex','if !held || !load64(p){','if 1{'),
 ('wrong-classic-shared-pulls','esp32-gpio-emulator.flex','(!se_chip(s) || rtc)','rtc'),
 ('wrong-s3-constant-zero','esp32-gpio-emulator.flex','if se_chip(s){zero=60;}','if se_chip(s){zero=48;}'),
 ('ignored-oe-override','esp32-gpio-emulator.flex','if !(matrix&(1<<10)){','if 1{'),
 ('ignored-rtc-open-drain','esp32-gpio-emulator.flex','if !open || !value{drive=value;}','drive=value;'),
 ('wrong-s3-force-hold','esp32-gpio-emulator.flex','return 0x600080d8;','return 0x600080dc;'),
 ('contention-partial-edge','esp32-gpio-emulator.flex','if value>=0 && other>=0 && value!=other{return -5;}','if value>=0 && other>=0 && value!=other{store64(s+152,load64(s+152)|16);return -5;}'),
 ('clipped-s3-high-bank','esp32-gpio-emulator.flex','return 0x3fffff;','return 0x1ffff;'),
 ('unmasked-high-status','esp32-emulator.flex','let bits=(value&se_gpio_bank_mask(s,shift!=0))<<shift;','let bits=value<<shift;'),
 ('unmasked-gpio-source','esp32-emulator.flex','se_source(s,source,se_gpio_cpu_status(s,0,0))','se_source(s,source,load64(s+152))'),
]
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
    message=result.stderr.decode();assert re.fullmatch(r'GPIO check \d+: .+\n',message),message;detected.append({'chip':chip,'failure':message.strip()})
  assert detected,label+' escaped verification';controls.append({'control':label,'detected':detected})
report={'pass':True,'cases':cases,'checks':sum(c['checks'] for c in cases),'global_values_per_chip':69,'pad_descriptor_words':(40+49)*14,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False,'limitations':['Dedicated peripheral IO_MUX functions, sleep/wakeup and analog behavior remain open','All pad slots are modeled; no all-pad physical test is implied']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'checks':report['checks'],'controls':len(controls),'cases':cases}))
