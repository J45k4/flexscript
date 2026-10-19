#!/usr/bin/env python3
"""Verify unchanged original ESP32 LEDC/RMT drivers against pinned C definitions.

--reference supplies the local official files recorded in signal-oracle/sources.json.
The runner downloads neither a compiler nor vendor headers.
"""
import argparse, hashlib, json, re, struct, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--reference',type=Path,required=True)
p.add_argument('--work',type=Path,required=True)
p.add_argument('--report',type=Path)
p.add_argument('--cc',default='cc')
a=p.parse_args();r=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True)
compiler=a.compiler.resolve();official=a.reference.resolve();oracle=r/'tests/esp32/signal-oracle'
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
# Compile Espressif's real symbol bitfields, extracting only the declaration
# to avoid unrelated target HAL dependencies in a host reference program.
symbol=re.search(r'typedef union\s*\{[\s\S]*?\}\s*rmt_symbol_word_t;', (official/'rmt_types.h').read_text())
assert symbol
(w/'symbol-definition.h').write_text('#include <stdint.h>\n'+symbol.group(0)+'\n')
address=re.search(r'PROVIDE\s*\(\s*RMTMEM\s*=\s*(0x[0-9a-fA-F]+)',(official/'esp32.peripherals.ld').read_text())
assert address
(w/'memory-address.h').write_text('#define REFERENCE_RMTMEM '+address.group(1)+'\n')
reference=w/'reference.bin';program=w/'register-reference'
checked([a.cc,'-std=gnu11','-O2','-I'+str(w),'-I'+str(oracle),'-I'+str(official),oracle/'register-reference.c','-o',program])
reference.write_bytes(checked([program]).stdout);assert len(reference.read_bytes())==672
fixture=r/'tests/esp32/signal-register-model.flex';model=w/'model'
checked([compiler,fixture,'-o',model]);result=checked([model,reference])
assert len(result.stdout)==8 and not result.stderr
checks,=struct.unpack('<Q',result.stdout);assert checks>=4400
controls=[]
for label,module,old,new in [
 ('wrong-ledc-divider-shift','esp32-pwm.flex','(divisor<<5)|bits','(divisor<<4)|bits'),
 ('missing-ledc-low-speed-update','esp32-pwm.flex','config=config|16;','config=config|0;'),
 ('wrong-ledc-output-route','esp32-pwm.flex','signal=79+(channel&7)','signal=78+(channel&7)'),
 ('premature-initial-duty-start','esp32-pwm.flex','esp32_store32(base+12,0x40100400);let config','esp32_store32(base+12,0xc0100400);let config'),
 ('missing-duty-busy-guard','esp32-pwm.flex','if esp32_load32(base+12)&(1<<31)','if 0'),
 ('wrong-rmt-memory-base','esp32-rmt.flex','0x3ff56800+channel*256','0x3ff56400+channel*256'),
 ('wrong-rmt-event-stride','esp32-rmt.flex','channel*3','channel*4'),
 ('wrong-rmt-memory-owner','esp32-rmt.flex','c1=c1|(1<<5)','c1=c1|(1<<6)'),
 ('missing-rmt-shared-clock','esp32-rmt.flex','0x80000000','0x00000000'),
 ('premature-rmt-reuse','esp32-rmt.flex','store64(state+8,3);return error;','store64(state+8,0);return error;'),
 ('missing-rmt-region-reservation','esp32-rmt.flex','(er_memory_mask&mask)','0'),
 ('wrong-rmt-rx-block-count','esp32-rmt.flex','(blocks<<24)','(1<<24)'),
 ('short-rmt-rx-clear','esp32-rmt.flex','i<load64(state+48)*64','i<64'),
 ('missing-rmt-region-release','esp32-rmt.flex','er_memory_mask=er_memory_mask&~load64(state+56);',''),
 ('wrong-rmt-region-shift','esp32-rmt.flex','((1<<blocks)-1)<<channel','((1<<blocks)-1)'),
 ('missing-rmt-rx-capacity-check','esp32-rmt.flex','if capacity>load64(state+48)*64{return -22;}',''),
 ('over-released-rmt-region','esp32-rmt.flex','er_memory_mask=er_memory_mask&~load64(state+56);','er_memory_mask=0;'),
]:
    directory=w/label;directory.mkdir(exist_ok=True)
    for name in ['esp32-pwm.flex','esp32-rmt.flex','esp32-common.flex','esp32.flex']:
        text=(r/'lib/platform'/name).read_text()
        if name==module:
            assert old in text,label+' mutation pattern missing'
            text=text.replace(old,new)
        (directory/name).write_text(text)
    text=fixture.read_text()
    for name in ['esp32-pwm.flex','esp32-rmt.flex']:
        text=text.replace('"../../lib/platform/'+name+'"',json.dumps(str(directory/name)))
    source=directory/'model.flex';source.write_text(text);binary=directory/'model'
    checked([compiler,source,'-o',binary]);rejected=run([binary,reference])
    assert rejected.returncode==1 and len(rejected.stderr)==16,label+' defect was not detected cleanly'
    assertion,count=struct.unpack('<QQ',rejected.stderr)
    controls.append({'control':label,'detected':True,'assertion':assertion})
report={'pass':True,'native_checks':checks,'official_register_values':82,'reference_headers':headers,'negative_controls':controls,'physical_hardware':False}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
