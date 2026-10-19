#!/usr/bin/env python3
"""Original ESP32 ADC register, pad, lifecycle and radio-ownership oracle.

Provide official local headers matching adc-oracle/sources.json. No compiler
or vendor download. C bitfields and original GPIO/RTC descriptor tables supply
independent expected register addresses, masks and channel mappings.
"""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--reference',type=Path,required=True)
p.add_argument('--work',type=Path,required=True)
p.add_argument('--report',type=Path)
p.add_argument('--cc',default='cc')
a=p.parse_args();r=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);official=a.reference.resolve();compiler=a.compiler.resolve();oracle=r/'tests/esp32/adc-oracle'
def run(args):return subprocess.run([str(x) for x in args],cwd=r,capture_output=True)
def checked(args):
    result=run(args)
    assert result.returncode==0,(args,result.stderr.decode(errors='replace'))
    return result
headers={}
for source in json.loads((oracle/'sources.json').read_text()):
    name=Path(source['path']).name;data=(official/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==source['sha256'],name+' reference checksum mismatch'
    headers[name]=source['sha256']
# Extract declarations verbatim from the pinned C source instead of duplicating
# its pin/RTC/mux information or bringing in unrelated target HAL dependencies.
s=(official/'rtc_io_periph.h').read_text();definition=re.search(r'typedef struct \{[\s\S]*?\} rtc_io_desc_t;',s).group(0)
s=(official/'rtc_io_periph.c').read_text();mapping=s[s.index('const int rtc_io_num_map'):s.index('//Reg,Mux')];descriptors=s[s.index('const rtc_io_desc_t rtc_io_desc'):]
(w/'rtc-descriptors.h').write_text('#define SOC_GPIO_PIN_COUNT 40\n#define SOC_RTCIO_PIN_COUNT 18\n'+definition+'\n'+mapping+descriptors)
s=(official/'gpio_periph.c').read_text();mapping=re.search(r'const uint32_t GPIO_PIN_MUX_REG\[.*?\]\s*=\s*\{[\s\S]*?\};',s).group(0);(w/'gpio-mux.h').write_text(mapping+'\n')
program=w/'reference';reference=w/'reference.bin'
checked([a.cc,'-std=gnu11','-O2','-I'+str(w),'-I'+str(oracle),'-I'+str(official),oracle/'register-reference.c','-o',program]);reference.write_bytes(checked([program]).stdout)
assert len(reference.read_bytes())==2320
fixture=r/'tests/esp32/adc-register-model.flex';binary=w/'model';checked([compiler,fixture,'-o',binary]);result=checked([binary,reference]);assert len(result.stdout)==8 and not result.stderr
checks,=struct.unpack('<Q',result.stdout);assert checks>=17000
controls=[]
for label,old,new in [
 ('wrong-adc-channel-map','24252627202122230400020f0d0c0e1b191a','24252627202123220400020f0d0c0e1b191a'),
 ('wrong-rtc-input-mask','if pin<34{ie=1<<(shift-4);}','if pin==32{ie=1<<5;}'),
 ('wrong-rtc-force-hold','return 1<<(4+pin-36);','return 1<<(2+pin-36);'),
 ('wrong-adc2-register-offset','read=0x3ff48890;','read=0x3ff48824;'),
 ('missing-data-inversion','1|(3<<16)|inv);','1|(3<<16));'),
 ('missing-adc2-radio-guard','unit==2 && (esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs)','0'),
 ('stale-pwdet-after-radio','let busy=dig;if unit==2{busy=1<<28;}','let busy=dig;'),
 ('missing-phy-reference-guard','esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs','esp_radio_owner'),
 ('missing-shared-restoration','ea_restore();esp_adc_busy=0;','ea_saved_count=0;esp_adc_busy=0;'),
 ('missing-dac-sync-disable','ea_patch(0x3ff488a0,15,0);','ea_patch(0x3ff488a0,15,15);'),
 ('missing-unit-stop','if error{esp_reg_update(0x3ff4882c,stop,stop);}',''),
 ('missing-irq-mask','let ps=esp32_irq_save();','let ps=0;'),
]:
    directory=w/label;directory.mkdir(exist_ok=True)
    for name in ['esp32-adc.flex','esp32-analog-state.flex','esp32-common.flex','esp32.flex']:
        text=(r/'lib/platform'/name).read_text()
        if name=='esp32-adc.flex':
            assert old in text,label+' mutation pattern missing'
            text=text.replace(old,new)
        (directory/name).write_text(text)
    text=fixture.read_text().replace('"../../lib/platform/esp32-adc.flex"',json.dumps(str(directory/'esp32-adc.flex')))
    source=directory/'model.flex';source.write_text(text);binary=directory/'model';checked([compiler,source,'-o',binary]);rejected=run([binary,reference])
    assert rejected.returncode==1 and len(rejected.stderr)==16,label+' defect was not detected cleanly'
    assertion,count=struct.unpack('<QQ',rejected.stderr);controls.append({'control':label,'detected':True,'assertion':assertion})
report={'pass':True,'native_checks':checks,'official_register_and_pad_values':288,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
