#!/usr/bin/env python3
"""Independent GL vertex byte layout, signed truncation and write-bound checks."""
import argparse,json,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'build/migration/vertex-packing');a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
rows=[]
for pipeline in ['ir','direct']:
    binary=out/('vertices-'+pipeline);records=out/(pipeline+'.bin')
    subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/ui/vertex-packing.flex'),'-o',str(binary)],cwd=ROOT,check=True)
    subprocess.run([str(binary),str(records)],cwd=ROOT,check=True)
    raw=records.read_bytes();assert len(raw)==2060*88
    for index in range(2060):
        row=raw[index*88:(index+1)*88];values=struct.unpack('<6q',row[:48])
        assert row[48:56]==row[80:88]==b'\xa5'*8,(pipeline,index,'vertex write crossed its 24-byte bounds')
        assert row[56:80]==struct.pack('<6I',*(v&0xffffffff for v in values)),(pipeline,index,'coordinate/UV/color/mode byte layout differs')
    rows.append(dict(pipeline=pipeline,vertices=2060,byte_exact=True,guards_intact=True))
    print('PASS',pipeline,'2,060 signed/high-word/random GL vertices match independent struct ABI and preserve guards',flush=True)
(out/'report.json').write_text(json.dumps(rows,indent=2)+'\n')
