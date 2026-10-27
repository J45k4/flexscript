#!/usr/bin/env python3
"""Full pinned Unicode grapheme conformance plus independent property oracle.

Python is test orchestration/reference parsing only. The implementation and
property generator are Flexscript and have no external Unicode runtime.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
base=ROOT/'tests/tooling/unicode/17.0.0';out=ROOT/'build/migration/unicode-tests';out.mkdir(parents=True,exist_ok=True)
manifest=json.loads((base/'manifest.json').read_text())
for source in manifest['sources']:assert hashlib.sha256((base/source['file']).read_bytes()).hexdigest()==source['sha256'],source
generator=out/'unicode-properties';subprocess.run([str(a.compiler.resolve()),str(ROOT/'scripts/unicode-properties.flex'),'-o',str(generator)],check=True)
generated=out/'properties.flex';subprocess.run([str(generator),str(base),str(generated)],check=True)
assert generated.read_bytes()==(ROOT/'libs/unicode/properties.flex').read_bytes(),'Regenerate native Unicode properties'
values=bytearray(0x110000)
gcb=['Other','CR','LF','Control','Extend','ZWJ','Regional_Indicator','Prepend','SpacingMark','L','V','T','LV','LVT']
for file,kind in [('auxiliary/GraphemeBreakProperty.txt',0),('emoji/emoji-data.txt',1),('DerivedCoreProperties.txt',2)]:
    for raw in (base/file).read_text().splitlines():
        raw=raw.split('#',1)[0].strip()
        if not raw:continue
        fields=[s.strip() for s in raw.split(';')]
        if kind==0:value=gcb.index(fields[1]);mask=15
        elif kind==1:
            if fields[1]!='Extended_Pictographic':continue
            value=mask=16
        else:
            if fields[1]!='InCB':continue
            value={'Extend':32,'Linker':64,'Consonant':96}[fields[2]];mask=96
        span=fields[0].split('..');start=int(span[0],16);end=int(span[-1],16)
        for cp in range(start,end+1):values[cp]=(values[cp]&~mask)|value
requests=[];expected=[]
for raw in (base/'auxiliary/GraphemeBreakTest.txt').read_text().splitlines():
    raw=raw.split('#',1)[0].strip()
    if not raw:continue
    text=bytearray();boundaries=[]
    for token in raw.split():
        if token=='÷':boundaries.append(len(text))
        elif token!='×':text+=chr(int(token,16)).encode('utf-8')
    requests.append(text.hex());expected.append(boundaries)
# Additional degenerate/embedded-NUL and long emoji cases are not handpicked
# substitutes for the complete official corpus above.
for text,bounds in [('',[0]),('\0',[0,1]),('a\u0301',[0,3]),('🇫🇮🇸🇪',[0,8,16]),('👨‍👩‍👧‍👦',[0,25]),('क्\u200dष',[0,12])]:
    requests.append(text.encode().hex());expected.append(bounds)
path=out/'requests.json';path.write_text(json.dumps(requests))
for pipeline in ['ir','direct']:
    binary=out/f'grapheme-{pipeline}';subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/unicode/grapheme.flex'),'-o',str(binary)],check=True)
    property_file=out/f'properties-{pipeline}.bin'
    result=subprocess.run([str(binary),str(path),str(property_file)],capture_output=True,text=True,timeout=90)
    assert result.returncode==0,(pipeline,result.stderr)
    actual=json.loads(result.stdout)
    for i,(got,want) in enumerate(zip(actual,expected,strict=True)):assert got==want,(pipeline,i,bytes.fromhex(requests[i]),want,got)
    assert property_file.read_bytes()==values,(pipeline,'Full Unicode property oracle differs')
print(f'PASS IR/direct: {len(expected)} Unicode 17 grapheme cases, all 1,114,112 codepoint property values, strict UTF-8, bounds, navigation and generator reproducibility')
