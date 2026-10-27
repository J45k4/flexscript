#!/usr/bin/env python3
"""Full pinned UAX #14 default line-break conformance and property oracle."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CLASSES='AI AK AL AP AS B2 BA BB BK CB CJ CL CM CP CR EB EM EX GL H2 H3 HH HL HY ID IN IS JL JT JV LF NL NS NU OP PO PR QU RI SA SG SP SY VF VI WJ XX ZW ZWJ'.split()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',required=True,type=Path);a=p.parse_args()
    base=ROOT/'tests/tooling/unicode/17.0.0';out=ROOT/'build/migration/unicode-linebreak-tests';out.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((base/'manifest.json').read_text())
    for source in manifest['sources']:
        assert hashlib.sha256((base/source['file']).read_bytes()).hexdigest()==source['sha256'],source
    generator=out/'generator';generated=out/'line-properties.flex'
    subprocess.run([str(a.compiler.resolve()),str(ROOT/'scripts/unicode-line-properties.flex'),'-o',str(generator)],check=True)
    subprocess.run([str(generator),str(base),str(generated)],check=True)
    assert generated.read_bytes()==(ROOT/'libs/unicode/line-properties.flex').read_bytes(),'Regenerate line-break properties'
    # Deliberately parse the independent contributory LineBreak.txt here;
    # the Flexscript generator reads the derived table with @missing defaults.
    values=[46|1024]*0x110000
    for filename,kind in [('LineBreak.txt',0),('EastAsianWidth.txt',1),('extracted/DerivedGeneralCategory.txt',2),('emoji/emoji-data.txt',3)]:
        for raw in (base/filename).read_text().splitlines():
            raw=raw.split('#',1)[0].strip()
            if not raw:continue
            span,name=[f.strip() for f in raw.split(';')]
            bounds=[int(t,16) for t in span.split('..')];first,last=bounds[0],bounds[-1]
            if kind==0:mask=63;value=CLASSES.index(name)
            elif kind==1:mask=64;value=64 if name in ('F','W','H') else 0
            elif kind==2:mask=1920;value={'Mn':128,'Mc':128,'Pi':256,'Pf':512,'Cn':1024}.get(name,0)
            else:
                if name!='Extended_Pictographic':continue
                mask=value=2048
            for cp in range(first,last+1):values[cp]=(values[cp]&~mask)|value
    properties=struct.pack('<'+'H'*len(values),*values)
    requests=[];expected=[];sources=[]
    for line_number,raw in enumerate((base/'auxiliary/LineBreakTest.txt').read_text().splitlines(),1):
        raw=raw.split('#',1)[0].strip()
        if not raw:continue
        text=bytearray();bounds=[]
        for token in raw.split():
            if token=='÷':bounds.append(len(text))
            elif token!='×':text+=chr(int(token,16)).encode()
        requests.append(text.hex());expected.append(bounds);sources.append(line_number)
    official=len(requests)
    for text,bounds in [('',[0]),('\0a',[2]),('a b',[2,3]),('a\r\nb\nc',[3,5,6])]:
        requests.append(text.encode().hex());expected.append(bounds);sources.append('edge')
    path=out/'requests.json';path.write_text(json.dumps(requests))
    for pipeline in ('ir','direct'):
        binary=out/('linebreak-'+pipeline);output=out/('properties-'+pipeline+'.bin')
        subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/unicode/linebreak.flex'),'-o',str(binary)],check=True)
        result=subprocess.run([str(binary),str(path),str(output)],capture_output=True,text=True,timeout=120)
        (out/(pipeline+'.stderr.log')).write_text(result.stderr)
        assert result.returncode==0,(pipeline,result.returncode,result.stderr)
        results=[json.loads(line) for line in result.stdout.splitlines()]
        for i,(got,want) in enumerate(zip(results,expected,strict=True)):
            assert got==want,(pipeline,i,sources[i],bytes.fromhex(requests[i]),want,got)
        actual=output.read_bytes()
        if actual!=properties:
            mismatch=next(cp for cp in range(0x110000) if actual[cp*2:cp*2+2]!=properties[cp*2:cp*2+2])
            raise AssertionError((pipeline,'Property mismatch',hex(mismatch),values[mismatch],struct.unpack_from('<H',actual,mismatch*2)[0]))
        print(f'PASS {pipeline}: {official} official Unicode 17 line-break cases plus edges; all 1,114,112 properties',flush=True)
    report=dict(status='pass',unicode='17.0.0',official=official,edges=len(requests)-official,properties=0x110000,pipelines=['ir','direct'])
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':main()
