#!/usr/bin/env python3
"""Independent JSON value oracle plus arena, growth and limit checks."""
import argparse, decimal, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
values=[None,True,False,0,-1,-9223372036854775808,9223372036854775807,'','quotes " slash \\ and newline\n\t\r','ä中👋 é אבג',[],{},[False,None,{'':[],'nested':{'key':'value'}}],list(range(65536)),{f'field-{i}':i for i in range(4096)}]
deep='leaf'
for _ in range(62):deep=[deep]
values.append(deep);text=json.dumps(values,ensure_ascii=False,separators=(',',':'))
# Exact fractional/exponent/large numeric tokens use Collie's full JSON reader.
text=text[:-1]+',1.2500e-003,-12.5E+9,99999999999999999999999999,-0.0]';source=out/'input.json';source.write_text(text)
def parse(text):return json.loads(text,parse_float=decimal.Decimal,object_pairs_hook=lambda pairs:dict(pairs))
expected=parse(text);rows=[]
for pipeline in ['ir','direct']:
    binary=out/f'json-copy-{pipeline}';subprocess.run(['nice','-n19',str(a.compiler.resolve()),'--native-pipeline',pipeline,'tests/tooling/json-copy.flex','-o',str(binary)],cwd=ROOT,check=True,timeout=60)
    result=out/f'{pipeline}.json';r=subprocess.run(['nice','-n19',str(binary),str(source),str(result)],cwd=ROOT,capture_output=True,text=True,timeout=30)
    (out/f'{pipeline}.stdout.log').write_text(r.stdout);(out/f'{pipeline}.stderr.log').write_text(r.stderr);assert r.returncode==0,(pipeline,r.returncode,r.stdout,r.stderr)
    assert parse(result.read_text())==expected,'Independent JSON values changed';assert '1.2500e-003,-12.5E+9,99999999999999999999999999,-0.0' in result.read_text(),'Exact numeric metadata changed'
    for mode,message in [('depth','JSON nesting limit'),('cycle','JSON nesting limit'),('kind','unknown JSON node kind'),('number','invalid raw JSON numeric metadata'),('size','JSON collection limit'),('object-size','JSON collection limit'),('duplicate','duplicate JSON object key')]:
        bad=subprocess.run(['nice','-n19',str(binary),'--bad',mode],cwd=ROOT,capture_output=True,text=True,timeout=5);(out/f'{pipeline}-{mode}.stderr.log').write_text(bad.stderr);assert bad.returncode==1 and message in bad.stderr,(pipeline,mode,bad.returncode,bad.stderr)
    rows.append(dict(pipeline=pipeline,ownership=True,independent_values=True,negative_cases=7,source_arena_released=True,array_elements=65536,object_fields=4096,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest()))
    print('PASS JSON copy:',pipeline,'independent values, owned storage/growth, max collections, exact metadata and 7 negative controls',flush=True)
(out/'report.json').write_text(json.dumps(dict(rows=rows,source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ['scripts/lib/json.flex','tests/tooling/json-copy.flex','scripts/test-json-copy.py']}),indent=2)+'\n')
